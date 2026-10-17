#!/bin/sh
# Fix B - preferred: grant ONLY /usr/bin/bwrap the right to create user
# namespaces, keeping Ubuntu's host-wide restriction enabled. Needs root.
#
#   sudo sh fix_B_apparmor_bwrap.sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run me with sudo" >&2; exit 1; }

here=$(cd "$(dirname "$0")" && pwd)
src="$here/bwrap.apparmor"
dst=/etc/apparmor.d/bwrap

[ -f "$src" ] || { echo "missing $src" >&2; exit 1; }

install -m 0644 -b "$src" "$dst"
apparmor_parser -r "$dst"
echo "installed + loaded $dst"

echo
echo "--- verification ---"
if [ -r /sys/kernel/security/apparmor/profiles ]; then
    grep -i bwrap /sys/kernel/security/apparmor/profiles || echo "profile NOT in kernel list"
fi

user=${BWRAP_USER:-${SUDO_USER:-root}}
echo "--- bwrap self-test as $user ---"
if id "$user" >/dev/null 2>&1; then
    su -s /bin/sh -c 'bwrap --ro-bind / / true; echo "bwrap rc=$?"' "$user" 2>&1
fi

echo
echo "If rc=0: next step is  python3 apply_bwrap_sandbox.py --apply --binds"
echo "then restart the nanobot gateway."
