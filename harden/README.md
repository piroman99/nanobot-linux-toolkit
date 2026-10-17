# harden — keep the model key away from `exec`

Goal: `exec` must not be able to read `~/.nanobot/config.json`, *without*
removing the `exec` tool and without breaking normal work (git over SSH, HTTPS,
headless Chromium).

Mechanism: `tools.exec.sandbox = "bwrap"` makes the gateway run every exec
command under bubblewrap and mount a fresh tmpfs over `~/.nanobot` (the config's
parent), then re-bind `~/.nanobot/workspace` read-write. Network namespaces are
left alone, so outbound traffic is unaffected.

## Order of operations

1. `sh userns_diagnose.sh` — can bwrap run on this host at all?
2. If not: `sudo sh fix_A_sysctl.sh` **or** `sudo sh fix_B_apparmor_bwrap.sh`.
3. `nanobot gateway stop` (or `systemctl --user stop nanobot-gateway`).
4. `python3 apply_bwrap_sandbox.py --apply --binds`.
5. `nanobot gateway start` / `nanobot-start.sh`.
6. `python3 verify_exec_sandbox.py`, then from the agent:
   `exec → cat ~/.nanobot/config.json` → expect *No such file or directory*.

## Files

| File | Purpose |
|---|---|
| `userns_diagnose.sh` | read-only: distro, sysctl keys, bwrap self-test |
| `fix_A_sysctl.sh` | blunt: allow unprivileged userns host-wide |
| `fix_B_apparmor_bwrap.sh` | narrow: AppArmor profile granting `userns,` to `/usr/bin/bwrap` |
| `bwrap.apparmor` | that profile |
| `apply_bwrap_sandbox.py` | writes `sandbox="bwrap"`, collapses duplicate bind keys, refuses while the gateway runs |
| `verify_exec_sandbox.py` | reports sandbox state and what a plain child process can read |

## Known traps

- **camelCase wins over snake_case.** With both `sandboxRoBinds: []` and
  `sandbox_ro_binds: [...]` in the file, the empty camelCase value is used and
  your binds vanish. Symptom: `ssh: No user exists for uid 1000`.
- **Never edit the config while the gateway runs.** It rewrites the file on
  start and normalises keys, dropping your change.
- **`/etc/passwd` is not bound by bwrap's defaults.** Add it, or ssh/git break.
- **Playwright**: needs `/dev/shm`; bind it read-write (`sandboxRwBinds`) if
  Chromium crashes with shared-memory errors.

Each `--apply` keeps `config.json.bak-<timestamp>`; roll back by copying it over
`config.json` with the gateway stopped.
