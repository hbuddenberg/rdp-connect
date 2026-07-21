# Tasks: baseline-hardening

## Review Workload Forecast (final, post-archive)

| Field | Value |
|---|---|
| Actual changed lines (PR1) | 972 ins+del incl. T1.1 size:exception verbatim move (reviewable new logic ≈417) |
| Actual changed lines (PR2) | 993 code+test (1,635 total incl. openspec docs) |
| Final task count | 9 (T1.1–T1.4 PR1 + T2.1–T2.3 PR2 + T2.4–T2.6 PR2 bugfix slice) |
| 400-line budget risk | **High** — both PRs over the per-PR budget; mitigated by chained-PR slice + T1.1 `size:exception` + bugfix slice inherently coupled to its parent PR |
| Chained PRs used | Yes (2 PRs, stacked-to-main) |
| Chain strategy | stacked-to-main (both PRs merged to main) |
| Bugfix slice | T2.4 + T2.5 + T2.6 carried on `pr2/robustness-installer` (same branch, +166 LOC) |

Decision needed before apply: Yes (resolved — chained-PRs, user-locked)
Chained PRs recommended: Yes (delivered)
Chain strategy: stacked-to-main (delivered)
400-line budget risk: High (accepted via `size:exception` for T1.1 verbatim move; PR2 overage accepted as coupled-bugfix slice per orchestrator decision)

> **PR1 budget note (evidence-based):** PR1 landed ~710 changed lines, but
> **~570 of those were a verbatim heredoc→file move** in T1.1 (engine ~211 LOC +
> i18n/template ~35 LOC extracted from `install-rdp-framework.sh:14-286`; no
> logic change — `diff` between old heredoc body and new file is empty). PR1's
> *reviewable new logic* (F3+F2+F5) was only ~140 LOC. Tagged T1.1's commit with
> `size:exception` (pure extraction, verified by empty diff vs. old heredoc body).

> **PR2 budget note (evidence-based):** PR2 landed 993 code+test lines (1,635
> total incl. openspec docs). The overage is real: the cross-distro installer
> (T2.3) is a new top-level deliverable; the bugfix slice (T2.4–T2.6) was
> inherently coupled to the parser/cleanup code that landed in the same PR —
> splitting would break TDD/verify coherence. Accepted via orchestrator
> delivery decision rather than `size:exception` footer (per verify-report-pr2
> open item 1).

### Work Units Delivered

| Unit | Goal | PR | Status |
|---|---|---|---|
| T1.1 | Extract engine/lib/i18n/template to real files; installer copies them | PR1 | ✅ merged @ `fa2b10e` |
| T1.2 | F3 hardened `parse_env_safe` (allowlist + quote/comment) | PR1 | ✅ merged @ `401a257` |
| T1.3 | F2 i18n via parser (no `source`) | PR1 | ✅ merged @ `67c92a4` |
| T1.4 | F5 PID path under XDG_RUNTIME_DIR + EXIT-trap cleanup | PR1 | ✅ merged @ `e0904be` |
| T2.1 | F1 jq-native HiDPI math (DPI_FLAGS array) | PR2 | ✅ merged @ `6116413` |
| T2.2 | F4+F6+F7+F8+F9 strict mode + preflight + arrays + cleanup guard | PR2 | ✅ merged @ `c88a0f5` |
| T2.3 | F10 cross-distro installer + smoke + checksum manifest | PR2 | ✅ merged @ `9ef351f` |
| T2.4 | Parser robustness: CRLF + trailing whitespace + tail validation (review bug A) | PR2 | ✅ merged @ `eace9b1` |
| T2.5 | Cleanup SESSION_START marker for per-PID error extraction (review bug B) | PR2 | ✅ merged @ `f4da861` |
| T2.6 | Preflight input normalization: trim whitespace (user report) | PR2 | ✅ merged @ `41735dd` |

## PR1 — security-core  (branch `pr1/security-core` ← `main`)

- [x] **T1.1** `refactor(install): extract engine, lib, i18n, template into real repo files` — F10-prep (design commit 1)
   - Files: `engine/rdp-connect` (new, from heredoc body), `lib/rdp-common.bash` (new: `_PROFILE_KEYS` decl, `_reject`, fn stubs), `i18n/es.env`, `i18n/en.env`, `template/template.env` (new), `install-rdp-framework.sh` (drop engine/i18n/template heredocs → `install -D` copy). No logic change.
   - Deps: none. Size: ~570 (≈480 verbatim move → `size:exception` candidate).
   - [x] manual-verification: installer → **Engine is copied, not heredoc-generated** (`diff -q engine/rdp-connect ~/.local/bin/rdp-connect` clean; no `cat <<` for engine/i18n/template deployment) — PASS @ fa2b10e

