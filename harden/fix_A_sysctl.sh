#!/bin/sh
# Fix A - blunt: allow unprivileged user namespaces for every program on the
# host. Needs root. Weaker than Fix B, but one line and easy to reason about.
#
#   sudo sh fix_A_sysctl.sh
#
# Undo:
#   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=1
#   sudo rm /etc/sysctl.d/99-unprivileged-userns.conf
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run me with sudo" >&2; exit 1; }

sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
printf 'kernel.apparmor_restrict_unprivileged_userns=0\n' \
    > /etc/sysctl.d/99-unprivileged-userns.conf
echo "wrote /etc/sysctl.d/99-unprivileged-userns.conf"

echo
user=${BWRAP_USER:-${SUDO_USER:-root}}
echo "--- bwrap self-test as $user ---"
if id "$user" >/dev/null 2>&1; then
    su -s /bin/sh -c 'bwrap --ro-bind / / true; echo "bwrap rc=$?"' "$user" 2>&1
fi

echo
echo "NOTE: this lowers host hardening globally; Fix B scopes it to bwrap only."
echo "Next: python3 apply_bwrap_sandbox.py --apply --binds"
