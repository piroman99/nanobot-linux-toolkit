#!/bin/sh
# Self-contained smoke test: syntax, install into a throwaway HOME, toggle on/off
# with stubbed pgrep/curl/nanobot (so a live gateway is never touched), then the
# config rewrite. Nothing here writes outside ./_testhome.
#
#   sh test.sh
set -u
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
T=$ROOT/_testhome
rm -rf "$T"; mkdir -p "$T/bin" "$T/Desktop"

fail=0
chk() { # chk <label> <expected> <actual>
    if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (want '$2' got '$3')"; fail=$((fail+1)); fi
}

echo "== 1. syntax =="
for f in "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/lib/common.sh \
         "$ROOT"/bin/*.sh "$ROOT"/service/*.sh "$ROOT"/harden/*.sh; do
    sh -n "$f" || { echo "FAIL  syntax $f"; fail=$((fail+1)); }
done
echo "syntax pass"
python3 -m py_compile "$ROOT"/harden/*.py && echo "python compile pass" || fail=$((fail+1))

echo
echo "== 2. stubs =="
STATE=$T/state
cat > "$T/bin/nanobot" <<EOF
#!/bin/sh
case "\$*" in
  "gateway stop") rm -f "$STATE"; echo "fake: gateway stopped" ;;
  *"--background"*) : > "$STATE"; echo "fake: gateway started in background" ;;
  "gateway start"*) : > "$STATE"; echo "fake: started" ;;
  "gateway install-service"*) echo "fake: service installed" ;;
  *) echo "fake nanobot: \$*" ;;
esac
EOF
cat > "$T/bin/pgrep" <<EOF
#!/bin/sh
[ -f "$STATE" ] && { echo 4242; exit 0; }
exit 1
EOF
cat > "$T/bin/curl" <<EOF
#!/bin/sh
[ -f "$STATE" ] && exit 0
exit 7
EOF
cat > "$T/bin/systemctl" <<'EOF'
#!/bin/sh
exit 1   # pretend no user unit is installed
EOF
cat > "$T/bin/xdg-open" <<EOF
#!/bin/sh
echo "xdg-open \$*" >> "$T/opened"
EOF
chmod 0755 "$T/bin"/*

echo
echo "== 3. install (HOME=$T) =="
HOME="$T" PATH="$T/bin:$PATH" sh "$ROOT/install.sh" >"$T/install.log" 2>&1
chk "install exit" 0 $?
chk "start wrapper" yes "$([ -x "$T/.local/bin/nanobot-start.sh" ] && echo yes || echo no)"
chk "toggle wrapper" yes "$([ -x "$T/.local/bin/nanobot-toggle.sh" ] && echo yes || echo no)"
chk "lib installed" yes "$([ -f "$T/.local/share/nanobot-toolkit/common.sh" ] && echo yes || echo no)"
chk "icon installed" yes "$([ -f "$T/.local/share/icons/hicolor/scalable/apps/nanobot.svg" ] && echo yes || echo no)"
chk "app menu entries" 3 "$(ls "$T/.local/share/applications"/*.desktop 2>/dev/null | wc -l)"
chk "desktop icons" 3 "$(ls "$T/Desktop" | wc -l)"
grep -q "^Exec=$T/.local/bin/nanobot-toggle.sh" "$T/.local/share/applications/nanobot-toggle.desktop" \
    && echo "PASS  toggle desktop entry Exec" || { echo "FAIL  toggle desktop entry Exec"; fail=$((fail+1)); }

echo
echo "== 4. status (gateway down) =="
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ \
    "$T/.local/bin/nanobot-status.sh" >"$T/status1.log" 2>&1
chk "status exit" 0 $?
grep -q "process  : not running" "$T/status1.log" && echo "PASS  status: not running" || { echo "FAIL  status: not running"; fail=$((fail+1)); }
grep -q "no answer" "$T/status1.log" && echo "PASS  status: webui down" || { echo "FAIL  status: webui down"; fail=$((fail+1)); }

echo
echo "== 5. toggle ON =="
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ NANOBOT_START_TIMEOUT=3 \
    "$T/.local/bin/nanobot-toggle.sh" >"$T/toggle1.log" 2>&1
chk "toggle start exit" 0 $?
chk "gateway state file" yes "$([ -f "$STATE" ] && echo yes || echo no)"
grep -q "gateway: up at" "$T/toggle1.log" && echo "PASS  toggle: up message" || { echo "FAIL  toggle: up message"; fail=$((fail+1)); }
chk "chat opened once" 1 "$([ -f "$T/opened" ] && wc -l < "$T/opened" || echo 0)"

echo
echo "== 6. toggle OFF =="
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ \
    "$T/.local/bin/nanobot-toggle.sh" >"$T/toggle2.log" 2>&1
chk "toggle stop exit" 0 $?
chk "gateway state gone" no "$([ -f "$STATE" ] && echo yes || echo no)"
grep -q "gateway: stopped" "$T/toggle2.log" && echo "PASS  toggle: stopped message" || { echo "FAIL  toggle: stopped message"; fail=$((fail+1)); }

echo
echo "== 7. start --no-open / stop --quiet =="
rm -f "$STATE" "$T/opened"
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ NANOBOT_START_TIMEOUT=3 \
    "$T/.local/bin/nanobot-start.sh" --no-open >"$T/start.log" 2>&1
chk "start --no-open exit" 0 $?
chk "no browser opened" 0 "$([ -f "$T/opened" ] && wc -l < "$T/opened" || echo 0)"
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ \
    "$T/.local/bin/nanobot-stop.sh" --quiet >"$T/stop.log" 2>&1
chk "stop --quiet exit" 0 $?
grep -q "gateway: stopped" "$T/stop.log" && echo "PASS  stop message" || { echo "FAIL  stop message"; fail=$((fail+1)); }
HOME="$T" PATH="$T/bin:$PATH" NANOBOT_URL=http://127.0.0.1:9/ \
    "$T/.local/bin/nanobot-stop.sh" >"$T/stop2.log" 2>&1
grep -q "not running" "$T/stop2.log" && echo "PASS  stop when already down" || { echo "FAIL  stop when already down"; fail=$((fail+1)); }

echo
echo "== 8. uninstall =="
HOME="$T" PATH="$T/bin:$PATH" sh "$ROOT/uninstall.sh" >"$T/uninstall.log" 2>&1
chk "uninstall exit" 0 $?
chk "wrappers gone" 0 "$(ls "$T/.local/bin" | wc -l)"
chk "app entries gone" 0 "$(ls "$T/.local/share/applications"/*.desktop 2>/dev/null | wc -l)"
chk "desktop gone" 0 "$(ls "$T/Desktop" | wc -l)"
chk "lib gone" no "$([ -d "$T/.local/share/nanobot-toolkit" ] && echo yes || echo no)"

echo
echo "== 9. harden dry run (fake config) =="
mkdir -p "$T/.nanobot"
cat > "$T/.nanobot/config.json" <<'EOF'
{
  "tools": {
    "exec": {
      "sandbox": "",
      "sandboxRoBinds": [],
      "sandbox_ro_binds": ["/etc/passwd", "/etc/hosts"]
    }
  }
}
EOF
HOME="$T" NANOBOT_CONFIG="$T/.nanobot/config.json" python3 "$ROOT/harden/apply_bwrap_sandbox.py" --skip-bwrap-check >"$T/harden.log" 2>&1
chk "harden dry-run exit" 0 $?
grep -q "took the value of sandbox_ro_binds" "$T/harden.log" && echo "PASS  harden: camelCase trap detected" || { echo "FAIL  harden: camelCase trap detected"; fail=$((fail+1)); }
chk "config untouched by dry run" "" "$(python3 -c "import json,sys;print(json.load(open('$T/.nanobot/config.json'))['tools']['exec']['sandbox'])" 2>/dev/null)"

echo
echo "== 10. harden --apply =="
HOME="$T" NANOBOT_CONFIG="$T/.nanobot/config.json" python3 "$ROOT/harden/apply_bwrap_sandbox.py" --apply --binds --skip-bwrap-check >"$T/harden2.log" 2>&1
rc=$?
if [ "$rc" = 1 ] && grep -q "gateway is RUNNING" "$T/harden2.log"; then
    echo "PASS  guard: refuses to write while the gateway runs"
    echo "      (this test host has a live gateway - retrying with --force)"
    HOME="$T" NANOBOT_CONFIG="$T/.nanobot/config.json" python3 "$ROOT/harden/apply_bwrap_sandbox.py" --apply --binds --skip-bwrap-check --force >"$T/harden2.log" 2>&1
    rc=$?
fi
chk "apply exit" 0 "$rc"
if [ "$rc" = 0 ]; then
    chk "sandbox=bwrap" "bwrap" "$(python3 -c "import json;print(json.load(open('$T/.nanobot/config.json'))['tools']['exec']['sandbox'])")"
    chk "no snake_case left" "0" "$(python3 -c "import json;e=json.load(open('$T/.nanobot/config.json'))['tools']['exec'];print(len([k for k in e if '_binds' in k and k.startswith('sandbox_')]))")"
    chk "binds include /etc/passwd" "yes" "$(python3 -c "import json;b=json.load(open('$T/.nanobot/config.json'))['tools']['exec']['sandboxRoBinds'];print('yes' if '/etc/passwd' in b else 'no')")"
    chk "backup kept" yes "$(ls "$T/.nanobot"/config.json.bak-* >/dev/null 2>&1 && echo yes || echo no)"
    echo
    echo "  11. re-apply is a no-op"
    HOME="$T" NANOBOT_CONFIG="$T/.nanobot/config.json" python3 "$ROOT/harden/apply_bwrap_sandbox.py" --skip-bwrap-check >"$T/harden3.log" 2>&1
    grep -q "already enabled" "$T/harden3.log" && echo "PASS  idempotent" || { echo "FAIL  idempotent"; fail=$((fail+1)); }
else
    echo "SKIP  apply checks (unexpected failure):"
    tail -5 "$T/harden2.log"
    fail=$((fail+1))
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fail CHECK(S) FAILED"; fi
exit "$fail"
