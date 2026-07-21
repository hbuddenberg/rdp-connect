# Verification Report — baseline-hardening PR2 (robustness-installer + bugfix slice)

**Change**: baseline-hardening
**Branch**: `pr2/robustness-installer` (8 commits: T2.1, T2.2, T2.3, docs, T2.4, T2.5, docs, T2.6)
**Specs in scope**: hidpi-scaling-delta (5 scenarios), engine-robustness-delta (11 scenarios), installer-delta (12 scenarios) — **28 total**
**PR1 specs SKIPPED**: engine-security, instance-locking (already verified in PR1, merged to main)
**Mode**: Standard (`strict_tdd: false`)
**Date**: 2026-07-21

## Executive Summary

All **28/28 PR2 spec scenarios COMPLIANT** (5 hidpi + 11 robustness + 12 installer).
All 4 executable probes pass (**parser-probe 24/24, hidpi-probe 8/8, pid-path-probe 6/6, vpn-trim-probe 8/8**).
Bugfix slice (T2.4 + T2.5 + T2.6) fully verified — parser CRLF/whitespace robustness, cleanup SESSION_START session-isolation, and VPN trim all pass.
Structural checks clean: `shellcheck --severity=warning` 0 findings across engine/lib/installer/tests; `bash -n` clean on all bash files.
Throwaway-HOME install is idempotent (manifest byte-identical across 2 runs).

Two non-blocking warnings for the orchestrator:
1. **PR2 size over budget** — 993 code+test changed lines (1,635 total incl. openspec docs) vs 400-line budget. Delivery decision needed: `size:exception` footer OR split.
2. **Documentation gap** — `tasks.md` lacks T2.4/T2.5/T2.6 entries; `apply-progress.md` lacks T2.6 section. Close at archive.

**Verdict: PASS WITH WARNINGS — PR2 is ready to merge from a verification standpoint.**

---

## Artifacts

- File: `openspec/changes/baseline-hardening/verify-report-pr2.md` (this report)
- Engram mirror: topic_key `sdd/baseline-hardening/verify-report-pr2`

---

## Scenarios Verified

| Status | Count |
|---|---|
| ✅ Passed (COMPLIANT) | 28 |
| ⚠️ Warned (PARTIAL) | 0 |
| ❌ Failed (FAILING/UNTESTED) | 0 |
| **Total** | **28** |

---

## Spec Compliance Matrix

### hidpi-scaling-delta (5/5 COMPLIANT)

| # | Requirement | Scenario | Test / Evidence | Result |
|---|---|---|---|---|
| 1 | Pure-bash HiDPI math | HiDPI monitor receives /scale-desktop on bc-less box (scale=2) | `tests/hidpi-probe.sh S1` PASS → `DPI_FLAGS=["/scale-desktop:200" "/smart-sizing"]`; `grep -nE '\bbc\b\|python3' engine lib` returns only comments | ✅ COMPLIANT |
| 2 | Pure-bash HiDPI math | Fractional scale rounds to integer percent (scale=1.5) | `tests/hidpi-probe.sh S2` PASS → `DPI_FLAGS=["/scale-desktop:150" "/smart-sizing"]` | ✅ COMPLIANT |
| 3 | Pure-bash HiDPI math | Scale of 1 emits no DPI flags | `tests/hidpi-probe.sh S3` PASS → `DPI_FLAGS=()` | ✅ COMPLIANT |
| 4 | Safe fallback | null scale falls back with warning | `tests/hidpi-probe.sh S4` PASS → `IS_HIDPI=0 SCALE_PCT=100` + WARN line naming `null` | ✅ COMPLIANT |
| 5 | Safe fallback | Non-numeric scale falls back with warning | `tests/hidpi-probe.sh S5` PASS → WARN + empty `DPI_FLAGS` for `"auto"` | ✅ COMPLIANT |

### engine-robustness-delta (11/11 COMPLIANT)

