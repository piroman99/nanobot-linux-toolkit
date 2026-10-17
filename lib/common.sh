# shellcheck shell=sh
# Shared helpers for the nanobot Linux toolkit. Sourced, never executed.
#
# Override anything you like from the environment:
#   NANOBOT_URL           WebUI URL          (default http://127.0.0.1:8765/)
#   NANOBOT_LOG           gateway log        (default ~/nanobot-gateway.log)
#   NANOBOT_START_TIMEOUT seconds to wait    (default 30)

NANOBOT_URL="${NANOBOT_URL:-http://127.0.0.1:8765/}"
NANOBOT_LOG="${NANOBOT_LOG:-$HOME/nanobot-gateway.log}"
NANOBOT_START_TIMEOUT="${NANOBOT_START_TIMEOUT:-30}"

# Path of the shared library itself, so bin/* can fail with a useful message.
NANOBOT_TOOLKIT_LIB="${NANOBOT_TOOLKIT_LIB:-${XDG_DATA_HOME:-$HOME/.local/share}/nanobot-toolkit/common.sh}"

# Locate the `nanobot` launcher: PATH first, then the usual install spots
# (pipx, `uv tool install`, hand-made launchers in ~/.local/bin).
find_nanobot() {
    _n=$(command -v nanobot 2>/dev/null || true)
    if [ -z "$_n" ]; then
        for _c in \
            "$HOME/.local/bin/nanobot" \
            "$HOME"/.local/share/uv/tools/*/bin/nanobot \
            "$HOME"/.local/pipx/venvs/*/bin/nanobot
        do
            if [ -x "$_c" ]; then _n="$_c"; break; fi
        done
    fi
    printf '%s\n' "$_n"
}

# Is the gateway installed as a systemd --user unit?
service_installed() {
    systemctl --user list-unit-files 2>/dev/null | grep -q '^nanobot-gateway\.service'
}

gateway_running() { pgrep -x nanobot-gateway >/dev/null 2>&1; }

# Reachable over HTTP? (catches "process exists but is still booting")
gateway_webui_up() { curl -sf -m 2 "$NANOBOT_URL" >/dev/null 2>&1; }

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$@" >/dev/null 2>&1 || true
    fi
    return 0
}

# Start the gateway (service if installed, else detached background process)
# and wait until the WebUI answers. Returns non-zero on failure.
start_gateway() {
    if service_installed; then
        systemctl --user start nanobot-gateway >/dev/null 2>&1 || true
    else
        _nb=$(find_nanobot)
        if [ -z "$_nb" ]; then
            echo "nanobot launcher not found (pipx / uv tool / PATH)" >&2
            return 1
        fi
        setsid "$_nb" gateway --background >>"$NANOBOT_LOG" 2>&1 &
    fi
    _i=0
    while [ "$_i" -lt "$NANOBOT_START_TIMEOUT" ]; do
        gateway_webui_up && return 0
        sleep 1
        _i=$((_i + 1))
    done
    # Not answering, but maybe it is alive and just slow: report the truth.
    gateway_running && return 0
    return 1
}

# Stop the gateway and wait for the process to go away.
stop_gateway() {
    if service_installed; then
        systemctl --user stop nanobot-gateway >/dev/null 2>&1 || true
    else
        _nb=$(find_nanobot)
        if [ -n "$_nb" ]; then
            "$_nb" gateway stop >/dev/null 2>&1 || true
        fi
    fi
    _i=0
    while gateway_running && [ "$_i" -lt 15 ]; do
        sleep 1
        _i=$((_i + 1))
    done
    ! gateway_running
}

# Open the WebUI in the default browser.
open_chat() {
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$NANOBOT_URL" >/dev/null 2>&1 &
    elif command -v firefox >/dev/null 2>&1; then
        firefox "$NANOBOT_URL" >/dev/null 2>&1 &
    else
        notify "nanobot" "Open $NANOBOT_URL in your browser"
        return 1
    fi
    return 0
}
