#!/bin/sh
# One button: turn nanobot ON (start + open the chat) or OFF (stop).
#
# Bind it to a keyboard shortcut or a desktop icon and you have an on/off
# switch for the whole agent:
#
#   nanobot-toggle
set -eu

NANOBOT_TOOLKIT_LIB="${NANOBOT_TOOLKIT_LIB:-${XDG_DATA_HOME:-$HOME/.local/share}/nanobot-toolkit/common.sh}"
if [ ! -r "$NANOBOT_TOOLKIT_LIB" ]; then
    echo "missing $NANOBOT_TOOLKIT_LIB - run ./install.sh first" >&2
    exit 1
fi
# shellcheck source=../lib/common.sh
. "$NANOBOT_TOOLKIT_LIB"

if gateway_running; then
    echo "gateway: running -> stopping"
    if stop_gateway; then
        echo "gateway: stopped"
        notify "nanobot" "Gateway stopped"
    else
        echo "gateway: still running - stop it manually" >&2
        notify -u critical "nanobot" "Gateway did not stop"
        exit 1
    fi
else
    echo "gateway: stopped -> starting"
    if start_gateway; then
        echo "gateway: up at $NANOBOT_URL"
        notify "nanobot" "Gateway started"
        open_chat || true
    else
        echo "gateway: FAILED to start - see $NANOBOT_LOG" >&2
        notify -u critical "nanobot" "Gateway did not start. See $NANOBOT_LOG"
        exit 1
    fi
fi
