# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A pure-bash RDP connection framework for Hyprland/Wayland, built on `xfreerdp3`. It ships as two deployed files (`engine/rdp-connect` + `lib/rdp-common.bash`), an installer, i18n dictionaries, and a bats-core test suite. There is no runtime other than bash — `package.json`/`node_modules` in this repo are unrelated tooling, not part of the project.

## Commands

```bash
make test             # bats tests/ — run the full suite
make lint             # shellcheck --severity=warning over engine + lib + installer + bootstrap + tests/*.bash
make ci               # lint + test — what GitHub Actions runs on every push/PR
make smoke            # install + throwaway-HOME `rdp-connect --help` (no xfreerdp3/hyprctl needed)
make verify-manifest  # sha256sum -c the installer's manifest (tamper detection)
make install          # delegates to ./install-rdp-framework.sh
```

Run a single test file: `bats tests/parser.bats`. Run a single case: `bats tests/parser.bats --filter "<test name>"`.

bats-core (1.5.0+) plus the separate `bats-support`/`bats-assert` libraries are **dev dependencies only** — the installer never installs them. `tests/test_helper.bash` looks for them at `$BATS_LIB_PATH`, `/usr/lib/bats`, then `~/.local/lib/bats`, in that order. See README "Testing" for the per-distro install matrix if bats/shellcheck are missing.

## Architecture

**Two-file split, both deployed from the repo root into `~/.local/`:**
- `engine/rdp-connect` → `~/.local/bin/rdp-connect` (mode 700) — the CLI entrypoint. Handles flag parsing, `--help`, `--log`, `--new`, `--update-profiles`, the wofi/rofi/walker selector, and the full connection pipeline (VPN/host preflight → HiDPI → monitor mode → audio → client selection → `xfreerdp3` launch).
- `lib/rdp-common.bash` → `~/.local/lib/rdp/rdp-common.bash` (mode 644) — pure, unit-testable functions sourced by the engine: `parse_env_safe`, `trim_profile_fields`, `extract_session_error`, `compute_pid_path`, `compute_dpi_flags`, `require_cmd`, `build_mon_flags`, `log_event`, `setup_colors`, `profile_has_tunables_block`, `append_tunables_block`.

The split exists so the bats suite can source `lib/rdp-common.bash` directly and test pure functions in isolation, without invoking the full engine (which needs `hyprctl`/`xfreerdp3`/a TTY). When adding new logic, prefer extracting it into the lib as a pure function with its own bats file, rather than growing the engine's inline logic — this is the established pattern (see the `strict-tdd-enable` history in README).

**Security model — this is the part to never regress on:**
- Profiles are `.env` files parsed by `parse_env_safe` — an allowlist parser (7 keys only: `HOST`, `USER_RDP`, `PASS_RDP`, `DOMAIN`, `VPN_CHECK`, `PREFERRED_WS`, `LANG_OVERRIDE`). It never `source`s or `eval`s the file; any key outside the allowlist aborts the engine. Do not "simplify" this back to `source`.
- The password is piped to `xfreerdp3` via `/from-stdin:force` (hidden from `ps aux`), never passed as `/p:`. The engine hard-fails at startup if the installed `xfreerdp3` build lacks `/from-stdin` support rather than silently falling back to `/p:`.
- `set -euo pipefail` is strict-mode for the whole engine. `|| true` is applied only to documented cosmetic calls (`hyprctl`, `notify-send`) — never to `xfreerdp3`, `flock`, `jq`, file tests, or anything security-relevant.
- The engine re-execs itself under `setsid --wait` at startup to become its own session/process-group leader, so the EXIT trap can `kill -- -$$` and reap orphaned `xfreerdp3` children. The PID lockfile under `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-<uid>.pid` is intentionally **never unlinked** on exit — the kernel releases the `flock` on process death and the next start reclaims the stale path via `flock -n`. See the `multi-peer-race` change (openspec) for why the previous unlink-on-exit design was a race (R7).
- Empty bash arrays must be expanded as `"${arr[@]}"`, never `"${arr[@]-}"` — the latter injects a phantom empty-string arg that `xfreerdp3` rejects. This bit `DPI_FLAGS`/`SOUND_FLAGS`/`MON_FLAGS` once; see `tests/freerdp3-flags.bats`.

**Spec-driven development (SDD):** behavioral changes are tracked under `openspec/` — canonical capability contracts live in `openspec/specs/<capability>/spec.md` (one per capability: `engine-robustness`, `engine-security`, `hidpi-scaling`, `installer`, `instance-locking`, `test-harness`); completed change proposals (explore → propose → spec → design → tasks → apply → verify → archive) are archived under `openspec/changes/archive/<change-name>/`. When changing engine/lib behavior, check whether the relevant `openspec/specs/*/spec.md` needs a corresponding update, and look at the archived changes for the reasoning behind non-obvious code (most "why" comments in the engine point back to a specific archived change like `multi-peer-race`).

**i18n:** message dictionaries are `i18n/{es,en}.env`, loaded through the same `parse_env_safe` (in `i18n` mode: only `MSG_*` keys allowed). Language is auto-detected from `$LANG`, overridable per-profile via `LANG_OVERRIDE`.

## Distro support

Arch/Fedora/Debian-family are fully supported by the installer (pacman → dnf → apt detection via `/etc/os-release`); Alpine/NixOS/others are rejected with a manual-install pointer. `hyprctl` (Hyprland) is a hard runtime requirement — the installer warns but does not fail if it's missing on Debian (not in Debian main), but the engine's `require_cmd` preflight will refuse to start without it.
