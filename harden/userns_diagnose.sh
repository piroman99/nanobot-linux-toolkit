#!/bin/sh
# Read-only diagnosis: why does bwrap fail on this host?
#   sh userns_diagnose.sh
# Nothing here needs root; it only prints state.
set -eu

echo "=== kernel / distro ==="
uname -r
. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"

echo
echo "=== apparmor userns restriction ==="
sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo "(sysctl key absent - older kernel, restriction not present)"
echo "user.max_user_namespaces = $(sysctl -n user.max_user_namespaces 2>/dev/null || echo '?')"

echo
echo "=== bwrap ==="
command -v bwrap || echo "bwrap NOT installed (apt install bubblewrap)"

echo
echo "=== /etc/apparmor.d/bwrap (if present) ==="
cat /etc/apparmor.d/bwrap 2>/dev/null || echo "(absent)"

echo
echo "=== bwrap self-test as the invoking user ==="
user=${BWRAP_USER:-${SUDO_USER:-$(id -un)}}
echo "user: $user"
if id "$user" >/dev/null 2>&1; then
    su -s /bin/sh -c 'bwrap --ro-bind / / true; echo "bwrap rc=$?"' "$user" 2>&1 || true
fi

echo
echo "=== interpretation ==="
echo "rc=0                        -> bwrap works, go straight to apply_bwrap_sandbox.py"
echo "rc!=0 + restrict_userns=1   -> run fix_A_sysctl.sh (blunt) or fix_B_apparmor_bwrap.sh (narrow)"
echo "'setting up uid map' error  -> same cause: unprivileged user namespaces are blocked"
