#!/usr/bin/env python3
"""Check whether the exec sandbox is on and whether the key is reachable.

Run it as your own user (a normal terminal), then confirm the last step from
inside the agent, because the sandbox only applies to exec children spawned by
the gateway:

    exec -> cat ~/.nanobot/config.json      # expect: No such file or directory
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

CFG = Path(os.environ.get("NANOBOT_CONFIG", Path.home() / ".nanobot" / "config.json"))


def main() -> int:
    print("== bwrap ==")
    print("path     :", shutil.which("bwrap"))
    r = subprocess.run(["bwrap", "--ro-bind", "/", "/", "true"], capture_output=True, text=True)
    print("self-test: rc =", r.returncode, (r.stderr or "").strip()[:200])

    print("\n== config ==")
    data = {}
    if CFG.exists():
        data = json.loads(CFG.read_text())
        ex = data.get("tools", {}).get("exec", {})
        print("file     :", CFG)
        print("sandbox  :", repr(ex.get("sandbox")))
        print("ro binds :", ex.get("sandboxRoBinds"))
        print("rw binds :", ex.get("sandboxRwBinds"))
        dup = [k for k in ("sandbox_ro_binds", "sandbox_rw_binds") if k in ex]
        if dup:
            print("WARNING  : snake_case duplicates present:", dup)
            print("           the camelCase key wins; if it is empty, your binds are")
            print("           silently ignored. Fix: apply_bwrap_sandbox.py --apply --binds")
    else:
        print("config not found:", CFG)

    print("\n== key visibility from a plain child process ==")
    print("(this is what an exec child sees when the sandbox is OFF)")
    code = (
        "import json,os;p=os.path.expanduser('~/.nanobot/config.json');"
        "k=json.load(open(p)).get('providers',{}).get('custom',{}).get('apiKey','');"
        "print('key readable, length =', len(k))"
    )
    p = subprocess.run(["python3", "-c", code], capture_output=True, text=True)
    print("rc:", p.returncode, "|", (p.stdout or p.stderr).strip()[:160])

    print("\n== findings ==")
    on = data.get("tools", {}).get("exec", {}).get("sandbox") == "bwrap"
    print("sandbox enabled in config:", "yes" if on else "NO")
    print("bwrap usable             :", "yes" if r.returncode == 0 else "NO")
    if on and r.returncode == 0:
        print("-> run `cat ~/.nanobot/config.json` via the exec tool; it must fail.")
        return 0
    print("-> finish the setup: apply_bwrap_sandbox.py --apply --binds, restart the gateway")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