| # | Requirement | Scenario | Test / Evidence | Result |
|---|---|---|---|---|
| 1 | Strict mode (F4) | Transient hyprctl blip does not abort a live session | Code inspection: `hyprctl keyword` (L328) + `hyprctl dispatch focuswindow` (L215) + every `notify-send` carry `\|\| true`; xfreerdp3/flock/jq do NOT | ✅ COMPLIANT |
| 2 | Strict mode (F4) | Real failure still propagates | Integration: `rdp-connect nonexistent-profile` exits 1; xfreerdp3 invocation (L340) has no `\|\| true` → EXIT trap fires | ✅ COMPLIANT |
| 3 | require_cmd (F6) | Missing jq aborts with exit 127 | Probe A (PATH-isolated fake bindir): rc=127, message `missing required command: jq (install via your package manager, e.g. jq)` | ✅ COMPLIANT |
| 4 | require_cmd (F6) | Missing both wofi and rofi aborts | Probe B (selector mode, both hidden): rc=127, message `missing required command: wofi or rofi (install one via your package manager)` | ✅ COMPLIANT |
| 5 | require_cmd (F6) | All binaries present proceeds normally | Probe C (all present): no missing-cmd message; engine reaches profile lookup (rc=1 for nonexistent) | ✅ COMPLIANT |
| 6 | /from-stdin gate (F7) | Build without /from-stdin:force is rejected | Probe D (mock xfreerdp3 without from-stdin): rc=1, message names `/from-stdin:force` | ✅ COMPLIANT |
| 7 | /from-stdin gate (F7) | Build with /from-stdin:force proceeds | Probe D (mock WITH from-stdin): proceeds past F7 gate to profile lookup | ✅ COMPLIANT |
| 8 | Flag arrays (F8) | Multi-monitor builds an array | Inline probe `build_mon_flags 3 "0,1,2"`: `declare -a MON_FLAGS=([0]="/multimon" [1]="/monitors:0,1,2")` | ✅ COMPLIANT |
| 9 | Flag arrays (F8) | Single-monitor builds /f array | Inline probe `build_mon_flags 1 "0"`: `declare -a MON_FLAGS=([0]="/f")` | ✅ COMPLIANT |
| 10 | Flag arrays (F8) | Empty DPI_FLAGS under set -u | Inline probe under `set -u`: `"${DPI_FLAGS[@]-}"` expands to nothing; no "unbound variable" abort | ✅ COMPLIANT |
| 11 | Cleanup guard (F9) | EXIT before log file exists does not crash | Probe A2 (missing jq → early exit): no `No such file` diagnostic leaked; cleanup's `[ -f "$LOG_FILE" ]` guard confirmed at L248 | ✅ COMPLIANT |

### installer-delta (12/12 COMPLIANT)

| # | Requirement | Scenario | Test / Evidence | Result |
|---|---|---|---|---|
| 1 | Distro detection | Arch host detected as pacman | Throwaway-HOME install: `📦 Detected package manager: pacman` | ✅ COMPLIANT |
| 2 | Distro detection | Debian host detected as apt | Code inspection L39: case branch `debian\|ubuntu\|linuxmint\|pop` | ✅ COMPLIANT |
| 3 | Distro detection | Fedora host detected as dnf | Code inspection L34: case branch `fedora\|rhel\|centos\|rocky\|alma` | ✅ COMPLIANT |
| 4 | Dep manifest | Missing jq is installed before engine deploy | Code inspection: `install_deps` (L263) runs BEFORE `deploy_files` (L266); `command -v` gate at L97 | ✅ COMPLIANT |
| 5 | Dep manifest | wofi or rofi satisfies the launcher dependency | Code inspection L105: `if ! command -v wofi && ! command -v rofi; then missing+=("$(pkg_for "$pkgr" wofi)")` (OR-satisfied → no install) | ✅ COMPLIANT |
| 6 | Unsupported distro | Alpine host is rejected with manual install instructions | Synthetic Alpine os-release: `detect_pkgr` returns 1; UNSUPPORTED message lists all 3 manager commands; `exit 1` BEFORE any file deploy | ✅ COMPLIANT |
| 7 | Idempotent deployment | Two consecutive runs produce identical files | Throwaway-HOME run 1 vs run 2: SHA256 byte-identical across engine + lib + 2 i18n + template + manifest | ✅ COMPLIANT |
| 8 | Real repo files | Engine is copied, not heredoc-generated | Deployed engine SHA256 == repo engine SHA256 (`1457d023...`); installer uses `install -D` from `$SCRIPT_DIR/engine/rdp-connect` | ✅ COMPLIANT |
| 9 | Smoke test | --help succeeds post-install | Smoke step (c) PASS; integration `rdp-connect --help` rc=0 | ✅ COMPLIANT |
| 10 | Smoke test | Parser probe rejects a known-bad profile | Smoke step (d) PASS; `parse_env_safe <(printf 'PATH=/x\n') profile` rejected | ✅ COMPLIANT |
| 11 | Smoke test | Smoke test failure aborts the installer | Code inspection L271: `run_smoke_test \|\| { echo "❌ Smoke test failed — aborting install."; exit 1; }` | ✅ COMPLIANT |
| 12 | Checksum manifest | Manifest is generated and stable | Manifest at `~/.local/state/rdp/manifest.sha256`; LC_ALL=C sort; byte-identical across 2 runs | ✅ COMPLIANT |

