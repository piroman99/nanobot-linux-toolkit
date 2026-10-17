#!/bin/sh
# Start the nanobot gateway (if it is not already running) and open the WebUI.
#
#   nanobot-start            start + open the chat window
#   nanobot-start --no-open  start only (useful for scripts)
set -eu

NANOBOT_TOOLKIT_LIB="${NANOBOT_TOOLKIT_LIB:-${XDG_DATA_HOME:-$HOME/.local/share}/nanobot-toolkit/common.sh}"
if [ ! -r "$NANOBOT_TOOLKIT_LIB" ]; then
    echo "missing $NANOBOT_TOOLKIT_LIB - run ./install.sh first" >&2
    exit 1
fi
# shellcheck source=../lib/common.sh
. "$NANOBOT_TOOLKIT_LIB"

open_chat_after=1
for arg in "$@"; do
    case "$arg" in
        --no-open|--no-browser) open_chat_after=0 ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    esac
done

if gateway_running; then
    echo "gateway: already running"
else
    echo "gateway: starting ..."
fi

if start_gateway; then
    echo "gateway: up at $NANOBOT_URL"
else
    echo "gateway: FAILED to start - see $NANOBOT_LOG" >&2
    notify -u critical "nanobot" "Gateway did not start. See $NANOBOT_LOG"
    exit 1
fi

if [ "$open_chat_after" -eq 1 ]; then
    open_chat || true
fi
