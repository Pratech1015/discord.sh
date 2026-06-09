#!/usr/bin/env bash

# ========================================
# discord.sh
# Discord Bot Library for Bash
# ========================================

DISCORD_API="https://discord.com/api/v10"
DISCORD_TOKEN=""

declare -A DISCORD_EVENTS

# ========================================
# AUTH
# ========================================

discord_login() {
    DISCORD_TOKEN="$1"

    if [[ -z "$DISCORD_TOKEN" ]]; then
        echo "[discord.sh] No token provided"
        return 1
    fi

    return 0
}

# ========================================
# INTERNAL REQUEST
# ========================================

discord_request() {
    local method="$1"
    local endpoint="$2"
    local payload="$3"

    if [[ -z "$DISCORD_TOKEN" ]]; then
        echo "[discord.sh] Not logged in"
        return 1
    fi

    curl -s \
        -X "$method" \
        -H "Authorization: Bot $DISCORD_TOKEN" \
        -H "Content-Type: application/json" \
        "${DISCORD_API}${endpoint}" \
        -d "$payload"
}

# ========================================
# MESSAGE FUNCTIONS
# ========================================

discord_send() {
    local channel="$1"
    local message="$2"

    discord_request \
        POST \
        "/channels/$channel/messages" \
        "{\"content\":\"$message\"}"
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

    discord_request \
        PATCH \
        "/channels/$channel/messages/$message_id" \
        "{\"content\":\"$content\"}"
}

discord_delete() {
    local channel="$1"
    local message_id="$2"

    discord_request \
        DELETE \
        "/channels/$channel/messages/$message_id"
}

# ========================================
# CHANNELS
# ========================================

discord_channel() {
    local id="$1"

    discord_request GET "/channels/$id"
}

# ========================================
# USERS
# ========================================

discord_me() {
    discord_request GET "/users/@me"
}

discord_user() {
    local id="$1"

    discord_request GET "/users/$id"
}

# ========================================
# GUILDS
# ========================================

discord_guild() {
    local id="$1"

    discord_request GET "/guilds/$id"
}

# ========================================
# JSON HELPERS
# ========================================

json_get() {
    echo "$1" | jq -r "$2"
}

# ========================================
# EVENT SYSTEM
# ========================================

discord_on() {
    local event="$1"
    local function="$2"

    DISCORD_EVENTS["$event"]="$function"
}

discord_emit() {
    local event="$1"
    shift

    local fn="${DISCORD_EVENTS[$event]}"

    if [[ -n "$fn" ]]; then
        "$fn" "$@"
    fi
}

# ========================================
# LOGGING
# ========================================

discord_log() {
    echo "[discord.sh] $*"
}

# ========================================
# START
# ========================================

discord_run() {
    discord_log "Library loaded"

    discord_emit "ready"
}
