# rdp-connect

![status](https://img.shields.io/badge/status-baseline--hardened-brightgreen)
![capabilities](https://img.shields.io/badge/capabilities-5-blue)
![distros](https://img.shields.io/badge/distros-Arch%20%E2%9C%93%20%7C%20Debian%20%E2%9C%93%20%7C%20Fedora%20%E2%9C%93%20%7C%20Alpine%20%E2%9C%97-orange)
![tests](https://img.shields.io/badge/tests-46%20probe%20scenarios-brightgreen)
![spec](https://img.shields.io/badge/spec-driven-openspec-blueviolet)

RDP connection framework for Hyprland/Wayland built on `xfreerdp3`.

## Capabilities

| Capability | What it guarantees |
|---|---|
| `engine-security` | Hardened env parser (`parse_env_safe`) — allowlist + quote/comment handling, no `source`/`eval`, CRLF/whitespace tolerance, raw-preview diagnostics |
| `engine-robustness` | Strict mode (`set -euo pipefail`), `require_cmd` preflight, `/from-stdin:force` build gate, array-based flag expansion, cleanup LOG_FILE guard, per-PID error diagnostics, preflight input trimming |
| `hidpi-scaling` | Pure-bash + jq HiDPI math — no `bc`/`python3` deps; safe fallback when scale is unparsable |
| `instance-locking` | uid-private PID path under `${XDG_RUNTIME_DIR:-/tmp}`; stale-lock reclamation via `flock`; EXIT-trap cleanup |
| `installer` | Cross-distro deterministic deployment — `/etc/os-release` detection (pacman→dnf→apt), idempotent `install -D`, post-install smoke test, SHA-256 manifest |

Canonical contracts live at **[`openspec/specs/`](openspec/specs/)** — one directory per capability, each with a `spec.md` containing the normative requirements and Given/When/Then scenarios.

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

One-liner:

```bash
git clone https://github.com/hbuddenberg/rdp-connect && cd rdp-connect && ./install-rdp-framework.sh
```

The installer:
1. **Detects your distro** via `/etc/os-release` (pacman → dnf → apt order). Unsupported distros (Alpine, NixOS, etc.) are rejected with a manual-install reference.
2. **Installs missing dependencies** via the detected package manager (only missing ones — existing installs are preserved).
3. **Deploys files** idempotently via `install -D` (running twice produces byte-identical state).
4. **Runs a smoke test**: `bash -n` + `shellcheck --severity=warning` + `rdp-connect --help` (must exit 0) + parser probe (hostile profile must be rejected). Failure aborts the install.
5. **Writes a SHA-256 checksum manifest** to `~/.local/state/rdp/manifest.sha256` for reproducibility.

Then edit `~/.config/rdp/profiles/<name>.env` to set real credentials.

### Verify your install

```bash
# Smoke test — must exit 0 and print usage
rdp-connect --help

# Manifest verification — every line must report OK
sha256sum -c ~/.local/state/rdp/manifest.sha256
```

If `sha256sum -c` reports any file as `FAILED`, re-run `./install-rdp-framework.sh` to restore the canonical state.

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

Any key outside this allowlist is rejected with `parse_env_safe: <file>:<line>: rejected key '<key>'`. Inline comments inside quoted values are preserved (`HOST="server # prod"`); trailing comments after unquoted values are stripped (`PREFERRED_WS=3  # ws`). CRLF line endings (Windows-edited profiles) are tolerated. `HOST`, `VPN_CHECK`, `DOMAIN`, `PREFERRED_WS`, and `LANG_OVERRIDE` have leading/trailing whitespace trimmed before preflight; `PASS_RDP` and `USER_RDP` are NEVER trimmed (whitespace may be significant).

## Distro support matrix

| Distro | Manager | Status |
|---|---|---|
| Arch + derivatives (CachyOS, Garuda, EndeavourOS) | pacman | ✅ Full |
| Fedora + derivatives (RHEL, CentOS, Rocky, Alma) | dnf | ✅ Full |
| Debian + derivatives (Ubuntu, Mint, Pop) | apt | ✅ (hyprland manual — not in Debian main) |
| Alpine, NixOS, others | — | ❌ Manual install only (installer exits non-zero with a 3-manager reference) |

## Specifications

The capability contracts that govern this project live under **[`openspec/specs/`](openspec/specs/)** — they are the source of truth for what the engine, installer, and supporting modules MUST do. Every change to behavior flows through the SDD cycle (explore → propose → spec → design → tasks → apply → verify → archive) tracked under `openspec/changes/`. Completed changes are archived under `openspec/changes/archive/`.
