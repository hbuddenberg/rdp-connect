# 🖥️ rdp-connect

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg?style=flat-square)](https://github.com/hbuddenberg/rdp-connect/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg?style=flat-square)](LICENSE)
[![CI](https://github.com/hbuddenberg/rdp-connect/actions/workflows/test.yml/badge.svg)](https://github.com/hbuddenberg/rdp-connect/actions)
[![Compositors](https://img.shields.io/badge/compositors-Hyprland%20%7C%20Niri-94e2d5.svg?style=flat-square)](https://github.com/hbuddenberg/rdp-connect)

Modern RDP connection framework for **Hyprland**, **Niri**, and Wayland desktop environments built on `xfreerdp3`.

## ✨ Features

- **Native Quickshell Modal UI**: Modern Omarchy standalone modal applet with visual profile picker, monitor selector, hardware feature toggles (Audio, Clipboard, Drive, USB, Webcam), client engine chips (X11, SDL, Wayland), and Fullscreen switch.
- **Multiple FreeRDP Client Engines**: Support for `xfreerdp3` (XWayland, default), `sdl-freerdp3` (SDL3 with Wayland native dynamic resolution), and `wlfreerdp3` (Wayland native).
- **Multi-Launcher Support**: Quickshell → Walker → Wofi → Rofi fallback hierarchy.
- **Multi-Compositor Support**: Native IPC integration with both **Hyprland** (`hyprctl`) and **Niri** (`niri msg`).
- **Profile-based connections**: Each server is an `.env` file under `~/.config/rdp/profiles/`.
- **Hardened Security**: Env parser (`parse_env_safe`) with allowlist + quote/comment handling, no `source`/`eval`, password piped via stdin (`/from-stdin:force`, hidden from `ps aux`), `flock` single-instance guard.
- **Robustness**: Strict mode (`set -euo pipefail`), `require_cmd` preflight, array-based flag expansion, process-group isolation so termination reaps all child processes.
- **Pre-flight checks**: TCP socket probe on port 3389 before launching.
- **i18n**: Spanish/English message dictionaries, auto-detected from `$LANG`.

## 📦 Installation

### AUR (Arch Linux)

```bash
# Using yay
yay -S rdp-connect

# Using paru
paru -S rdp-connect
```

### Manual Install

```bash
git clone https://github.com/hbuddenberg/rdp-connect.git
cd rdp-connect
chmod +x install.sh
./install.sh
```
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
| `rdp-connect` | Open graphical selector (Quickshell/Walker/Wofi/Rofi) |
| `rdp-connect <profile>` | Direct connection to a profile |
| `rdp-connect --client <x11\|sdl\|wayland> <profile>` | Select FreeRDP client engine |
| `rdp-connect --single-mon <profile>` | Single-monitor mode (+dynamic-resolution) |
| `rdp-connect --multi-mon <profile>` | Multi-monitor mode |
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

PID lockfile: `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-<uid>.pid` (uid-private — two users on the same host never collide). **Note (`multi-peer-race` R7 fix):** the lockfile path now PERSISTS in `XDG_RUNTIME_DIR` after the engine exits. The kernel releases the advisory `flock` automatically when the engine process dies (fd close); the next start's `flock -n` reclaims the stale path. Do NOT delete these `.pid` files manually — they are benign and self-healing. (Previous versions unlinked the path on exit, which created an anonymous inode and allowed a contender to bypass the lock during the cleanup window — R7.)

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

## Testing

The bats test suite and `shellcheck` lint are **dev dependencies only** — the installer does NOT install them (runtime needs only the binaries listed in Requirements). CI runs `make ci` (= `lint test`) on every push and pull_request.

### Install bats-core + assertion libraries

bats-core 1.5.0+ is the floor (enforced at load by `tests/test_helper.bash`). The test helper also loads **bats-support** and **bats-assert** (separate repos / packages — `assert_success`, `assert_output`, `assert_equal` are not built-in to bats-core).

| Distro | bats-core | bats-support + bats-assert |
|---|---|---|
| Arch | `sudo pacman -S bats` | (not in pacman — install from source, see below) |
| Ubuntu / Debian | `sudo apt-get install -y bats` | `sudo apt-get install -y bats-support bats-assert` |
| Fedora | `sudo dnf install -y bats` | `sudo dnf install -y bats-support bats-assert` |
| Any (source) | `git clone https://github.com/bats-core/bats-core && ./bats-core/install.sh ~/.local` | see below |

Source install of the assertion libraries (for Arch and any distro without packaged versions):

```bash
mkdir -p ~/.local/lib/bats
git clone https://github.com/bats-core/bats-support ~/.local/lib/bats/bats-support
git clone https://github.com/bats-core/bats-assert  ~/.local/lib/bats/bats-assert
```

`tests/test_helper.bash` searches these locations in order: `$BATS_LIB_PATH`, `/usr/lib/bats`, `~/.local/lib/bats`. Set `BATS_LIB_PATH` if you install elsewhere.

### Run the suite

```bash
make test    # bats tests/
make lint    # shellcheck --severity=warning over engine + lib + installer + bootstrap + tests/*.{sh,bash}
make ci      # lint + test (what GitHub Actions runs)
make smoke   # install + throwaway-HOME rdp-connect --help (no xfreerdp3 needed)
```

The smoke target works on a host without `xfreerdp3` / `hyprctl` because `rdp-connect --help` exits 0 (engine L40) BEFORE `require_cmd xfreerdp3` (engine L47) runs — the same reason CI does not need to mock those binaries.

### SDD context

This test harness was built under the `strict-tdd-enable` change (archived — see **[`openspec/changes/archive/strict-tdd-enable/`](openspec/changes/archive/strict-tdd-enable/)** for the proposal, design, and task breakdown). PR1 landed the tooling (Makefile + CI + helper + this README section); PR2 migrated the 46 probe scenarios to `*.bats`; PR3 extracted two more pure functions from the engine (`trim_profile_fields`, `extract_session_error`), added the cleanup-session + engine-security bats coverage those extractions unlock, and flipped `strict_tdd: true` — every future SDD change now follows the red-green-refactor cycle at the unit level. The canonical contract for this capability lives at **[`openspec/specs/test-harness/spec.md`](openspec/specs/test-harness/spec.md)**.

Current suite: **74 bats cases across 8 files** (parser 24 + hidpi 8 + pid-path 6 + vpn-trim 10 + harness 10 + cleanup-session 6 + engine-security 2 + multi-peer-race 8).

### Recent changes

- **`multi-peer-race` (PR #6, merged 2026-07-21)** — closed the R7 race and the orphan-kill footgun in a single diff. Three user-visible behavior changes:
  1. **`$PID_FILE` now persists in `$XDG_RUNTIME_DIR` after exit.** The kernel releases the `flock` on fd close; the next start reclaims the path via `flock -n`. (Previous versions unlinked the path, which created an anonymous inode and let a contender bypass the lock during the cleanup window.) See [`openspec/specs/instance-locking/spec.md`](openspec/specs/instance-locking/spec.md) — "EXIT trap preserves the lockfile path".
  2. **`pkill rdp-connect` now reaps `xfreerdp3` children.** The engine calls `setpgid 0 0` at startup (becomes its own process-group leader); the EXIT trap fires `kill -- -$$` to terminate the whole group before logging/notification. Scoped to the engine's own group only — no collateral damage. See [`openspec/specs/engine-robustness/spec.md`](openspec/specs/engine-robustness/spec.md) — "Process-group isolation and signal-induced cleanup".
  3. **8 new bats cases** in `tests/multi-peer-race.bats` (3 source-grep + 5 pattern-contract). Full suite 74/74 green; `make ci` rc=0.
  
  Change archived at [`openspec/changes/archive/multi-peer-race/`](openspec/changes/archive/multi-peer-race/). The verify report flagged 3 spec scenarios (S6/S9/S10) as having no direct behavioral `@test` coverage — tracked as a follow-up; the engine change itself is safe, correct, and reversible.

## Specifications

The capability contracts that govern this project live under **[`openspec/specs/`](openspec/specs/)** — they are the source of truth for what the engine, installer, and supporting modules MUST do. Every change to behavior flows through the SDD cycle (explore → propose → spec → design → tasks → apply → verify → archive) tracked under `openspec/changes/`. Completed changes are archived under `openspec/changes/archive/`.
