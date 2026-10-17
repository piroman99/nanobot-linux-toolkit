#!/bin/sh
# Install the nanobot Linux toolkit: start/stop/toggle wrappers, app-menu and
# desktop icons, optionally a systemd --user service.
#
#   ./install.sh                  wrappers + icons (app menu and ~/Desktop)
#   ./install.sh --no-desktop     do not touch ~/Desktop
#   ./install.sh --with-service   also install nanobot-gateway.service
#   ./install.sh --help
#
# Everything lands in the standard per-user locations:
#   ~/.local/bin/nanobot-{start,stop,toggle,status}.sh
#   ~/.local/share/nanobot-toolkit/common.sh
#   ~/.local/share/applications/nanobot*.desktop
#   ~/.local/share/icons/hicolor/scalable/apps/nanobot.svg
#   ~/Desktop/nanobot*.desktop                      (unless --no-desktop)
# Remove it all again with ./uninstall.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)

BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA/applications"
ICONS="$DATA/icons/hicolor/scalable/apps"
LIBDIR="$DATA/nanobot-toolkit"
DESK="$HOME/Desktop"
ICON="$ICONS/nanobot.svg"

want_desktop=1
want_service=0

for arg in "$@"; do
    case "$arg" in
        --no-desktop) want_desktop=0 ;;
        --with-service) want_service=1 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

# --- 1. sanity --------------------------------------------------------------
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

nb=$(find_nanobot || true)
if [ -n "$nb" ]; then
    echo "nanobot launcher : $nb"
else
    echo "WARNING: no 'nanobot' launcher found (PATH, pipx, uv tool)." >&2
    echo "         Install nanobot first:  uv tool install nanobot-ai" >&2
    echo "         The wrappers look it up again on every run, so this is not fatal." >&2
fi

command -v pgrep >/dev/null 2>&1 || echo "WARNING: pgrep not found (procps package)." >&2
command -v curl >/dev/null 2>&1  || echo "WARNING: curl not found (used to wait for the WebUI)." >&2

# --- 2. wrappers ------------------------------------------------------------
mkdir -p "$BIN" "$LIBDIR"
install -m 0644 "$here/lib/common.sh" "$LIBDIR/common.sh"
for s in start stop toggle status; do
    install -m 0755 "$here/bin/nanobot-$s.sh" "$BIN/nanobot-$s.sh"
done
echo "wrappers         : $BIN/nanobot-{start,stop,toggle,status}.sh"
echo "library          : $LIBDIR/common.sh"

# --- 3. icon ----------------------------------------------------------------
mkdir -p "$ICONS"
install -m 0644 "$here/assets/nanobot.svg" "$ICON"
gtk-update-icon-cache -f -t "$DATA/icons/hicolor" >/dev/null 2>&1 || true

# --- 4. desktop entries -----------------------------------------------------
mkdir -p "$APPS"

entry() {
    out=$1; name=$2; comment=$3; exec=$4; icon=$5
    cat > "$out" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$comment
Exec=$exec
Icon=$icon
Terminal=false
Categories=Utility;Network;
StartupNotify=true
EOF
    chmod 0755 "$out"
}

entry "$APPS/nanobot.desktop" \
      "nanobot" \
      "Open the nanobot chat (starts the gateway if it is not running)" \
      "$BIN/nanobot-start.sh" \
      "$ICON"

entry "$APPS/nanobot-toggle.desktop" \
      "nanobot on/off" \
      "Toggle the nanobot gateway: start it if stopped, stop it if running" \
      "$BIN/nanobot-toggle.sh" \
      "media-playback-start"

entry "$APPS/nanobot-stop.desktop" \
      "Stop nanobot" \
      "Stop the nanobot gateway" \
      "$BIN/nanobot-stop.sh" \
      "process-stop"

echo "app menu         : $APPS/nanobot.desktop (+ nanobot-toggle, nanobot-stop)"

# --- 5. desktop icons -------------------------------------------------------
if [ "$want_desktop" -eq 1 ]; then
    mkdir -p "$DESK" 2>/dev/null || true
    if [ -d "$DESK" ]; then
        for n in nanobot nanobot-toggle nanobot-stop; do
            cp -f "$APPS/$n.desktop" "$DESK/$n.desktop"
            chmod 0755 "$DESK/$n.desktop"
            gio set "$DESK/$n.desktop" metadata::trusted true >/dev/null 2>&1 || true
        done
        echo "desktop icons    : $DESK/nanobot.desktop (+ toggle, stop)"
        echo "                   (right-click -> Allow Launching, if GNOME asks)"
    fi
fi

update-desktop-database "$APPS" >/dev/null 2>&1 || true

# --- 6. optional: systemd --user service -----------------------------------
if [ "$want_service" -eq 1 ]; then
    echo
    sh "$here/service/install-service.sh"
fi

cat <<EOF

Done. Try:
  $BIN/nanobot-status.sh
  $BIN/nanobot-toggle.sh      # on/off switch for the whole agent
EOF
