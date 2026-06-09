#!/usr/bin/env bash

# ========================================
# discord.sh v0.5
# Discord Bot Library for Bash
# ========================================

DISCORD_API="https://discord.com/api/v10"
DISCORD_TOKEN=""
DISCORD_PREFIX="!"
DISCORD_RUNNING=0
DISCORD_GATEWAY_URL=""
DISCORD_GATEWAY_PID=""

declare -A DISCORD_COMMANDS
declare -A DISCORD_COMMAND_DESCRIPTIONS
declare -A DISCORD_EVENTS

declare -A DISCORD_TASKS
declare -A DISCORD_TASK_LAST_RUN

# ========================================
# LOGGING
# ========================================

discord_log() {
    echo "[discord.sh] $*"
}

discord_error() {
    echo "[discord.sh ERROR] $*" >&2
}

# ========================================
# GATEWAY
# ========================================
discord_gateway_url() {
    local response
    response=$(discord_request GET "/gateway")
    echo "$response" | jq -r '.url'
}

discord_gateway_connect() {
    command -v websocat >/dev/null || {
        discord_error "websocat is not installed"
        return 1
    }
    local url
    url=$(discord_gateway_url)
    [[ -z "$url" ]] && {
        discord_error "Failed to obtain gateway URL"
        return 1
    }
    url="${url}/?v=10&encoding=json"
    discord_log "Connecting to Gateway..."
    websocat "$url"
}

discord_gateway_listen() {

    discord_gateway_connect | while read -r packet
    do
        echo
        echo "========== GATEWAY =========="
        echo "$packet"
        echo "============================="
        echo
    done
}

# ========================================
# AUTH
# ========================================

discord_login() {
    DISCORD_TOKEN="$1"

    [[ -z "$DISCORD_TOKEN" ]] && {
        discord_error "No token provided"
        return 1
    }
}

# ========================================
# CONFIG
# ========================================

discord_prefix() {
    DISCORD_PREFIX="$1"
}

# ========================================
# REST API
# ========================================

discord_request() {
    local method="$1"
    local endpoint="$2"
    local payload="$3"

    [[ -z "$DISCORD_TOKEN" ]] && {
        discord_error "Not logged in"
        return 1
    }

    if [[ -n "$payload" ]]; then
        curl -s \
            -X "$method" \
            -H "Authorization: Bot $DISCORD_TOKEN" \
            -H "Content-Type: application/json" \
            "${DISCORD_API}${endpoint}" \
            -d "$payload"
    else
        curl -s \
            -X "$method" \
            -H "Authorization: Bot $DISCORD_TOKEN" \
            -H "Content-Type: application/json" \
            "${DISCORD_API}${endpoint}"
    fi
}

# ========================================
# JSON
# ========================================

json_get() {
    echo "$1" | jq -r "$2"
}

json_pretty() {
    echo "$1" | jq .
}

# ========================================
# COMMANDS
# ========================================

discord_command() {
    local name="$1"
    local handler="$2"
    local description="$3"

    DISCORD_COMMANDS["$name"]="$handler"
    DISCORD_COMMAND_DESCRIPTIONS["$name"]="$description"
}

discord_alias() {
    local alias="$1"
    local target="$2"

    [[ -n "${DISCORD_COMMANDS[$target]}" ]] && {
        DISCORD_COMMANDS["$alias"]="${DISCORD_COMMANDS[$target]}"
        DISCORD_COMMAND_DESCRIPTIONS["$alias"]="Alias of $target"
    }
}

discord_execute_command() {
    local channel="$1"
    local content="$2"

    [[ "$content" != "$DISCORD_PREFIX"* ]] && return

    local cmd="${content#$DISCORD_PREFIX}"
    cmd="${cmd%% *}"

    local args="${content#"$DISCORD_PREFIX$cmd"}"
    args="${args# }"

    local handler="${DISCORD_COMMANDS[$cmd]}"

    [[ -z "$handler" ]] && return

    "$handler" "$channel" "$args"
}

discord_help_text() {
    local output="Available Commands:\n"

    for cmd in "${!DISCORD_COMMANDS[@]}"
    do
        output+="${DISCORD_PREFIX}${cmd} - ${DISCORD_COMMAND_DESCRIPTIONS[$cmd]}\n"
    done

    echo -e "$output"
}

discord_builtin_help() {
    local channel="$1"
    discord_send "$channel" "$(discord_help_text)"
}

# ========================================
# EVENTS
# ========================================

discord_on() {
    local event="$1"
    local fn="$2"

    DISCORD_EVENTS["$event"]+="$fn "
}

