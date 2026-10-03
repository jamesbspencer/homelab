#!/usr/bin/env bash
#
# notify.sh - Spencer's Homelab Push Notification Dispatcher
#
# Usage:
#   scripts/notify.sh [-t "Title"] [-p priority] [-g "tags,emojis"] [-a "Click URL"] <topic> <message>
#   echo "Message body" | scripts/notify.sh [-t "Title"] <topic>
#
# Priority levels:
#   1 / min:       Silent / low importance
#   2 / low:       Quiet
#   3 / default:   Normal sound/vibrate (default)
#   4 / high:      High urgency
#   5 / max:       Urgent / persistent alarm
#
set -euo pipefail

NTFY_URL="${NTFY_URL:-}"
EXTRA_CURL_FLAGS=()
if [ -z "$NTFY_URL" ]; then
    # Auto-detect if running inside Docker network or on host/LAN
    if getent hosts ntfy >/dev/null 2>&1; then
        NTFY_URL="http://ntfy:80"
    elif ping -c 1 -W 1 push.spencer.lan >/dev/null 2>&1; then
        NTFY_URL="https://push.spencer.lan"
    elif curl -sk --connect-timeout 1 --resolve push.spencer.lan:443:127.0.0.1 https://push.spencer.lan/v1/health >/dev/null 2>&1; then
        NTFY_URL="https://push.spencer.lan"
        EXTRA_CURL_FLAGS=(--resolve "push.spencer.lan:443:127.0.0.1" -k)
    else
        NTFY_URL="${NTFY_PUBLIC_URL:-https://push.spencer.lan}"
    fi
fi

TITLE=""
PRIORITY="3"
TAGS=""
CLICK_URL=""
TOPIC=""
MESSAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        -p|--priority)
            PRIORITY="$2"
            shift 2
            ;;
        -g|--tags)
            TAGS="$2"
            shift 2
            ;;
        -a|--action|--click)
            CLICK_URL="$2"
            shift 2
            ;;
        -u|--url)
            NTFY_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-t TITLE] [-p PRIORITY] [-g TAGS] [-a CLICK_URL] [-u NTFY_URL] <TOPIC> [MESSAGE]"
            exit 0
            ;;
        *)
            if [ -z "$TOPIC" ]; then
                TOPIC="$1"
            elif [ -z "$MESSAGE" ]; then
                MESSAGE="$1"
            else
                MESSAGE="$MESSAGE $1"
            fi
            shift
            ;;
    esac
done

if [ -z "$TOPIC" ]; then
    echo "Error: Topic is required." >&2
    echo "Usage: $0 [-t TITLE] [-p PRIORITY] [-g TAGS] [-a CLICK_URL] <TOPIC> [MESSAGE]" >&2
    exit 1
fi

# Read message from stdin if not provided as argument
if [ -z "$MESSAGE" ]; then
    if [ ! -t 0 ]; then
        MESSAGE="$(cat)"
    else
        echo "Error: Message body is required (either as argument or via stdin)." >&2
        exit 1
    fi
fi

CURL_ARGS=(
    -s
    -X POST
    "$NTFY_URL/$TOPIC"
    -d "$MESSAGE"
)

[ -n "$TITLE" ] && CURL_ARGS+=(-H "Title: $TITLE")
[ -n "$PRIORITY" ] && CURL_ARGS+=(-H "Priority: $PRIORITY")
[ -n "$TAGS" ] && CURL_ARGS+=(-H "Tags: $TAGS")
[ -n "$CLICK_URL" ] && CURL_ARGS+=(-H "Click: $CLICK_URL")

curl "${EXTRA_CURL_FLAGS[@]}" "${CURL_ARGS[@]}"
