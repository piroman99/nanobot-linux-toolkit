#!/bin/sh
# Install the nanobot gateway as a systemd --user service, so it starts on
# login, survives closing terminals, and can be controlled with systemctl.
#
#   ./service/install-service.sh
#
# Note: the currently running gateway is stopped first. A gateway started in
# the foreground (a terminal) cannot be promoted to a service in place.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

nb=$(find_nanobot || true)
[ -n "$nb" ] || { echo "nanobot launcher not found (pipx / uv tool / PATH)" >&2; exit 1; }
echo "nanobot launcher : $nb"

if service_installed; then
    echo "service already installed - reinstalling"
fi

echo "== stopping the running gateway =="
if gateway_running; then
    "$nb" gateway stop >/dev/null 2>&1 || true
    i=0
    while gateway_running && [ "$i" -lt 15 ]; do sleep 1; i=$((i + 1)); done
    if gateway_running; then
        echo "gateway still running - stop it (Ctrl+C in its window) and retry" >&2
        exit 1
    fi
fi
echo "stopped"

echo "== installing the unit =="
"$nb" gateway install-service --manager systemd

echo "== enabling start on login =="
if loginctl enable-linger "$USER" 2>/dev/null; then
    echo "linger enabled for $USER"
else
    echo "linger skipped - run manually: sudo loginctl enable-linger $USER"
fi

echo "== status =="
systemctl --user --no-pager status nanobot-gateway 2>/dev/null | head -10 || true

cat <<EOF

Control it with:
  systemctl --user start|stop|restart|status nanobot-gateway
The toolkit wrappers detect the unit and use systemctl automatically.
EOF