discord_emit() {
    local event="$1"
    shift

    for fn in ${DISCORD_EVENTS[$event]}
    do
        "$fn" "$@"
    done
}

# ========================================
# MESSAGES
# ========================================

discord_send() {
    local channel="$1"
    local message="$2"

    local payload

    payload=$(
        jq -n \
            --arg content "$message" \
            '{content:$content}'
    )

    discord_request POST "/channels/$channel/messages" "$payload"
}

discord_reply() {
    discord_send "$1" "$2"
}

discord_edit() {
    local channel="$1"
    local message_id="$2"
    local content="$3"

    local payload

    payload=$(
        jq -n \
            --arg content "$content" \
            '{content:$content}'
    )

    discord_request \
        PATCH \
        "/channels/$channel/messages/$message_id" \
        "$payload"
}

discord_delete() {
    local channel="$1"
    local message_id="$2"

    discord_request \
        DELETE \
        "/channels/$channel/messages/$message_id"
}

# ========================================
# EMBEDS
# ========================================

discord_embed() {
    local channel="$1"
    local title="$2"
    local description="$3"

    local payload

    payload=$(
        jq -n \
            --arg title "$title" \
            --arg description "$description" \
            '{
                embeds: [
                    {
                        title: $title,
                        description: $description
                    }
                ]
            }'
    )

    discord_request \
        POST \
        "/channels/$channel/messages" \
        "$payload"
}

discord_embed_color() {
    local channel="$1"
    local title="$2"
    local description="$3"
    local color="$4"

    local payload

    payload=$(
        jq -n \
            --arg title "$title" \
            --arg description "$description" \
            --argjson color "$color" \
            '{
                embeds: [
                    {
                        title: $title,
                        description: $description,
                        color: $color
                    }
                ]
            }'
    )

    discord_request \
        POST \
        "/channels/$channel/messages" \
        "$payload"
}

# ========================================
# REACTIONS
# ========================================

discord_react() {
    local channel="$1"
    local message="$2"
    local emoji="$3"

    local encoded
    encoded=$(printf '%s' "$emoji" | jq -sRr @uri)

    discord_request \
        PUT \
        "/channels/$channel/messages/$message/reactions/$encoded/@me"
}

# ========================================
# FILES
# ========================================

discord_send_file() {
    local channel="$1"
    local file="$2"

    curl -s \
        -H "Authorization: Bot $DISCORD_TOKEN" \
        -F "files[0]=@$file" \
        "${DISCORD_API}/channels/$channel/messages"
}

# ========================================
# USERS / GUILDS
# ========================================

discord_me() {
    discord_request GET "/users/@me"
}

discord_user() {
    discord_request GET "/users/$1"
}

discord_guild() {
    discord_request GET "/guilds/$1"
}

# ========================================
# PLUGINS
# ========================================

discord_load() {
    source "$1"
}

discord_load_dir() {
    local dir="$1"

    for file in "$dir"/*.sh
    do
        [[ -f "$file" ]] && source "$file"
    done
}

# ========================================
# SCHEDULER
# ========================================

discord_interval() {
    local seconds="$1"
    local fn="$2"

    DISCORD_TASKS["$fn"]="$seconds"
    DISCORD_TASK_LAST_RUN["$fn"]="0"
}

discord_scheduler_tick() {
    local now
    now=$(date +%s)

    for fn in "${!DISCORD_TASKS[@]}"
    do
        local interval="${DISCORD_TASKS[$fn]}"
        local last="${DISCORD_TASK_LAST_RUN[$fn]}"

        if (( now - last >= interval ))
        then
            "$fn"
            DISCORD_TASK_LAST_RUN["$fn"]="$now"
        fi
    done
}

# ========================================
# UTILITIES
# ========================================

discord_ping() {
    local start
    start=$(date +%s%N)

    discord_me >/dev/null

    local end
    end=$(date +%s%N)

    echo $(((end - start) / 1000000))
}

discord_version() {
    echo "discord.sh bash library v0.4"
}

# ========================================
# SHUTDOWN
# ========================================

discord_stop() {
    DISCORD_RUNNING=0
}

discord_shutdown() {
    discord_log "Shutting down..."
    DISCORD_RUNNING=0
}

# ========================================
# MAIN LOOP
# ========================================

discord_run() {

    trap discord_shutdown INT TERM

    discord_command \
        help \
        discord_builtin_help \
        "Shows available commands"

    discord_log "discord.sh v0.4 running"

    DISCORD_RUNNING=1

    discord_emit ready

    while (( DISCORD_RUNNING ))
    do
        discord_scheduler_tick
        sleep 1
    done

    discord_log "Stopped"
}