---

## Bugfix Slice Verification (T2.4 + T2.5 + T2.6)

### T2.4 — Parser robustness: **PASS**

- `tests/parser-probe.sh` → **24/24 PASS** (was 15; +9 new fixtures F15-F23)
- New fixtures explicitly cover: empty quoted value (F15 regression), CRLF after closing quote (F16 NEW), trailing space (F17 NEW), trailing tab (F18 NEW), inline comment after closing quote (F19 NEW), garbage after closing quote rejected (F20 NEW), unterminated quote with raw preview (F21 NEW), quoted `=` signs (F22 regression), quoted `#` interior preserved (F23 regression).
- Implementation: `lib/rdp-common.bash::parse_env_safe` L87 strips trailing `\r` BEFORE any value inspection; L118-133 uses first-closing-quote search + tail validation regex `^[[:space:]]*(#.*)?$`; L124/131 emit 40-char sanitized raw previews.

### T2.5 — Cleanup SESSION_START marker: **PASS**

- **Marker placement confirmed**: `log_event "SESSION_START" "pid=$$ profile=$PROFILE"` (engine L282) is the FIRST `log_event` call after the EXIT trap registration (L272), before the INICIO banner (L283).
- **awk extractor scopes by PID confirmed**: cleanup L249-253 uses `awk -v pid="$$"` with marker regex `"pid="pid"([^0-9]\|$)"` — PID-prefix safe (`pid=2222` does NOT match `pid=22222`).
- **Synthetic multi-session LOG_FILE test** (4 cases):
  - Test 1: current PID with its own ERROR → returns ONLY current session's ERROR (session A's stale ERROR NOT leaked). **PASS**
  - Test 2: PID-prefix safety (`pid=222` ≠ `pid=2222` marker). **PASS**
  - Test 3: current session with NO ERROR → returns empty (no leak from previous sessions). **PASS**
  - Test 4: legacy LOG_FILE without SESSION_START marker → returns empty (graceful degradation). **PASS**

### T2.6 — VPN whitespace trim: **PASS**

- `tests/vpn-trim-probe.sh` → **8/8 PASS** (4 expect-SKIP + 4 expect-ENTER with cleaned host).
- **Trim block placement confirmed** in `engine/rdp-connect`:
  - L162: `parse_env_safe "$ENV_FILE" profile` (parse)
  - L174-181: T2.6 trim block (HOST, VPN_CHECK, DOMAIN, PREFERRED_WS, LANG_OVERRIDE)
  - L292: `if [ -n "${VPN_CHECK:-}" ]; then` (VPN preflight guard)
  - Order: **parse_env_safe → trim → VPN preflight** ✅
- PASS_RDP and USER_RDP intentionally NOT trimmed (passwords/identifiers may legally have surrounding spaces) — documented in commit body + inline comment L170-171.
- T2.6 commit body explicitly references user bug report: *"User report: 'VPN required when empty' + confusing 'unterminated quote' on the same profile."*

---

## Structural Checks

