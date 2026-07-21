# Tasks: baseline-hardening

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | PR1 ≈ 710 / PR2 ≈ 255 (total ≈ 965) |
| 400-line budget risk | **High** — PR1 over budget (see note) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 security-core → PR2 robustness+installer (stacked-to-main) |
| Delivery strategy | auto-chain (chained-PRs, user-locked) |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

> **PR1 budget note (evidence-based):** PR1 lands ~710 changed lines, but **~570 of those are a verbatim heredoc→file move** in T1.1 (engine ~211 LOC + i18n/template ~35 LOC extracted from `install-rdp-framework.sh:14-286`; no logic change — `diff` between old heredoc body and new file is empty). PR1's *reviewable new logic* (F3+F2+F5) is only ~140 LOC. The move cannot split cleanly → meets the chained-pr `size:exception` criterion ("generated/vendor/migration diff cannot split cleanly"). **Recommendation:** tag T1.1's commit with `size:exception` (pure extraction, verified by empty diff vs. old heredoc body); PR2 (~255) needs no exception.

### Suggested Work Units

| Unit | Goal | PR | Base |
|---|---|---|---|
| T1.1 | Extract engine/lib/i18n/template to real files; installer copies them | PR1 | `main` |
| T1.2 | F3 hardened `parse_env_safe` (allowlist + quote/comment) | PR1 | `pr1/security-core` |
| T1.3 | F2 i18n via parser (no `source`) | PR1 | `pr1/security-core` |
| T1.4 | F5 PID path under XDG_RUNTIME_DIR + EXIT-trap cleanup | PR1 | `pr1/security-core` |
| T2.1 | F1 jq-native HiDPI math (DPI_FLAGS array) | PR2 | `main` (post-PR1) |
| T2.2 | F4+F6+F7+F8+F9 strict mode + preflight + arrays + cleanup guard | PR2 | `pr2/robustness-installer` |
| T2.3 | F10 cross-distro installer + smoke + checksum manifest | PR2 | `pr2/robustness-installer` |

## PR1 — security-core  (branch `pr1/security-core` ← `main`)

- [ ] **T1.1** `refactor(install): extract engine, lib, i18n, template into real repo files` — F10-prep (design commit 1)
  - Files: `engine/rdp-connect` (new, from heredoc body), `lib/rdp-common.bash` (new: `_PROFILE_KEYS` decl, `_reject`, fn stubs), `i18n/es.env`, `i18n/en.env`, `template/template.env` (new), `install-rdp-framework.sh` (drop engine/i18n/template heredocs → `install -D` copy). No logic change.
  - Deps: none. Size: ~570 (≈480 verbatim move → `size:exception` candidate).
  - [ ] manual-verification: installer → **Engine is copied, not heredoc-generated** (`diff -q engine/rdp-connect ~/.local/bin/rdp-connect` clean; no `cat <<` for engine/i18n/template deployment)

- [ ] **T1.2** `fix(security): harden parse_env_safe with allowlist and quote/comment handling` — F3 (design commit 2)
  - Files: `lib/rdp-common.bash` (`parse_env_safe` full impl incl. `i18n` MSG_* mode), `engine/rdp-connect` (`source <profile>` → `parse_env_safe "$f" profile`), `tests/parser-probe.sh` (rejects `PATH=/x`).
  - Deps: T1.1. Size: ~80.
  - [ ] manual-verification: engine-security → **Dangerous key in profile is rejected**
  - [ ] manual-verification: engine-security → **Unknown non-allowlisted key is rejected**
  - [ ] manual-verification: engine-security → **All allowlisted keys accepted**
  - [ ] manual-verification: engine-security → **Inline comment inside double-quoted value is preserved**
  - [ ] manual-verification: engine-security → **Trailing comment after unquoted value is stripped**
  - [ ] manual-verification: engine-security → **Single-quoted value is unquoted**
  - [ ] manual-verification: engine-security → **Malformed line aborts parsing**

