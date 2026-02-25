#!/usr/bin/env bash
# ntfy_ask.sh — Send a numbered-choice notification via ntfy and wait for a reply.
#
# Usage:
#   ntfy_ask.sh "Question" --options "Fix tests" "Revert" "Skip"
#   ntfy_ask.sh "Question"                           # free-text reply only
#   ntfy_ask.sh --notify "Status update"             # no reply expected
#
# The --options flag creates tappable buttons on the notification.
# ntfy supports up to 3 action buttons. If you pass more than 3 options,
# the first 3 become buttons and the rest are text-only (user types number).
#
# Environment (optional but recommended):
#   CLAUDE_NTFY_TOPIC    — Your ntfy topic name (auto-generated if not set)
#
# Environment (optional):
#   CLAUDE_NTFY_SERVER   — ntfy server URL (default: https://ntfy.sh)
#   CLAUDE_NTFY_TIMEOUT  — Seconds to wait for reply (default: 300)
#
# Authentication (optional — use ONE method):
#   CLAUDE_NTFY_TOKEN    — Access token (preferred, e.g. tk_AgQdq7mVBoFD37zQVN29RhuMzNIz2)
#   CLAUDE_NTFY_USER     — Username for basic auth (requires CLAUDE_NTFY_PASSWORD)
#   CLAUDE_NTFY_PASSWORD — Password for basic auth (requires CLAUDE_NTFY_USER)
#
# Token auth is preferred over basic auth. If both are set, token wins.
# Auth is applied to both outgoing notifications AND action button callbacks,
# so replies work on access-controlled topics.
#
# Security notes:
#   - Always use HTTPS for servers with auth (credentials are in headers)
#   - Use access tokens rather than passwords when possible
#   - On self-hosted: create a dedicated user/token with rw access to the topic
#   - Avoid sending secrets in message bodies (use for decisions only)

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
NTFY_SERVER="${CLAUDE_NTFY_SERVER:-https://ntfy.sh}"
TIMEOUT="${CLAUDE_NTFY_TIMEOUT:-300}"

# Generate a stable default topic from hostname + username if not set
if [[ -n "${CLAUDE_NTFY_TOPIC:-}" ]]; then
    NTFY_TOPIC="$CLAUDE_NTFY_TOPIC"
else
    TOPIC_HASH=$(echo -n "$(hostname)-$(whoami)" | sha256sum | cut -c1-12)
    NTFY_TOPIC="claude-${TOPIC_HASH}"
    echo "NOTE: CLAUDE_NTFY_TOPIC not set. Using auto-generated topic: ${NTFY_TOPIC}" >&2
    echo "      Subscribe to this topic in your ntfy app." >&2
fi

# Remove trailing slashes from server URL
NTFY_SERVER="${NTFY_SERVER%/}"

TOPIC_URL="${NTFY_SERVER}/${NTFY_TOPIC}"

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------
# Build auth header(s) and action auth params
AUTH_HEADER=""
ACTION_AUTH=""

if [[ -n "${CLAUDE_NTFY_TOKEN:-}" ]]; then
    # Token auth (preferred)
    AUTH_HEADER="Authorization: Bearer ${CLAUDE_NTFY_TOKEN}"
    # For http action buttons: pass auth as header so replies authenticate too
    ACTION_AUTH="headers.Authorization=Bearer ${CLAUDE_NTFY_TOKEN}"
elif [[ -n "${CLAUDE_NTFY_USER:-}" && -n "${CLAUDE_NTFY_PASSWORD:-}" ]]; then
    # Basic auth
    BASIC_CRED=$(echo -n "${CLAUDE_NTFY_USER}:${CLAUDE_NTFY_PASSWORD}" | base64)
    AUTH_HEADER="Authorization: Basic ${BASIC_CRED}"
    ACTION_AUTH="headers.Authorization=Basic ${BASIC_CRED}"
fi

# Helper: build curl auth args (reused for both sending and polling)
build_curl_auth_args() {
    if [[ -n "$AUTH_HEADER" ]]; then
        echo "-H" "$AUTH_HEADER"
    fi
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
NOTIFY_ONLY=false
MESSAGE=""
OPTIONS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notify)
            NOTIFY_ONLY=true
            shift
            ;;
        --options)
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                OPTIONS+=("$1")
                shift
            done
            ;;
        *)
            if [[ -z "$MESSAGE" ]]; then
                MESSAGE="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$MESSAGE" ]]; then
    echo "Usage: ntfy_ask.sh [--notify] \"message\" [--options \"opt1\" \"opt2\" \"opt3\"]" >&2
    exit 1
fi

