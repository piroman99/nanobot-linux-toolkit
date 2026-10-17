#!/bin/sh
# Print what the toolkit sees: launcher, process, WebUI, service unit.
#
#   nanobot-status
set -eu

NANOBOT_TOOLKIT_LIB="${NANOBOT_TOOLKIT_LIB:-${XDG_DATA_HOME:-$HOME/.local/share}/nanobot-toolkit/common.sh}"
if [ ! -r "$NANOBOT_TOOLKIT_LIB" ]; then
    echo "missing $NANOBOT_TOOLKIT_LIB - run ./install.sh first" >&2
    exit 1
fi
# shellcheck source=../lib/common.sh
. "$NANOBOT_TOOLKIT_LIB"

printf 'launcher : %s\n' "$(find_nanobot || true)"
if gateway_running; then
    printf 'process  : running (pid %s)\n' "$(pgrep -x nanobot-gateway | tr '\n' ' ' | sed 's/ $//')"
else
    printf 'process  : not running\n'
fi
if gateway_webui_up; then
    printf 'webui    : answering at %s\n' "$NANOBOT_URL"
else
    printf 'webui    : no answer at %s\n' "$NANOBOT_URL"
fi
if service_installed; then
    printf 'unit     : nanobot-gateway.service (systemd --user)\n'
    systemctl --user is-active nanobot-gateway 2>/dev/null | sed 's/^/           state: /' || true
else
    printf 'unit     : not installed (manual/background mode)\n'
fi
printf 'log      : %s\n' "$NANOBOT_LOG"
