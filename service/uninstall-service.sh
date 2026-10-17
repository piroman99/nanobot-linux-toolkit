#!/bin/sh
# Remove the systemd --user unit installed by install-service.sh.
# The gateway keeps running until you stop or reboot; use nanobot-stop.sh.
#
#   ./service/uninstall-service.sh
set -eu

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/nanobot-gateway.service"

systemctl --user disable --now nanobot-gateway >/dev/null 2>&1 || true

if [ -f "$UNIT" ]; then
    rm -f "$UNIT"
    echo "removed $UNIT"
else
    echo "unit file not found: $UNIT"
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true
echo "done - the toolkit now falls back to background start/stop."