- [ ] **T1.3** `fix(security): route i18n through hardened parser (no source)` — F2 (design commit 3)
  - Files: `engine/rdp-connect` (`load_language`: `source .../$LANG.env` → `parse_env_safe ... i18n`).
  - Deps: **T1.2** (F3 BLOCKS F2 — the `i18n` MSG_* glob must exist before this call site changes). Size: ~15.
  - [ ] manual-verification: engine-security → **i18n file with injected key is rejected** (`grep -nE 'source[[:space:]]+.*\.env' ~/.local/bin/rdp-connect` empty)
  - [ ] manual-verification: engine-security → **Legitimate MSG_* keys load**

- [ ] **T1.4** `fix(lock): relocate PID to XDG_RUNTIME_DIR with uid suffix; clean new path on exit` — F5 (design commit 5)
  - Files: `lib/rdp-common.bash` (`compute_pid_path`), `engine/rdp-connect` (`PID_FILE` assignment, `flock -n` block, EXIT trap `rm -f` the new path; tolerate missing PID file on early exit).
  - Deps: T1.1. Size: ~45. *(F9 LOG_FILE guard is NOT here — deferred to T2.2 where `set -e` makes it load-bearing.)*
  - [ ] manual-verification: instance-locking → **XDG_RUNTIME_DIR set resolves under /run/user**
  - [ ] manual-verification: instance-locking → **XDG_RUNTIME_DIR unset falls back to /tmp with uid suffix**
  - [ ] manual-verification: instance-locking → **Two users on the same host do not collide**
  - [ ] manual-verification: instance-locking → **Stale lock from a crashed prior instance is reclaimed**
  - [ ] manual-verification: instance-locking → **Live lock from a running peer is honored**
  - [ ] manual-verification: instance-locking → **Normal session exit cleans up**
  - [ ] manual-verification: instance-locking → **Early-exit before flock does not error**

## PR2 — robustness + installer  (branch `pr2/robustness-installer` ← `main` after PR1 merges)