MAX_OPTIONS=3
if [[ ${#OPTIONS[@]} -gt $MAX_OPTIONS ]]; then
    echo "ERROR: Maximum $MAX_OPTIONS options allowed (got ${#OPTIONS[@]}). ntfy only supports up to $MAX_OPTIONS action buttons." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
for cmd in curl jq base64; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not found." >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Validate HTTPS when using auth
# ---------------------------------------------------------------------------
if [[ -n "$AUTH_HEADER" && "$NTFY_SERVER" != https://* ]]; then
    echo "WARNING: Sending credentials over non-HTTPS connection (${NTFY_SERVER})." >&2
    echo "         Strongly consider using HTTPS to protect your token/password." >&2
fi

# ---------------------------------------------------------------------------
# Build the notification message and action buttons
# ---------------------------------------------------------------------------

# If options were provided, append a numbered list to the message body
if [[ ${#OPTIONS[@]} -gt 0 ]]; then
    MESSAGE="${MESSAGE}"$'\n'""
    for i in "${!OPTIONS[@]}"; do
        NUM=$((i + 1))
        MESSAGE="${MESSAGE}"$'\n'"${NUM}) ${OPTIONS[$i]}"
    done
    MESSAGE="${MESSAGE}"$'\n'""$'\n'"Tap a button or reply with a number (1-${#OPTIONS[@]}):"
fi

# Build Actions header — tappable buttons (max 3, enforced above)
ACTIONS_HEADER=""
if [[ ${#OPTIONS[@]} -gt 0 ]]; then
    ACTION_PARTS=()
    for i in $(seq 0 $((${#OPTIONS[@]} - 1))); do
        NUM=$((i + 1))
        LABEL="${NUM}) ${OPTIONS[$i]}"
        # ntfy http action format: http, <label>, <url>, method=POST, body=<reply>[, auth]
        ACTION_ENTRY="http, ${LABEL}, ${TOPIC_URL}, method=POST, body=${NUM}"
        if [[ -n "$ACTION_AUTH" ]]; then
            ACTION_ENTRY="${ACTION_ENTRY}, ${ACTION_AUTH}"
        fi
        ACTION_PARTS+=("$ACTION_ENTRY")
    done

    # Join actions with semicolons
    ACTIONS_HEADER=$(IFS=';'; echo "${ACTION_PARTS[*]}")
else
    # No predefined options — add a generic reply action
    if [[ -n "$ACTION_AUTH" ]]; then
        ACTIONS_HEADER="http, Reply, ${TOPIC_URL}, method=POST, headers.Title=Reply, ${ACTION_AUTH}"
    else
        ACTIONS_HEADER="http, Reply, ${TOPIC_URL}, method=POST, headers.Title=Reply"
    fi
fi

# ---------------------------------------------------------------------------
# Send the notification
# ---------------------------------------------------------------------------
# Record timestamp just before sending (unix epoch)
SEND_TIME=$(date +%s)

# Build curl command with optional auth
CURL_CMD=(curl -sf -X POST
    -H "Title: Claude Code"
    -H "Priority: high"
    -H "Tags: robot"
    -H "Actions: ${ACTIONS_HEADER}"
)

if [[ -n "$AUTH_HEADER" ]]; then
    CURL_CMD+=(-H "$AUTH_HEADER")
fi

CURL_CMD+=(-d "$MESSAGE" "$TOPIC_URL")

SEND_RESPONSE=$("${CURL_CMD[@]}" 2>&1) || {
    echo "ERROR: Failed to send notification. Check CLAUDE_NTFY_SERVER, CLAUDE_NTFY_TOPIC, and auth credentials." >&2
    echo "Response: $SEND_RESPONSE" >&2
    if [[ "$SEND_RESPONSE" == *"403"* || "$SEND_RESPONSE" == *"401"* ]]; then
        echo "HINT: Authentication failed. Check CLAUDE_NTFY_TOKEN or CLAUDE_NTFY_USER/CLAUDE_NTFY_PASSWORD." >&2
    fi
    exit 3
}

# Extract our own message ID so we can filter it out when polling
SENT_ID=$(echo "$SEND_RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)

if $NOTIFY_ONLY; then
    echo "OK: Notification sent."
    exit 0
fi

# ---------------------------------------------------------------------------
# Wait for reply
# ---------------------------------------------------------------------------
echo "Waiting for reply (timeout: ${TIMEOUT}s)..." >&2

END_TIME=$((SEND_TIME + TIMEOUT))

while true; do
    NOW=$(date +%s)
    if (( NOW >= END_TIME )); then
        echo "TIMEOUT"
        exit 1
    fi

    # Build poll curl with optional auth
    POLL_CMD=(curl -sf)
    if [[ -n "$AUTH_HEADER" ]]; then
        POLL_CMD+=(-H "$AUTH_HEADER")
    fi
    POLL_CMD+=("${TOPIC_URL}/json?since=${SEND_TIME}&poll=1")

    POLL_RESULT=$("${POLL_CMD[@]}" 2>/dev/null || true)

    if [[ -n "$POLL_RESULT" ]]; then
        # Filter out our own message and any "open" events, get the latest reply
        REPLY=$(echo "$POLL_RESULT" \
            | jq -r "select(.event == \"message\") | select(.id != \"${SENT_ID}\") | .message" 2>/dev/null \
            | tail -1)

        if [[ -n "$REPLY" ]]; then
            echo "$REPLY"
            exit 0
        fi
    fi

    # Wait before next poll
    sleep 3
done
