# nanobot-linux-toolkit

Small, dependency-free shell helpers for running the [nanobot](https://github.com/HKUDS/nanobot)
personal AI agent on a Linux desktop — plus the recipe we use to keep the model
API key out of reach of the agent's own `exec` tool.

Unofficial: this repo is not part of nanobot, it only wraps it.
Tested on Ubuntu 24.04 (GNOME) with nanobot installed via `uv tool install nanobot-ai`.

Two independent parts:

| Part | What it gives you |
|---|---|
| **Launcher / on-off switch** | `nanobot-toggle` starts the gateway *and* opens the WebUI, or stops everything again. Plus app-menu and desktop icons, and an optional systemd `--user` service. |
| **Exec sandbox hardening** (`harden/`) | `tools.exec.sandbox = "bwrap"` so exec'd commands cannot read `~/.nanobot/config.json` (the model key), while git-over-SSH, HTTPS and Playwright keep working. Includes the two gotchas that cost us an evening. |

## Requirements

- Linux with a desktop that reads `~/.local/share/applications/*.desktop`
  (GNOME, KDE, XFCE...). Any POSIX `sh` will do — no bashisms.
- `curl`, `pgrep` (procps) for the wrappers.
- `bubblewrap` only if you want the exec sandbox: `sudo apt install bubblewrap`.
- nanobot itself: `uv tool install nanobot-ai` (or pipx). The wrappers look the
  launcher up in `PATH`, `~/.local/bin`, `~/.local/share/uv/tools/*/bin` and
  `~/.local/pipx/venvs/*/bin`, so the exact install method does not matter.

## Install the launcher

```sh
git clone https://github.com/piroman99/nanobot-linux-toolkit.git
cd nanobot-linux-toolkit
./install.sh                 # wrappers + app menu + desktop icons
./install.sh --no-desktop    # keep ~/Desktop clean
./install.sh --with-service  # also install nanobot-gateway.service
```

What lands where:

```
~/.local/bin/nanobot-start.sh          start (if needed) + open the chat
~/.local/bin/nanobot-stop.sh           stop
~/.local/bin/nanobot-toggle.sh         one button: on <-> off
~/.local/bin/nanobot-status.sh         what the toolkit sees
~/.local/share/nanobot-toolkit/common.sh
~/.local/share/applications/nanobot{,-toggle,-stop}.desktop
~/.local/share/icons/hicolor/scalable/apps/nanobot.svg
~/Desktop/nanobot{,-toggle,-stop}.desktop      (unless --no-desktop)
```

The WebUI is expected at `http://127.0.0.1:8765/`; override with
`NANOBOT_URL=...` if your gateway listens elsewhere.

### Use it

```sh
nanobot-toggle.sh          # off -> on: starts the gateway, opens the chat
nanobot-toggle.sh          # on -> off: stops it
nanobot-start.sh --no-open # just start it (scripts, cron)
nanobot-status.sh
```

Bind the toggle to a keyboard shortcut and you have a hardware-style on/off
switch for the whole agent. GNOME: *Settings → Keyboard → View and Customise
Shortcuts → Custom Shortcuts* → command `~/.local/bin/nanobot-toggle.sh`.
On the desktop, right-click the icon → *Allow Launching* once.

If the gateway is installed as a systemd user unit, all wrappers detect it and
use `systemctl --user` instead of spawning a background process.

### Run it as a service

```sh
./service/install-service.sh      # stops the current gateway, installs + enables the unit
./service/uninstall-service.sh
```

A gateway started in the foreground cannot be promoted in place — stop it first
(`Ctrl+C` in its window).

### Remove

```sh
./uninstall.sh
```

## Exec sandbox (`harden/`)

Out of the box, nanobot's `exec` tool runs as your user, so a command like
`cat ~/.nanobot/config.json` hands the model API key to whatever the agent (or a
prompt-injected page) asks it to run. Setting `tools.exec.sandbox = "bwrap"`
puts every exec command inside bubblewrap: nanobot mounts a tmpfs over
`~/.nanobot`, so the config is invisible, and re-binds the workspace read-write.
The network is **not** unshared — git/ssh/HTTPS keep working.

```sh
sh harden/userns_diagnose.sh                       # can bwrap even run here?
python3 harden/apply_bwrap_sandbox.py              # dry run
python3 harden/apply_bwrap_sandbox.py --apply --binds
nanobot-stop.sh && nanobot-start.sh                # restart, then verify
python3 harden/verify_exec_sandbox.py
```

Then, from inside the agent: `exec → cat ~/.nanobot/config.json` must answer
`No such file or directory`.

Verified behaviour (Ubuntu 24.04):

| Check | Before | After |
|---|---|---|
| exec reads `~/.nanobot/config.json` | readable (key leak) | hidden |
| workspace visible, `ls` / git / python | ok | ok |
| HTTPS + DNS | ok | ok |
| `git push` over SSH | ok | ok |
| headless Chromium render + screenshot | ok | ok |

### The two gotchas

1. **Ubuntu 24.10+ blocks bwrap.** `kernel.apparmor_restrict_unprivileged_userns=1`
   makes `bwrap` die with `setting up uid map: Permission denied`. On 24.04 it
   still works. If yours does not: `sudo sh harden/fix_A_sysctl.sh` (host-wide,
   blunt) or `sudo sh harden/fix_B_apparmor_bwrap.sh` (grants `userns,` to
   `/usr/bin/bwrap` only — preferred, minimal blast radius).

2. **`sandboxRoBinds` vs `sandbox_ro_binds`.** nanobot's config model uses
   `alias_generator=to_camel` + `validate_by_alias`. If a file contains *both*
   spellings, the **camelCase one wins even when it is empty**, and your binds
   are silently ignored. Without `/etc/passwd` bound, `ssh` fails with
   `No user exists for uid 1000`, which breaks every git push. Always edit the
   camelCase key; `apply_bwrap_sandbox.py` collapses duplicates for you.

   Also: **edit the config only while the gateway is stopped.** A running
   gateway rewrites `config.json` on start (normalising keys) and your edit is
   lost. The script refuses to `--apply` while `nanobot-gateway` is alive, and
   keeps a timestamped `.bak-*` next to the file.

Rollback: copy a `config.json.bak-*` over `config.json` with the gateway
stopped, then start it.

## Tests

```sh
sh test.sh
```

Self-contained: syntax-checks every script, installs into a throwaway
`./_testhome` with stubbed `nanobot`/`pgrep`/`curl`, exercises toggle on/off,
start/stop/status, uninstall, and the config rewrite (dry run, apply,
idempotent re-apply). A live gateway is never touched — if one happens to be
running on the test host, the test also asserts that `--apply` refuses to
write.

## Layout

```
install.sh  uninstall.sh  test.sh
lib/common.sh                 shared helpers (launcher lookup, start/stop, notify)
bin/nanobot-{start,stop,toggle,status}.sh
service/{install,uninstall}-service.sh
harden/apply_bwrap_sandbox.py  enable tools.exec.sandbox="bwrap" (+ bind fixes)
harden/verify_exec_sandbox.py  check config, bwrap, key visibility
harden/userns_diagnose.sh      read-only diagnosis of the AppArmor/userns block
harden/fix_A_sysctl.sh         blunt host-wide unblock
harden/fix_B_apparmor_bwrap.sh narrow per-binary unblock
assets/nanobot.svg
```

## License

MIT — see [LICENSE](LICENSE).
