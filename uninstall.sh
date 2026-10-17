#!/bin/sh
# Remove everything install.sh created. The gateway itself is left running
# unless you also stop it (nanobot-stop.sh) or uninstall the service
# (service/uninstall-service.sh).
#
#   ./uninstall.sh
set -eu

BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA/applications"
DESK="$HOME/Desktop"

removed=0
rm_one() {
    if [ -e "$1" ]; then
        rm -f "$1"
        echo "removed $1"
        removed=$((removed + 1))
    fi
}

for s in start stop toggle status; do
    rm_one "$BIN/nanobot-$s.sh"
done
rm_one "$DATA/nanobot-toolkit/common.sh"
rmdir "$DATA/nanobot-toolkit" 2>/dev/null || true

for n in nanobot nanobot-toggle nanobot-stop; do
    rm_one "$APPS/$n.desktop"
    rm_one "$DESK/$n.desktop"
done
rm_one "$DATA/icons/hicolor/scalable/apps/nanobot.svg"

update-desktop-database "$APPS" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$DATA/icons/hicolor" >/dev/null 2>&1 || true

[ "$removed" -eq 0 ] && echo "nothing to remove (already clean)" || echo "done ($removed files)"
