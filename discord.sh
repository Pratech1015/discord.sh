#!/usr/bin/env bash

# ========================================
# discord.sh v0.2
# Discord Bot Library for Bash
# ========================================

# ----------------------------------------
# Configuration
# ----------------------------------------

DISCORD_API="https://discord.com/api/v10"
DISCORD_TOKEN=""
DISCORD_PREFIX="!"

# ----------------------------------------
# Storage
# ----------------------------------------

declare -A DISCORD_COMMANDS
declare -A DISCORD_EVENTS

# ----------------------------------------
# Logging
# ----------------------------------------

discord_log() {
    echo "[discord.sh] $*"
}

discord_error() {
    echo "[discord.sh ERROR] $*" >&2
}

# ----------------------------------------
# Authentication
# ----------------------------------------

discord_login() {
    DISCORD_TOKEN="$1"

    if [[ -z "$DISCORD_TOKEN" ]]; then
        discord_error "No token provided"
        return 1
    fi

    return 0
}

# ----------------------------------------
# Configuration Functions
# ----------------------------------------

discord_prefix() {
    DISCORD_PREFIX="$1"
}

# ----------------------------------------
# REST API
# ----------------------------------------

discord_request() {
    local method="$1"
    local endpoint="$2"
    local payload="$3"

    if [[ -z "$DISCORD_TOKEN" ]]; then
        discord_error "Not logged in"
        return 1
    fi

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

# ----------------------------------------
# JSON Helpers
# ----------------------------------------

json_get() {
    echo "$1" | jq -r "$2"
}

json_pretty() {
    echo "$1" | jq .
}

# ----------------------------------------
# Commands
# ----------------------------------------

discord_command() {
    local name="$1"
    local handler="$2"

    DISCORD_COMMANDS["$name"]="$handler"
}

discord_alias() {
    local alias="$1"
    local command="$2"

    if [[ -n "${DISCORD_COMMANDS[$command]}" ]]; then
        DISCORD_COMMANDS["$alias"]="${DISCORD_COMMANDS[$command]}"
    fi
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

    if [[ -z "$handler" ]]; then
        return
    fi

    "$handler" "$channel" "$args"
}

# ----------------------------------------
# Events
# ----------------------------------------

discord_on() {
    local event="$1"
    local fn="$2"

    DISCORD_EVENTS["$event"]+="$fn "
}

discord_emit() {
    local event="$1"
    shift

    local handlers="${DISCORD_EVENTS[$event]}"

    for fn in $handlers
    do
        "$fn" "$@"
    done
}

# ----------------------------------------
# Messages
# ----------------------------------------

discord_send() {
    local channel="$1"
    local message="$2"

    local payload

    payload=$(
        jq -n \
        --arg content "$message" \
        '{content:$content}'
    )

    discord_request \
        POST \
        "/channels/$channel/messages" \
        "$payload"
}

discord_reply() {
    local channel="$1"
    local message="$2"

    discord_send "$channel" "$message"
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

# ----------------------------------------
# Channels
# ----------------------------------------

discord_channel() {
    local id="$1"

    discord_request GET "/channels/$id"
}

# ----------------------------------------
# Users
# ----------------------------------------

discord_me() {
    discord_request GET "/users/@me"
}

discord_user() {
    local id="$1"

    discord_request GET "/users/$id"
}

# ----------------------------------------
# Guilds
# ----------------------------------------

discord_guild() {
    local id="$1"

    discord_request GET "/guilds/$id"
}

# ----------------------------------------
# Reactions
# ----------------------------------------

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

# ----------------------------------------
# File Uploads
# ----------------------------------------

discord_send_file() {
    local channel="$1"
    local file="$2"

    curl -s \
        -H "Authorization: Bot $DISCORD_TOKEN" \
        -F "files[0]=@$file" \
        "${DISCORD_API}/channels/${channel}/messages"
}

# ----------------------------------------
# Plugin Loader
# ----------------------------------------

discord_load() {
    source "$1"
}

# ----------------------------------------
# Utility
# ----------------------------------------

discord_ping() {
    local start
    start=$(date +%s%N)

    discord_me >/dev/null

    local end
    end=$(date +%s%N)

    echo $(( (end - start) / 1000000 ))
}

# ----------------------------------------
# Startup
# ----------------------------------------

discord_run() {
    discord_log "Library loaded"

    discord_emit ready
}