| Check | Result | Evidence |
|---|---|---|
| `shellcheck --severity=warning engine/rdp-connect` | ✅ Clean | exit 0, 0 findings |
| `shellcheck --severity=warning lib/rdp-common.bash` | ✅ Clean | exit 0, 0 findings |
| `shellcheck --severity=warning install-rdp-framework.sh` | ✅ Clean | exit 0, 0 findings |
| `shellcheck --severity=warning tests/*.sh` | ✅ Clean | exit 0, 0 findings across all 4 probes |
| `bash -n engine/rdp-connect` | ✅ Clean | exit 0 |
| `bash -n lib/rdp-common.bash` | ✅ Clean | exit 0 |
| `bash -n install-rdp-framework.sh` | ✅ Clean | exit 0 |
| `bash -n tests/*.sh` | ✅ Clean | exit 0 across all 4 probes |
| `tests/parser-probe.sh` | ✅ **24/24 PASS** | exit 0; covers all 7 F3 spec scenarios + 7 design edge cases + 9 T2.4 robustness cases + 1 set-u safety re-verification |
| `tests/hidpi-probe.sh` | ✅ **8/8 PASS** | exit 0; covers all 5 hidpi-scaling spec scenarios + 3 robustness cases (malformed JSON, empty monitors, missing field) |
| `tests/pid-path-probe.sh` | ✅ **6/6 PASS** | exit 0; regression check from PR1 (instance-locking still correct) |
| `tests/vpn-trim-probe.sh` | ✅ **8/8 PASS** | exit 0; T2.6 regression (4 expect-SKIP, 4 expect-ENTER with cleaned host) |
| Throwaway-HOME install (idempotency) | ✅ PASS | Run 1 + Run 2 produce byte-identical deployed files AND manifest; smoke test 4/4 checks pass each run |

---

## Integration Sanity

| Check | Result | Notes |
|---|---|---|
| `rdp-connect --help` exits 0 | ✅ PASS | Prints full usage; works regardless of runtime deps on PATH |
| `rdp-connect nonexistent-profile` exits 1 | ✅ PASS | Profile-not-found path (does not reach xfreerdp3) |
| Deployed engine matches repo | ✅ PASS (throwaway) / ⚠ NOTE (user-local) | Throwaway install: `1457d023...` matches repo exactly. User-local `~/.local/bin/rdp-connect` is stale (`dc0fa11...` ≠ repo) — user has not re-installed locally; **expected per task instructions, not a failure**. |

---

## Diff Sanity

### Commit history (`git log main..HEAD --oneline`)

```
41735dd fix(vpn): trim whitespace from VPN_CHECK and HOST before TCP preflight   ← T2.6
d864e6a docs(sdd): append PR2 bugfix-slice progress (T2.4 + T2.5)
f4da861 fix(cleanup): scope error diagnostic to current session, not stale log   ← T2.5
eace9b1 fix(parser): tolerate trailing whitespace, CRLF, and inline comment      ← T2.4
40e3431 docs(sdd): mark T2.1-T2.3 complete; merge PR2 apply-progress; track verify-report-pr1
9ef351f feat(installer): cross-distro deterministic installer with smoke test    ← T2.3
c88a0f5 feat(robustness): strict mode, require_cmd, from-stdin gate, arrays      ← T2.2
6116413 fix(hidpi): replace bc/python3 with jq-native scale math                 ← T2.1
```

✅ **8 commits in correct dependency order**: T2.1 (DPI_FLAGS array) → T2.2 (set -u needs the array) → T2.3 (installer) → T2.4/T2.5/T2.6 (bugfix slice). Docs commits interleaved appropriately.

### Line counts

| Slice | Code+Test (reviewable) | All Files (incl. docs) |
|---|---|---|
| Original PR2 (T2.1-T2.3 + docs) | 644 ins / 77 del = **721 changed** | 644 ins / 77 del = **721 changed** |
| Bugfix slice (T2.4-T2.6 + docs) | 167 ins / 13 del = **280 changed** | 879 ins / 43 del = **922 changed** |
| **PR2 TOTAL** | **993 changed** | **1,635 changed** |

### T2.6 commit body references user bug report

