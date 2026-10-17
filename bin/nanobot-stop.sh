#!/bin/sh
# Stop the nanobot gateway.
#
#   nanobot-stop         stop it, stay quiet on success
#   nanobot-stop --quiet no desktop notification
set -eu

NANOBOT_TOOLKIT_LIB="${NANOBOT_TOOLKIT_LIB:-${XDG_DATA_HOME:-$HOME/.local/share}/nanobot-toolkit/common.sh}"
if [ ! -r "$NANOBOT_TOOLKIT_LIB" ]; then
    echo "missing $NANOBOT_TOOLKIT_LIB - run ./install.sh first" >&2
    exit 1
fi
# shellcheck source=../lib/common.sh
. "$NANOBOT_TOOLKIT_LIB"

quiet=0
for arg in "$@"; do
    case "$arg" in
        --quiet|-q) quiet=1 ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    esac
done

if ! gateway_running; then
    echo "gateway: not running"
    [ "$quiet" -eq 1 ] || notify "nanobot" "Gateway is not running"
    exit 0
fi

if stop_gateway; then
    echo "gateway: stopped"
    [ "$quiet" -eq 1 ] || notify "nanobot" "Gateway stopped"
else
    echo "gateway: still running - stop it manually (Ctrl+C in its window)" >&2
    [ "$quiet" -eq 1 ] || notify -u critical "nanobot" "Gateway did not stop"
    exit 1
fi