- [x] **T1.2** `fix(security): harden parse_env_safe with allowlist and quote/comment handling` — F3 (design commit 2)
   - Files: `lib/rdp-common.bash` (`parse_env_safe` full impl incl. `i18n` MSG_* mode), `engine/rdp-connect` (`source <profile>` → `parse_env_safe "$f" profile`), `tests/parser-probe.sh` (rejects `PATH=/x`).
   - Deps: T1.1. Size: ~80.
   - [x] manual-verification: engine-security → **Dangerous key in profile is rejected** — PASS @ F1 fixture + engine integration (PATH= exit 1, ambient PATH intact)
   - [x] manual-verification: engine-security → **Unknown non-allowlisted key is rejected** — PASS @ F2 fixture (FOO= rejected)
   - [x] manual-verification: engine-security → **All allowlisted keys accepted** — PASS @ F3 fixture (all 7 keys → rc=0)
   - [x] manual-verification: engine-security → **Inline comment inside double-quoted value is preserved** — PASS @ F4 fixture (HOST="server # production" preserved verbatim)
   - [x] manual-verification: engine-security → **Trailing comment after unquoted value is stripped** — PASS @ F5 fixture (PREFERRED_WS=3  # x → "3")
   - [x] manual-verification: engine-security → **Single-quoted value is unquoted** — PASS @ F6 fixture (DOMAIN='MicrosoftAccount' → "MicrosoftAccount")
   - [x] manual-verification: engine-security → **Malformed line aborts parsing** — PASS @ F7 fixture (no-= line → rc=1)

- [x] **T1.3** `fix(security): route i18n through hardened parser (no source)` — F2 (design commit 3)
   - Files: `engine/rdp-connect` (`load_language`: `source .../$LANG.env` → `parse_env_safe ... i18n`).
   - Deps: **T1.2** (F3 BLOCKS F2 — the `i18n` MSG_* glob must exist before this call site changes). Size: ~15.
   - [x] manual-verification: engine-security → **i18n file with injected key is rejected** (`grep -nE 'source[[:space:]]+.*\.env' ~/.local/bin/rdp-connect` empty) — PASS @ engine source + deployed engine both clean; hostile es.env aborts engine exit 1
   - [x] manual-verification: engine-security → **Legitimate MSG_* keys load** — PASS @ deployed es.env probe (MSG_PROMPT_SELECT/CONNECTING/NEW_NO_EDITOR populated, rc=0)

- [x] **T1.4** `fix(lock): relocate PID to XDG_RUNTIME_DIR with uid suffix; clean new path on exit` — F5 (design commit 5)
   - Files: `lib/rdp-common.bash` (`compute_pid_path`), `engine/rdp-connect` (`PID_FILE` assignment, `flock -n` block, EXIT trap `rm -f` the new path; tolerate missing PID file on early exit).
   - Deps: T1.1. Size: ~45. *(F9 LOG_FILE guard is NOT here — deferred to T2.2 where `set -e` makes it load-bearing.)*
   - [x] manual-verification: instance-locking → **XDG_RUNTIME_DIR set resolves under /run/user** — PASS @ S1 (/run/user/1000/rdp-partner-1000.pid)
   - [x] manual-verification: instance-locking → **XDG_RUNTIME_DIR unset falls back to /tmp with uid suffix** — PASS @ S2 (/tmp/rdp-partner-1000.pid)
   - [x] manual-verification: instance-locking → **Two users on the same host do not collide** — PASS @ S3+S4 (uid 1000 vs 1001 → distinct paths under both XDG-set and XDG-unset)
   - [x] manual-verification: instance-locking → **Stale lock from a crashed prior instance is reclaimed** — PASS by design inspection (flock is process-bound; kernel releases lock on crash → our flock -n succeeds → `echo "$$" >&200` overwrites stale content)
   - [x] manual-verification: instance-locking → **Live lock from a running peer is honored** — PASS by design inspection (flock -n fails on same-inode fd → peer branch logs WARN, focuses window, exits 0)
   - [x] manual-verification: instance-locking → **Normal session exit cleans up** — PASS @ engine integration (new-path PID file removed after preflight-failed run; legacy path never used)
   - [x] manual-verification: instance-locking → **Early-exit before flock does not error** — PASS by trap inspection (`[ -f "$PID_FILE" ] && rm -f` guard tolerates missing file; rm -f is itself tolerant)

## PR2 — robustness + installer  (branch `pr2/robustness-installer` ← `main` after PR1 merges)

- [x] **T2.1** `fix(hidpi): replace bc/python3 with jq-native scale math` — F1 (design commit 4)
  - Files: `lib/rdp-common.bash` (`compute_dpi_flags`: jq float→int%, null/non-numeric → WARN + 100%; emits `DPI_FLAGS` **array**), `engine/rdp-connect` (call site; drop `bc`/`python3`; expand `"${DPI_FLAGS[@]}"`).
  - Deps: PR1 merged (lib exists). Size: ~35. *(DPI_FLAGS becomes an array here — required by the hidpi math; F8's MON_FLAGS array + `${arr[@]-}` set -u safety complete in T2.2.)*
  - [x] manual-verification: hidpi-scaling → **HiDPI monitor receives /scale-desktop on bc-less box** — PASS @ S1 (scale=2.0 → /scale-desktop:200 /smart-sizing; hidpi-probe 8/8)
  - [x] manual-verification: hidpi-scaling → **Fractional scale rounds to integer percent** — PASS @ S2 (scale=1.5 → /scale-desktop:150)
  - [x] manual-verification: hidpi-scaling → **Scale of 1 emits no DPI flags** — PASS @ S3 (scale=1.0 → empty DPI_FLAGS)
  - [x] manual-verification: hidpi-scaling → **null scale falls back with warning** — PASS @ S4 (scale=null → WARN + empty DPI_FLAGS)
  - [x] manual-verification: hidpi-scaling → **Non-numeric scale falls back with warning** — PASS @ S5 (scale="auto" → WARN + empty)

- [x] **T2.2** `feat(robustness): strict mode, require_cmd, from-stdin gate, array flags, cleanup guard` — F4+F6+F7+F8+F9 (design commit 6 + F9)
  - Files: `engine/rdp-connect` (`set -euo pipefail`; `--help` handler **before** preflight; `require_cmd` for xfreerdp3/hyprctl/jq/notify-send/flock/wofi|rofi; `xfreerdp3 /help` from-stdin gate (F7); `MON_FLAGS` array + `"${arr[@]-}"` on both arrays (F8); `cleanup()` `[ -f "$LOG_FILE" ]` guard (F9); tactical `|| true` on hyprctl `keyword`/`focuswindow` + notify-send), `lib/rdp-common.bash` (`require_cmd`, `build_mon_flags`).
  - Deps: **T2.1** (DPI_FLAGS array must exist before `set -u`); PR1 merged (F3 precedes F4 per constraint). Size: ~90.
  - Intra-commit order: F6 preflight → F7 gate → F4 `set -e` region → F8 arrays → F9 cleanup guard. *(F4 REQUIRES F8 → same commit; F9 rides here because `set -e` + `require_cmd` early-exit is what makes the LOG_FILE guard load-bearing — splitting F9 off would ship a broken trap.)*
  - [x] manual-verification: engine-robustness → **Transient hyprctl blip does not abort a live session** — PASS (hyprctl keyword/focuswindow + notify-send carry `|| true`)
  - [x] manual-verification: engine-robustness → **Real failure still propagates** — PASS @ integration (unreachable host → exit 1 → ERROR logged)
  - [x] manual-verification: engine-robustness → **Missing jq aborts with exit 127** — PASS @ Probe 2
  - [x] manual-verification: engine-robustness → **Missing both wofi and rofi aborts** — PASS @ Probe 3 (selector mode → exit 127)
  - [x] manual-verification: engine-robustness → **All binaries present proceeds normally** — PASS @ integration (engine reaches preflight)
  - [x] manual-verification: engine-robustness → **Build without /from-stdin:force is rejected** — PASS @ Probe 4 (mock xfreerdp3 → exit 1)
  - [x] manual-verification: engine-robustness → **Build with /from-stdin:force proceeds** — PASS @ integration (host xfreerdp3 advertises /from-stdin)
  - [x] manual-verification: engine-robustness → **Multi-monitor builds an array** — PASS @ build_mon_flags (count > 1 → ["/multimon" "/monitors:ids"])
  - [x] manual-verification: engine-robustness → **Single-monitor builds /f array** — PASS @ build_mon_flags (count ≤ 1 → ["/f"])
  - [x] manual-verification: engine-robustness → **Empty DPI_FLAGS under set -u** — PASS @ standalone test ("${DPI_FLAGS[@]-}" expands to nothing, no abort)
  - [x] manual-verification: engine-robustness → **EXIT before log file exists does not crash** — PASS @ Probe 5 (missing jq → no "No such file" diagnostic)

- [x] **T2.3** `feat(installer): cross-distro deterministic installer with smoke test and manifest` — F10 (design commit 7)
  - Files: `install-rdp-framework.sh` (`detect_pkgr` via `/etc/os-release` ID+ID_LIKE, order pacman→dnf→apt; dep-manifest table; missing-dep `command -v` install; unsupported-distro loud fail w/ 3-manager reference; idempotent `install -D`; smoke = `bash -n`+shellcheck+`--help`+parser-probe; `sha256sum` manifest), `README.md` (layout, Hyprland hard-req, PID path, accepted profile syntax).
  - Deps: **T1.1** (real files), **T1.2** (`parse_env_safe` for probe), **T2.2** (`--help` handler for smoke). Size: ~130.
  - [x] manual-verification: installer → **Arch host detected as pacman** — PASS @ Probe 1
  - [x] manual-verification: installer → **Debian host detected as apt** — PASS by code inspection (case branch debian|ubuntu|linuxmint|pop)
  - [x] manual-verification: installer → **Fedora host detected as dnf** — PASS by code inspection (case branch fedora|rhel|centos|rocky|alma)
  - [x] manual-verification: installer → **Missing jq is installed before engine deploy** — PASS @ install_deps (command -v gate + pacman -Sy --needed)
  - [x] manual-verification: installer → **wofi or rofi satisfies the launcher dependency** — PASS @ install_deps (OR-check: if either present, skip)
  - [x] manual-verification: installer → **Alpine host is rejected with manual install instructions** — PASS by code inspection (alpine not in any case branch → detect_pkgr returns 1 → exit 1 with 3-manager reference)
  - [x] manual-verification: installer → **Two consecutive runs produce identical files** — PASS @ Probe 2 (throwaway-HOME run 1 + run 2, manifest byte-identical)
  - [x] manual-verification: installer → **--help succeeds post-install** — PASS @ smoke step 3
  - [x] manual-verification: installer → **Parser probe rejects a known-bad profile** — PASS @ smoke step 4 (PATH=/x → rejected)
  - [x] manual-verification: installer → **Smoke test failure aborts the installer** — PASS @ Probe 5 (syntax error → bash -n fails → exit 1)
  - [x] manual-verification: installer → **Manifest is generated and stable** — PASS @ Probe 4 (~/.local/state/rdp/manifest.sha256, LC_ALL=C sort, byte-identical across runs)

## PR2 — bugfix slice  (continuation of `pr2/robustness-installer`)

> Surfaced by post-PR2 review of the parser and the cleanup trap. Two of the
> three were not codified in the original spec — both amended into the canonical
> capabilities at archive (`engine-security` for parser robustness; `engine-robustness`
> for cleanup session-isolation and VPN trim).

- [x] **T2.4** `fix(parser): tolerate trailing whitespace, CRLF, and inline comment after closing quote` @ `eace9b1` — review-surfaced bug A
  - Files: `lib/rdp-common.bash::parse_env_safe` (CRLF strip BEFORE blank-line/`*=` checks; first-closing-quote search via `${rest%%"$q"*}`; tail-validation regex `^[[:space:]]*(#.*)?$`; 40-char sanitized raw previews on rejection), `tests/parser-probe.sh` (+9 fixtures F15-F23 via new `expect_rc_msg` helper).
  - Deps: T1.2 (parser exists). Size: +134.
  - Spec amendment at archive: `engine-security` → `Quote and comment handling` requirement gains three new scenarios (CRLF tolerated, trailing whitespace after quote tolerated, garbage after closing quote rejected with raw preview).
  - [x] manual-verification: engine-security → **Empty quoted value** — PASS @ F15 (VPN_CHECK="" → val=`<empty>`, rc=0)
  - [x] manual-verification: engine-security → **CRLF after closing quote** — PASS @ F16 (HOST="srv"`\r` → val=`srv`, rc=0; no "unterminated quote")
  - [x] manual-verification: engine-security → **Trailing space after closing quote** — PASS @ F17 (HOST="srv"` ` → val=`srv`)
  - [x] manual-verification: engine-security → **Trailing tab after closing quote** — PASS @ F18 (HOST="srv"`\t` → val=`srv`)
  - [x] manual-verification: engine-security → **Inline comment after closing quote** — PASS @ F19 (HOST="srv" # comment → val=`srv`)
  - [x] manual-verification: engine-security → **Garbage after closing quote is rejected** — PASS @ F20 (HOST="srv"garbage → rc=1, msg `unexpected content after closing quote: 'garbage'` — caught a SECOND silent-corruption bug in the old `${raw:1:${#raw}-2}` slice)
  - [x] manual-verification: engine-security → **Unterminated quote shows raw preview** — PASS @ F21 (HOST="srv → rc=1, msg `unterminated quote (raw: '...')`)
  - [x] manual-verification: engine-security → **Quoted `=` signs preserved** — PASS @ F22 regression (PASS_RDP="secret=with=equals" → val=`secret=with=equals`)
  - [x] manual-verification: engine-security → **Quoted `#` interior preserved** — PASS @ F23 regression (HOST="server # production" → val=`server # production`)

- [x] **T2.5** `fix(cleanup): scope error diagnostic to current session, not stale log lines` @ `f4da861` — review-surfaced bug B
  - Files: `engine/rdp-connect` (`log_event "SESSION_START" "pid=$$ profile=$PROFILE"` as FIRST log line after trap registration; `cleanup()` error-extractor rewritten from `tail -n 15 | grep` to `awk` bounded scan with PID-scoped marker regex `pid=<pid>([^0-9]|$)`).
  - Deps: T2.2 (cleanup guard exists). Size: +32.
  - Spec amendment at archive: `engine-robustness` gains a new requirement "Cleanup error diagnostic scoped to the current session" with four scenarios (current-session-only extraction, PID-prefix safety, no-error-returns-empty, legacy log degrades gracefully).
  - [x] manual-verification: engine-robustness → **Current session with its own ERROR** — PASS @ Test 1 (returns Session B's line; Session A NOT leaked)
  - [x] manual-verification: engine-robustness → **PID prefix safety** — PASS @ Test 3 (`pid=2222` does NOT match `pid=22222`)
  - [x] manual-verification: engine-robustness → **Current session with NO ERROR returns empty** — PASS @ Test 1 baseline (no leak from previous sessions)
  - [x] manual-verification: engine-robustness → **Legacy log without marker degrades gracefully** — PASS @ Test 4 (awk returns empty → generic notify-send fallback)

- [x] **T2.6** `fix(vpn): trim whitespace from VPN_CHECK and HOST before TCP preflight` @ `41735dd` — user-reported bug
  - Files: `engine/rdp-connect` (trim block at L174-181 over `HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE` — runs AFTER `parse_env_safe` L162 and BEFORE VPN preflight L292; `PASS_RDP`/`USER_RDP` deliberately NOT trimmed — passwords/identifiers MAY legally have surrounding spaces), `tests/vpn-trim-probe.sh` (8 cases: 4 expect-SKIP, 4 expect-ENTER-with-cleaned-host).
  - Deps: T2.2 (`set -u` requires pre-initialized allowlisted keys). Size: ~50.
  - Spec amendment at archive: `engine-robustness` gains a new requirement "Preflight input normalization" with three scenarios (VPN_CHECK whitespace-only trimmed, HOST surrounding-whitespace trimmed, PASS_RDP/USER_RDP NOT trimmed).
  - Trigger: user bug report — *"VPN required when empty" + confusing "unterminated quote" on the same profile.* Root cause: `VPN_CHECK=" "` passed the `-n` non-empty test and produced a useless "VPN requerida ( )" message; the same Windows-edited profile also had CRLF on a quoted value (fixed by T2.4).
  - [x] manual-verification: engine-robustness → **VPN_CHECK=" " trimmed → VPN preflight skipped** — PASS @ vpn-trim-probe (whitespace-only → empty → skip)
  - [x] manual-verification: engine-robustness → **VPN_CHECK="  host  " trimmed → preflight uses cleaned host** — PASS @ vpn-trim-probe (trim → `host`)
  - [x] manual-verification: engine-robustness → **HOST="  srv  " trimmed before TCP probe** — PASS @ vpn-trim-probe (trim → `srv`)
  - [x] manual-verification: engine-robustness → **PASS_RDP and USER_RDP NOT trimmed** — PASS @ code inspection (trim loop body enumerates only the 5 non-credential fields; commit body documents the rationale)

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

All 9 tasks complete (T1.1–T1.4 PR1 + T2.1–T2.3 PR2 + T2.4–T2.6 PR2 bugfix slice).
Both PRs merged to main. Change archived to
`openspec/changes/archive/baseline-hardening/`. Canonical capability specs
synced under `openspec/specs/{engine-security,engine-robustness,hidpi-scaling,instance-locking,installer}/spec.md`.

Recommended next change: tag release `v0.1.0`, then either (a) bats-core
scaffolding for `strict_tdd: true` on the next change, or (b) a new feature
change.