✅ Confirmed — *"User report: 'VPN required when empty' + confusing 'unterminated quote' on the same profile. Investigation found three failure modes..."* + footer *"Task: T2.6 (baseline-hardening, PR2 bugfix slice — prompted by user report of misleading 'VPN requerida' message on a profile with whitespace in VPN_CHECK)"*.

### `size:exception` footer

✅ Correctly **NOT present** in any PR2 commit body. The user's forecast was ~405 (borderline); actual code+test is 993 and the orchestrator must decide how to handle the over-budget size (see Open Items).

---

## Coherence (Design Decisions)

| Decision | Followed? | Notes |
|---|---|---|
| DPI_FLAGS as array (T2.1) | ✅ Yes | `lib/rdp-common.bash` L188/205; engine expands `"${DPI_FLAGS[@]-}"` at L349 |
| `set -euo pipefail` tactical `\|\| true` (T2.2/F4) | ✅ Yes | Only on hyprctl keyword/dispatch + notify-send + wofi/rofi cancel; NOT on xfreerdp3/flock/jq |
| `require_cmd` exits 127 (T2.2/F6) | ✅ Yes | Verified by Probe A (jq missing → 127) + Probe B (wofi+rofi missing → 127) |
| `/from-stdin:force` startup gate (T2.2/F7) | ✅ Yes | Verified by Probe D (mock without → rc=1, mock with → proceeds) |
| `MON_FLAGS` + `DPI_FLAGS` quoted-safe expansion (T2.2/F8) | ✅ Yes | `"${MON_FLAGS[@]-}"` / `"${DPI_FLAGS[@]-}"` at engine L348-349 |
| `cleanup()` LOG_FILE guard (T2.2/F9) | ✅ Yes | `[ -f "$LOG_FILE" ] && [ -n "${START_TIME:-}" ]` at engine L248 (belt-and-suspenders beyond spec) |
| `detect_pkgr` order pacman→dnf→apt (T2.3) | ✅ Yes | install-rdp-framework.sh L27-41 |
| Manifest path `manifest.sha256` (T2.3 deviation) | ⚠ Accepted | Design said `install-manifest.sha256`; task prompt said `manifest.sha256`; flagged for archive reconciliation |
| Parser CRLF tolerance (T2.4) | ✅ Yes | `line="${line%$'\r'}"` at lib L87 before any value inspection |
| First-closing-quote search + tail validation (T2.4) | ✅ Yes | lib L118-133; fixture F20 codifies the previous silent-corruption bug |
| `SESSION_START` marker as FIRST log line (T2.5) | ✅ Yes | engine L282, before INICIO banner (L283) |
| `awk` extractor scoped by PID (T2.5) | ✅ Yes | engine L249-253; PID-prefix-safe regex |
| VPN trim after parse, before preflight (T2.6) | ✅ Yes | engine L174-181 (trim) between L162 (parse) and L292 (preflight) |
| PASS_RDP/USER_RDP NOT trimmed (T2.6) | ✅ Yes | Only HOST/VPN_CHECK/DOMAIN/PREFERRED_WS/LANG_OVERRIDE trimmed; documented in commit body |

---

## Issues Found

### CRITICAL
None.

### WARNING

1. **PR2 over the 400-line review budget.** Per the SDD Review Workload Guard, PR2's code+test diff is 993 lines (1,635 total including openspec docs). The user's pre-flight forecast was ~405 (borderline); reality is significantly higher because the forecast counted only net-new logic, not git diff stat. **No `size:exception` footer is currently in any commit body.** Orchestrator must decide before opening PR2:
   - (a) Add `size:exception` footer to the merge commit (justified: bugfix slice is inherently coupled to the parser/cleanup code that landed in the same PR — splitting would break TDD/verify coherence), OR
   - (b) Split into PR2a (T2.1-T2.3, ~721 code+test lines) and PR2b (T2.4-T2.6, ~280 code+test lines) — note that PR2a is STILL over budget on its own, so this only helps marginally.

2. **Documentation gap: `tasks.md` lacks T2.4/T2.5/T2.6 entries.** The user's prompt expected these to be documented ("now includes T2.4, T2.5, T2.6 — confirm these are documented"), but `tasks.md` only goes up to T2.3. Close at archive.

