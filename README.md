# rdp-connect

RDP connection framework for Hyprland/Wayland built on `xfreerdp3`.

## What it does

- **Profile-based connections**: each server is an `.env` file under `~/.config/rdp/profiles/`
- **Graphical selector**: `wofi`/`rofi` menu when invoked without args
- **Hyprland integration**: auto workspaces, window rules, multi-monitor, HiDPI scaling (jq-native, no `bc`/`python3`)
- **Security**: hardened env parser (no `source` — allowlist + quote/comment handling), password piped via stdin (hidden from `ps aux`), `flock` single-instance guard, uid-private PID path under `XDG_RUNTIME_DIR`
- **Robustness**: strict mode (`set -euo pipefail`), `require_cmd` preflight for every external binary, `/from-stdin:force` build gate, array-based flag expansion
- **Pre-flight checks**: TCP socket probe on port 3389 before launching
- **i18n**: Spanish/English message dictionaries, auto-detected from `$LANG`
- **Auditing**: per-profile logs under `~/.local/state/rdp/`

## Requirements

`hyprctl` (Hyprland) is a **hard requirement** — the engine probes it at startup and refuses to start (exit 127) if absent.

| Binary | Purpose | pacman | apt | dnf |
|---|---|---|---|---|
| `xfreerdp3` | RDP client (must support `/from-stdin:force`) | `freerdp3` | `freerdp3-x11` | `freerdp` |
| `jq` | HiDPI scale math + monitor parsing | `jq` | `jq` | `jq` |
| `flock` | Single-instance guard | `util-linux` | `util-linux` | `util-linux` |
| `notify-send` | Desktop notifications | `libnotify` | `libnotify-bin` | `libnotify` |
| `wofi` **or** `rofi` | Graphical profile selector | `wofi` | `wofi` | `wofi` |
| `hyprctl` | Hyprland IPC (workspace/monitor rules) | `hyprland` | `hyprland`\* | `hyprland` |
| `shellcheck` | Smoke-test linter (optional) | `shellcheck` | `shellcheck` | `shellcheck` |

\* `hyprland` is **not in Debian main** — install it from a PPA, backports, or build from source ([Hyprland wiki](https://wiki.hyprland.org/)). The installer warns but does not fail on Debian if `hyprctl` is absent; the engine's `require_cmd` gate catches it at startup.

`bc` and `python3` are deliberately **not** required — HiDPI scale math is done via jq.

## Install

```bash
./install-rdp-framework.sh
```

The installer:
1. **Detects your distro** via `/etc/os-release` (pacman → dnf → apt order). Unsupported distros (Alpine, NixOS, etc.) are rejected with a manual-install reference.
2. **Installs missing dependencies** via the detected package manager (only missing ones — existing installs are preserved).
3. **Deploys files** idempotently via `install -D` (running twice produces byte-identical state).
4. **Runs a smoke test**: `bash -n` + `shellcheck` + `rdp-connect --help` (must exit 0) + parser probe (hostile profile must be rejected). Failure aborts the install.
5. **Writes a SHA-256 checksum manifest** to `~/.local/state/rdp/manifest.sha256` for reproducibility.

Then edit `~/.config/rdp/profiles/<name>.env` to set real credentials.

## Usage

| Command | Function |
|---|---|
| `rdp-connect` | Open graphical selector (wofi/rofi) |
| `rdp-connect <profile>` | Direct connection to a profile |
| `rdp-connect --new <name>` | Create a new profile from template |
| `rdp-connect --log <profile>` | Tail the profile's audit log |
| `rdp-connect --help` | Show help |

## File layout

| Deployed path | Source | Mode |
|---|---|---|
| `~/.local/bin/rdp-connect` | `engine/rdp-connect` | 700 |
| `~/.local/lib/rdp/rdp-common.bash` | `lib/rdp-common.bash` | 644 |
| `~/.config/rdp/i18n/{es,en}.env` | `i18n/{es,en}.env` | 600 |
| `~/.config/rdp/template.env` | `template/template.env` | 600 |
| `~/.config/rdp/profiles/*.env` | (user-created) | 600 |
| `~/.local/state/rdp/<profile>.log` | (runtime) | — |
| `~/.local/state/rdp/manifest.sha256` | (installer-generated) | — |

PID lockfile: `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-<uid>.pid` (uid-private — two users on the same host never collide).

## Accepted profile syntax

Only these 7 keys are accepted (parsed by the hardened `parse_env_safe` — no `source`, no `eval`):

```
HOST="server.example.com"       # required
USER_RDP="user@domain"          # required
PASS_RDP="secret"               # required (may contain = signs)
DOMAIN="MicrosoftAccount"       # optional
VPN_CHECK="vpn-host"            # optional (empty = skip VPN check)
PREFERRED_WS="3"                # optional (empty = no workspace rule)
LANG_OVERRIDE="es"              # optional (es/en)
```

Any key outside this allowlist is rejected with `parse_env_safe: <file>:<line>: rejected key '<key>'`. Inline comments inside quoted values are preserved (`HOST="server # prod"`); trailing comments after unquoted values are stripped (`PREFERRED_WS=3  # ws`).

## Distro support matrix

| Distro | Manager | Status |
|---|---|---|
| Arch + derivatives (CachyOS, Garuda, EndeavourOS) | pacman | ✅ Full |
| Fedora + derivatives (RHEL, CentOS, Rocky, Alma) | dnf | ✅ Full |
| Debian + derivatives (Ubuntu, Mint, Pop) | apt | ✅ (hyprland manual) |
| Alpine, NixOS, others | — | ❌ Manual install only |