- [ ] **T2.1** `fix(hidpi): replace bc/python3 with jq-native scale math` — F1 (design commit 4)
  - Files: `lib/rdp-common.bash` (`compute_dpi_flags`: jq float→int%, null/non-numeric → WARN + 100%; emits `DPI_FLAGS` **array**), `engine/rdp-connect` (call site; drop `bc`/`python3`; expand `"${DPI_FLAGS[@]}"`).
  - Deps: PR1 merged (lib exists). Size: ~35. *(DPI_FLAGS becomes an array here — required by the hidpi math; F8's MON_FLAGS array + `${arr[@]-}` set -u safety complete in T2.2.)*
  - [ ] manual-verification: hidpi-scaling → **HiDPI monitor receives /scale-desktop on bc-less box**
  - [ ] manual-verification: hidpi-scaling → **Fractional scale rounds to integer percent**
  - [ ] manual-verification: hidpi-scaling → **Scale of 1 emits no DPI flags**
  - [ ] manual-verification: hidpi-scaling → **null scale falls back with warning**
  - [ ] manual-verification: hidpi-scaling → **Non-numeric scale falls back with warning**

- [ ] **T2.2** `feat(robustness): strict mode, require_cmd, from-stdin gate, array flags, cleanup guard` — F4+F6+F7+F8+F9 (design commit 6 + F9)
  - Files: `engine/rdp-connect` (`set -euo pipefail`; `--help` handler **before** preflight; `require_cmd` for xfreerdp3/hyprctl/jq/notify-send/flock/wofi|rofi; `xfreerdp3 /help` from-stdin gate (F7); `MON_FLAGS` array + `"${arr[@]-}"` on both arrays (F8); `cleanup()` `[ -f "$LOG_FILE" ]` guard (F9); tactical `|| true` on hyprctl `keyword`/`focuswindow` + notify-send), `lib/rdp-common.bash` (`require_cmd`, `build_mon_flags`).
  - Deps: **T2.1** (DPI_FLAGS array must exist before `set -u`); PR1 merged (F3 precedes F4 per constraint). Size: ~90.
  - Intra-commit order: F6 preflight → F7 gate → F4 `set -e` region → F8 arrays → F9 cleanup guard. *(F4 REQUIRES F8 → same commit; F9 rides here because `set -e` + `require_cmd` early-exit is what makes the LOG_FILE guard load-bearing — splitting F9 off would ship a broken trap.)*
  - [ ] manual-verification: engine-robustness → **Transient hyprctl blip does not abort a live session**
  - [ ] manual-verification: engine-robustness → **Real failure still propagates**
  - [ ] manual-verification: engine-robustness → **Missing jq aborts with exit 127**
  - [ ] manual-verification: engine-robustness → **Missing both wofi and rofi aborts**
  - [ ] manual-verification: engine-robustness → **All binaries present proceeds normally**
  - [ ] manual-verification: engine-robustness → **Build without /from-stdin:force is rejected**
  - [ ] manual-verification: engine-robustness → **Build with /from-stdin:force proceeds**
  - [ ] manual-verification: engine-robustness → **Multi-monitor builds an array**
  - [ ] manual-verification: engine-robustness → **Single-monitor builds /f array**
  - [ ] manual-verification: engine-robustness → **Empty DPI_FLAGS under set -u**
  - [ ] manual-verification: engine-robustness → **EXIT before log file exists does not crash**

- [ ] **T2.3** `feat(installer): cross-distro deterministic installer with smoke test and manifest` — F10 (design commit 7)
  - Files: `install-rdp-framework.sh` (`detect_pkgr` via `/etc/os-release` ID+ID_LIKE, order pacman→dnf→apt; dep-manifest table; missing-dep `command -v` install; unsupported-distro loud fail w/ 3-manager reference; idempotent `install -D`; smoke = `bash -n`+shellcheck+`--help`+parser-probe; `sha256sum` manifest), `README.md` (layout, Hyprland hard-req, PID path, accepted profile syntax).
  - Deps: **T1.1** (real files), **T1.2** (`parse_env_safe` for probe), **T2.2** (`--help` handler for smoke). Size: ~130.
  - [ ] manual-verification: installer → **Arch host detected as pacman**
  - [ ] manual-verification: installer → **Debian host detected as apt**
  - [ ] manual-verification: installer → **Fedora host detected as dnf**
  - [ ] manual-verification: installer → **Missing jq is installed before engine deploy**
  - [ ] manual-verification: installer → **wofi or rofi satisfies the launcher dependency**
  - [ ] manual-verification: installer → **Alpine host is rejected with manual install instructions**
  - [ ] manual-verification: installer → **Two consecutive runs produce identical files**
  - [ ] manual-verification: installer → **--help succeeds post-install**
  - [ ] manual-verification: installer → **Parser probe rejects a known-bad profile**
  - [ ] manual-verification: installer → **Smoke test failure aborts the installer**
  - [ ] manual-verification: installer → **Manifest is generated and stable**

## Ordering Constraints (verified)

| Constraint | Status |
|---|---|
| F3 BLOCKS F2 | ✓ T1.2 → T1.3 (T1.3 deps on T1.2; `i18n` MSG_* glob lands in T1.2) |
| F3 + F6 precede F4 | ✓ F3 in PR1 (merged before PR2); F6 + F4 co-located in T2.2 (F6 ordered before the `set -e` line) |
| F4 REQUIRES F8 | ✓ same commit T2.2 (arrays + `set -u` atomic — never an intermediate `set -u` without arrays) |
| F5 PAIRS WITH F9 | ⚠ deliberate split (user-locked): F5 PID-path cleanup self-contained in T1.4; F9 LOG_FILE guard deferred to T2.2 where `set -e`+`require_cmd` make it load-bearing. T1.4 still tolerates a missing PID file on early exit (covers instance-locking "Early-exit before flock does not error"). |

## Branch Plan (stacked-to-main)

```
main (baseline ef04f56)
 ├─ pr1/security-core         ← branched from main; T1.1→T1.4; target main
 └─ pr2/robustness-installer  ← branched from main AFTER pr1/security-core merges; T2.1→T2.3; target main
```
Each PR's diff is against the latest `main` at branch time (sequential merges to main — not a feature-tracker chain).

## Next Step

Run `sdd-apply` for **PR1 (security-core)** first. Resolve the T1.1 `size:exception` question (accept the pure-extraction move, or restructure) before apply begins.
