#!/usr/bin/env python3
"""Turn on nanobot's bubblewrap exec sandbox.

Why bother: without a sandbox, every `exec` command runs as your user and can
read `~/.nanobot/config.json`, which holds the model API key. With
`tools.exec.sandbox = "bwrap"`, nanobot mounts a tmpfs over the config's parent
directory for each exec child, so the key is invisible, while the workspace
stays read-write and the network is *not* unshared (git, ssh, HTTPS and
Playwright rendering keep working).

Usage
    python3 apply_bwrap_sandbox.py                  # inspect + dry run
    python3 apply_bwrap_sandbox.py --apply          # set sandbox = "bwrap"
    python3 apply_bwrap_sandbox.py --apply --binds  # ... and add the /etc binds
    python3 apply_bwrap_sandbox.py --config PATH    # non-default config
    python3 apply_bwrap_sandbox.py --apply --skip-bwrap-check
        # containers/CI, where bwrap cannot be nested-tested: write the
        # config anyway and verify on the host

Stop the gateway before --apply: a running gateway rewrites config.json on
start and would normalise/lose the edit. A timestamped backup is always kept.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

CONFIG = Path(os.environ.get("NANOBOT_CONFIG", Path.home() / ".nanobot" / "config.json"))

# Read-only binds that are almost always needed once exec is confined.
# /etc/passwd is the classic trap: without it `ssh` dies with
# "No user exists for uid 1000", which breaks every git-over-SSH push.
DEFAULT_RO_BINDS = [
    "/etc/passwd",
    "/etc/group",
    "/etc/nsswitch.conf",
    "/etc/hosts",
    "/etc/localtime",
]

# Canonical camelCase key <-> legacy snake_case alias.
# nanobot's config model uses alias_generator=to_camel + validate_by_alias, and
# when BOTH spellings exist the *camelCase* one wins - even if it is empty.
BIND_KEYS = [("sandboxRoBinds", "sandbox_ro_binds"), ("sandboxRwBinds", "sandbox_rw_binds")]


def bwrap_works() -> tuple[bool, str]:
    if not shutil.which("bwrap"):
        return False, "bwrap not installed (apt install bubblewrap)"
    r = subprocess.run(["bwrap", "--ro-bind", "/", "/", "true"], capture_output=True, text=True)
    if r.returncode == 0:
        return True, "ok"
    return False, (r.stdout + r.stderr).strip()[:300]


def gateway_running() -> bool:
    return subprocess.run(["pgrep", "-x", "nanobot-gateway"], capture_output=True).returncode == 0


def normalize_binds(exec_cfg: dict) -> list[str]:
    """Collapse duplicate camelCase/snake_case keys into the camelCase one."""
    notes = []
    for camel, snake in BIND_KEYS:
        has_c, has_s = camel in exec_cfg, snake in exec_cfg
        if has_c and has_s:
            if not exec_cfg[camel] and exec_cfg[snake]:
                exec_cfg[camel] = exec_cfg[snake]
                notes.append(f"{camel}: took the value of {snake}")
            del exec_cfg[snake]
            notes.append(f"{snake}: removed (duplicate alias of {camel})")
        elif has_s:
            exec_cfg[camel] = exec_cfg.pop(snake)
            notes.append(f"{snake}: renamed to {camel}")
    return notes


def add_binds(existing, wanted) -> tuple[list[str], list[str]]:
    out = [str(p) for p in (existing or [])]
    added = [p for p in wanted if p not in out]
    return out + added, added


def main() -> int:
    apply = "--apply" in sys.argv
    want_binds = "--binds" in sys.argv
    force = "--force" in sys.argv
    skip_check = "--skip-bwrap-check" in sys.argv
    cfg = CONFIG
    if "--config" in sys.argv:
        cfg = Path(sys.argv[sys.argv.index("--config") + 1])
    if "-h" in sys.argv or "--help" in sys.argv:
        print(__doc__)
        return 0

    print(f"config: {cfg}")
    print()

    # -- 1. can bwrap run at all? -------------------------------------------
    ok, msg = bwrap_works()
    print(f"[1] bwrap self-test: {'PASS' if ok else 'FAIL'} - {msg}")
    if not ok and skip_check:
        print("    --skip-bwrap-check: writing the config anyway.")
        ok = True
    if not ok:
        print(
            "\n    bwrap cannot create its sandbox. On Ubuntu 24.10+ this is\n"
            "    kernel.apparmor_restrict_unprivileged_userns=1, which blocks\n"
            "    user namespaces for unprivileged binaries.\n"
            "\n    Fix with ONE of these, then re-run this script:\n"
            "      A) sudo sh fix_A_sysctl.sh     # blunt: host-wide, weaker\n"
            "      B) sudo sh fix_B_apparmor_bwrap.sh   # narrow: only /usr/bin/bwrap\n"
            "\n    Inside a container bwrap usually cannot be nested-tested at all;\n"
            "    if you know it works on the host, pass --skip-bwrap-check.\n"
            "\n    Not touching the config."
        )
        return 1

    if not cfg.exists():
        print(f"[2] config not found: {cfg}")
        return 1

    if gateway_running() and apply and not force:
        print("[2] the gateway is RUNNING - stop it first (it rewrites the config on start)")
        print("    nanobot gateway stop   # or: systemctl --user stop nanobot-gateway")
        print("    Then re-run with --apply (or add --force if you know better).")
        return 1

    try:
        data = json.loads(cfg.read_text())
    except Exception as exc:  # noqa: BLE001
        print(f"[2] cannot parse {cfg}: {exc}")
        return 1

    exec_cfg = data.setdefault("tools", {}).setdefault("exec", {})
    cur = exec_cfg.get("sandbox")
    print(f"[2] current tools.exec.sandbox = {cur!r}")

    notes = normalize_binds(exec_cfg)
    new_ro, added = ([], [])
    if want_binds:
        new_ro, added = add_binds(exec_cfg.get("sandboxRoBinds"), DEFAULT_RO_BINDS)

    if cur == "bwrap" and not want_binds:
        print("    already enabled - nothing to do")
        return 0

    if not apply:
        print("\n[3] dry run. Would write:")
        print('    tools.exec.sandbox = "bwrap"')
        for n in notes:
            print(f"    bind fix: {n}")
        if want_binds:
            print(f"    tools.exec.sandboxRoBinds = {new_ro}")
            if added:
                print(f"    (+{len(added)}: {', '.join(added)})")
        else:
            print(f"    (optional) --binds adds {DEFAULT_RO_BINDS}")
        print("\n    Re-run with --apply to write. A timestamped backup is kept.")
        return 0

    backup = cfg.with_name(cfg.name + time.strftime(".bak-%Y%m%d-%H%M%S"))
    shutil.copy2(cfg, backup)

    exec_cfg["sandbox"] = "bwrap"
    if want_binds:
        exec_cfg["sandboxRoBinds"] = new_ro

    tmp = cfg.with_name(cfg.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(cfg)

    print(f"\n[3] written. backup: {backup}")
    print('    tools.exec.sandbox = "bwrap"')
    for n in notes:
        print(f"    bind fix: {n}")
    if want_binds:
        print(f"    tools.exec.sandboxRoBinds = {new_ro}")
    print("\n    Now start the gateway and verify from inside the agent:")
    print("      exec -> cat ~/.nanobot/config.json")
    print("    Expected: 'No such file or directory'.")
    print("    If git-over-SSH or Playwright break, run again with --apply --binds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