3. **Documentation gap: `apply-progress.md` lacks a T2.6 section.** T2.4 and T2.5 ARE documented in the "PR2 — bugfix slice" section, but T2.6 (VPN trim) was committed AFTER the last docs update and has no progress entry. Close at archive.

4. **Process note: `verify-report-pr1.md` committed on PR2 branch.** The PR1 verify report (+186 lines) appears in `main..HEAD` because it was added in commit `40e3431` (PR2 docs commit). Ideally it would have been on the PR1 branch and merged to main via PR1. Not a blocker; flagged for process awareness.

5. **Spec gaps to amend at archive** (already noted in apply-progress.md):
   - Parser robustness scenarios (CRLF tolerance, trailing whitespace, inline comment after closing quote) are implemented + verified but NOT yet codified in `engine-robustness-delta.md`.
   - Cleanup session-isolation requirement is implemented + verified but NOT yet codified.
   - Per orchestrator note: amend spec at archive time.

6. **Design reconciliation at archive** (already noted in apply-progress.md):
   - Manifest path (`manifest.sha256` vs `install-manifest.sha256`).
   - `detect_pkgr` uses grep instead of sourcing os-release (functionally equivalent, safer under set -u).
   - Smoke test uses `--severity=warning` instead of default severity (engine has known info-level findings).

### SUGGESTION
None.

---

## Bugfix Verification Summary

| Bugfix | Status | Evidence |
|---|---|---|
| T2.4 (parser robustness) | ✅ PASS | parser-probe.sh **24/24** incl. new F15-F23 (CRLF, trailing ws/tab, inline comment, garbage-rejected, unterminated+raw-preview) |
| T2.5 (SESSION_START marker) | ✅ PASS | Engine L282 writes marker as first log_event; cleanup L249-253 awk scopes by PID; 4/4 synthetic multi-session tests pass |
| T2.6 (VPN whitespace trim) | ✅ PASS | vpn-trim-probe.sh **8/8**; trim block in engine L174-181 runs AFTER parse_env_safe (L162) and BEFORE VPN preflight (L292); PASS_RDP/USER_RDP intentionally untouched |

---

## Open Items for Archive

1. **Update `tasks.md`** to add T2.4, T2.5, T2.6 entries under "PR2 — robustness + installer" with per-scenario manual-verification evidence (mirror what apply-progress.md already has for T2.4/T2.5).
2. **Update `apply-progress.md`** to add a T2.6 section (the bugfix-slice section currently covers T2.4 + T2.5 only).
3. **Amend `engine-robustness-delta.md`** at archive to codify: (a) parser CRLF/whitespace/inline-comment tolerance scenarios, (b) cleanup SESSION_START session-isolation requirement.
4. **Reconcile design vs implementation** at archive: manifest path (`manifest.sha256`), os-release parsing approach (grep vs source), shellcheck severity (`warning` vs default).
5. **Orchestrator delivery decision**: resolve PR2 size overage (size:exception footer OR split) BEFORE opening PR2.
6. **Reconcile `verify-report-pr1.md`** location — currently on PR2 branch, ideally belongs on main via PR1.

---

## Verdict

# ✅ PASS WITH WARNINGS

**All 28 PR2 spec scenarios COMPLIANT. All 4 executable probes pass (24/24 + 8/8 + 6/6 + 8/8 = 46/46). Bugfix slice (T2.4/T2.5/T2.6) fully verified. Structural checks clean. Throwaway-HOME install idempotent. PR2 is ready to merge from a verification standpoint.**

Warnings are documentation/size only — none block merging. The size warning needs orchestrator resolution before opening PR2; the documentation warnings can be closed at archive.

---

## Skill Resolution

`paths-injected` — 3 skills loaded via orchestrator-injected paths:
- `/home/hbuddenberg/.config/opencode/skills/sdd-verify/SKILL.md` (primary phase skill)
- `/home/hbuddenberg/.config/opencode/skills/_shared/SKILL.md` (shared SDD references)
- `/home/hbuddenberg/.agents/skills/omarchy/SKILL.md` (loaded per instruction; **not relevant** to this bash project verification — flagged for orchestrator awareness; no omarchy commands invoked)
