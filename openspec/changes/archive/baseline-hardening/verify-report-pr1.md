# Verify Report — baseline-hardening PR1 (security-core)

> **Slice scope**: PR1 only — T1.1 → T1.4 (F10-prep + F3 + F2 + F5).
> PR2 (T2.1 → T2.3) is **OUT OF SCOPE** for this report.
>
> **Change**: `baseline-hardening`
> **Branch**: `pr1/security-core` (local only — not pushed)
> **Base**: `main` @ `ef04f56`
> **Mode**: Standard (strict_tdd: false — no test runner; manual + structural verification)
> **Verdict**: **PASS WITH WARNINGS** — all 16 in-scope spec scenarios compliant; 4 PR1 tasks complete; 3 WARN-level hygiene observations (none block merge).

## Executive Summary

PR1 security-core is implementation-complete and verified at runtime. Every one of the 16 spec scenarios across `engine-security-delta` (9) and `instance-locking-delta` (7) has covering evidence from a passing executable probe or a throwaway-HOME engine integration run. Structural checks (shellcheck on lib/installer/probes, `bash -n` on all bash, parser-probe 15/15, pid-path-probe 6/6) are green. The deployed engine byte-for-byte matches the repo source (5/5 files `diff -q` clean) with the design-mandated permission modes (700/644/600). Hostile `PATH=` injection in either a profile or an i18n file aborts the engine with exit 1 and a precise `parse_env_safe: <file>:<line>: <reason>` diagnostic, and the ambient `$PATH` is provably unchanged. The PID lockfile is uid-private under `XDG_RUNTIME_DIR`, two users cannot collide, stale locks are reclaimed through flock's process-bound semantics, the live-peer branch exits 0, and the EXIT trap removes the new path while tolerating early-exit-before-flock. The 3 WARNs below are cosmetic / hygiene only.

## Artifacts

- **File**: `openspec/changes/baseline-hardening/verify-report-pr1.md` (this file)
- **Engram mirror**: topic_key `sdd/baseline-hardening/verify-report-pr1` (project `rdp-connect`)
- **Source code under test**: `engine/rdp-connect`, `lib/rdp-common.bash`, `install-rdp-framework.sh`, `i18n/{es,en}.env`, `template/template.env`
- **Test probes**: `tests/parser-probe.sh` (15 fixtures), `tests/pid-path-probe.sh` (6 scenarios)

## Scenario Compliance Matrix

### engine-security-delta.md (9 scenarios — F3 + F2)

| Req | Scenario | Covering Evidence | Status |
|---|---|---|---|
| parse_env_safe key allowlist | Dangerous key in profile is rejected | `tests/parser-probe.sh` F1 (`PATH=/usr/bin/attacker` → rc=1, msg `rejected key 'PATH'`) + throwaway-HOME engine probe (`PATH=/evil` in `profiles/partner.env` → exit 1, ambient `$PATH` byte-identical before/after) | ✅ COMPLIANT |
| parse_env_safe key allowlist | Unknown non-allowlisted key is rejected | `tests/parser-probe.sh` F2 (`FOO=bar` → rc=1) + engine integration (`UNKNOWN_KEY=junk` → `parse_env_safe: …:2: rejected key 'UNKNOWN_KEY'`, exit 1, no PID file created) | ✅ COMPLIANT |
| parse_env_safe key allowlist | All allowlisted keys accepted | `tests/parser-probe.sh` F3 (all 7 keys → rc=0) + throwaway-HOME engine reaches the `INICIO DE SESIÓN RDP` + `Verificando disponibilidad de puerto 3389` log lines (parser+i18n+pid+flock all succeeded before host preflight) | ✅ COMPLIANT |
| Quote and comment handling | Inline comment inside double-quoted value is preserved | `tests/parser-probe.sh` F4 (`HOST="server # production"` → val=`server # production`) | ✅ COMPLIANT |
| Quote and comment handling | Trailing comment after unquoted value is stripped | `tests/parser-probe.sh` F5 (`PREFERRED_WS=3  # target workspace` → val=`3`) | ✅ COMPLIANT |
| Quote and comment handling | Single-quoted value is unquoted | `tests/parser-probe.sh` F6 (`DOMAIN='MicrosoftAccount'` → val=`MicrosoftAccount`) | ✅ COMPLIANT |
| Quote and comment handling | Malformed line aborts parsing | `tests/parser-probe.sh` F7 (no-`=` line → rc=1, msg `no '=' delimiter`) + spec augmentation F12 (`0KEY=v` invalid charset → rc=1) | ✅ COMPLIANT |
| i18n via hardened parser | i18n file with injected key is rejected | `tests/parser-probe.sh` F13 i18n mode (`PATH=/x` → rc=1, msg `rejected i18n key 'PATH'`) + throwaway-HOME engine integration (hostile `es.env` with `PATH=/evil` → `parse_env_safe: …/i18n/es.env:2: rejected i18n key 'PATH'`, exit 1, ambient `$PATH` intact) + `grep -nE 'source[[:space:]]+.*\.env'` returns 0 matches in both repo and deployed engine | ✅ COMPLIANT |
| i18n via hardened parser | Legitimate MSG_* keys load | `tests/parser-probe.sh` F13 (`MSG_PROMPT_SELECT=…` → rc=0) + throwaway-HOME engine with shipped `es.env` reaches host preflight (i18n loaded silently, no rejection) | ✅ COMPLIANT |

**Bonus coverage** (not spec scenarios but called out in the verify brief):
- Password with embedded `=` — F8 (`PASS_RDP=secret=with=equals` → val=`secret=with=equals`) ✅
- Unterminated quote — F9 ✅
- Unquoted `#` without whitespace (T1.2 augmentation, flagged for spec-author review at archive) — F10 ✅
- Blank lines / full-line comments skipped — F11 ✅
- Invalid key charset (starts with digit) — F12 ✅
- `set -u` safety (rejected assoc key returns 1, does NOT raise "unbound variable") — F14 ✅
- Multiline value rejection — manual probe: `HOST=line1\nline2noequals\n` → `parse_env_safe: …:2: no '=' delimiter`, rc=1 ✅
- Empty value handling — manual probe: `VPN_CHECK=` accepted, val=`<empty>` ✅

### instance-locking-delta.md (7 scenarios — F5)

| Req | Scenario | Covering Evidence | Status |
|---|---|---|---|
| uid-private PID path under XDG_RUNTIME_DIR | XDG_RUNTIME_DIR set resolves under /run/user | `tests/pid-path-probe.sh` S1 (`XDG_RUNTIME_DIR=/run/user/1000` + uid 1000 → `/run/user/1000/rdp-partner-1000.pid`) | ✅ COMPLIANT |
| uid-private PID path under XDG_RUNTIME_DIR | XDG_RUNTIME_DIR unset falls back to /tmp with uid suffix | `tests/pid-path-probe.sh` S2 (`XDG_RUNTIME_DIR` unset + uid 1000 → `/tmp/rdp-partner-1000.pid`, uid suffix retained) | ✅ COMPLIANT |
| uid-private PID path under XDG_RUNTIME_DIR | Two users on the same host do not collide | `tests/pid-path-probe.sh` S3 (XDG set: uid 1000 vs 1001 → distinct paths) + S4 (XDG unset: still distinct via uid suffix) + S5 (new path ≠ legacy `/tmp/rdp-partner.pid`) + S6 (per-profile isolation) | ✅ COMPLIANT |
| Stale lockfile reclamation | Stale lock from a crashed prior instance is reclaimed | Throwaway-HOME engine probe: pre-written `99999` PID content (not a live process) → engine's `flock -n` succeeds (kernel released the crashed peer's lock), engine proceeds past flock to host preflight (no peer-detected WARN logged). Design coherence: flock is process-bound → `echo "$$" >&200` overwrites stale content. | ✅ COMPLIANT |
| Stale lockfile reclamation | Live lock from a running peer is honored | Throwaway-HOME engine probe: real flock contention — peer subshell acquires flock on fd 200; second engine instance's `flock -n` fails → engine logs `WARN Instancia activa pid=? detectada. Enfocando ventana...`, calls `hyprctl dispatch focuswindow … \|\| true`, and exits **0** | ✅ COMPLIANT |
| EXIT trap cleans the new path (pairs with F9) | Normal session exit cleans up | Throwaway-HOME engine probe: valid profile reaches host preflight, fails (unroutable IP) → exit 1; PID file at new path `${XDG_RUNTIME_DIR}/rdp-partner-1000.pid` is removed by trap (`[ -f "$PID_FILE" ] && rm -f "$PID_FILE"`). Confirmed: directory listing empty post-exit. | ✅ COMPLIANT |
| EXIT trap cleans the new path (pairs with F9) | Early-exit before flock does not error | Throwaway-HOME engine probe: hostile profile (`UNKNOWN_KEY=junk`) → parser rejects at line 90, engine exits 1 BEFORE reaching `compute_pid_path`. PID file never created. Trap fires, `[ -f "$PID_FILE" ]` returns false → `rm -f` not invoked → **no "No such file" diagnostic on stderr**. | ✅ COMPLIANT |

**Compliance summary**: 16/16 scenarios ✅ COMPLIANT (0 PARTIAL, 0 UNTESTED, 0 FAILING).

## Structural Checks

| Check | Command | Result | Notes |
|---|---|---|---|
| `bash -n` | `bash -n lib/rdp-common.bash engine/rdp-connect install-rdp-framework.sh tests/*.sh` | ✅ PASS | All 5 files syntactically clean |
| `shellcheck` lib | `shellcheck lib/rdp-common.bash` | ✅ PASS (0 findings) | Clean |
| `shellcheck` installer | `shellcheck install-rdp-framework.sh` | ✅ PASS (0 findings) | Clean |
| `shellcheck` engine | `shellcheck engine/rdp-connect` | ⚠ PASS-WITH-INFO (12 info-level findings, all pre-existing) | See "Engine shellcheck baseline" below |
| `shellcheck` parser-probe | `shellcheck tests/parser-probe.sh` | ✅ PASS (0 findings) | Clean |
| `shellcheck` pid-path-probe | `shellcheck tests/pid-path-probe.sh` | ⚠ PASS-WITH-INFO (7 info-level findings) | SC2329 (mocked `id` is invoked indirectly by sourced lib — expected) + SC2015 (`A && B \|\| C` pattern used as ternary; safe because `ok`/`no` have no side effects beyond printing). Cosmetic only. |
| Parser probe | `./tests/parser-probe.sh` | ✅ PASS | 15/15 fixtures pass, exit 0 |
| PID path probe | `./tests/pid-path-probe.sh` | ✅ PASS | 6/6 scenarios pass, exit 0 |
| Throwaway-HOME install | `HOME=$(mktemp -d) ./install-rdp-framework.sh` | ✅ PASS | All 5 deployed files `diff -q` clean vs. repo source; modes 700/644/600/600/600 match design |
| Engine source-i18n grep | `grep -nE 'source[[:space:]]+.*\.env' ~/.local/bin/rdp-connect` | ✅ PASS | 0 matches in both repo and deployed engine |
| Legacy PID path grep | `grep -nE '/tmp/rdp-[a-zA-Z$_]' engine/rdp-connect` | ✅ PASS | 0 matches — legacy path expunged |

### Engine shellcheck baseline (pre-existing, NOT introduced by PR1)

These 12 findings were surfaced by T1.1's extraction (the baseline engine lived inside a `cat << 'ENGINE'` heredoc, which shellcheck skips as a string literal). Each is addressed by a specific later task and is documented in `apply-progress.md`:

| SC | Location | Owner |
|---|---|---|
| SC1091 | line 16 `source "$LIB_FILE"` | info-only; `shellcheck source=` directive present |
| SC2059 (×5) | lines 45, 57, 61, 95, 167, 176, 207 | PR2 cosmetic pass (i18n vars used as printf format — works because all values are trusted dictionaries) |
| SC2012 (×2) | lines 87, 89 `ls "$PROFILES_DIR" \| wofi/rofi` | acceptable (dir is operator-controlled, no whitespace in profile names enforced by template) |
| SC2086 (×2) | lines 220, 221 `$MON_FLAGS` / `$DPI_FLAGS` | T2.2 (F8 array refactor — these become `"${MON_FLAGS[@]-}"` / `"${DPI_FLAGS[@]-}"`) |

None of these are blockers for PR1. The two SC2086 cases are the load-bearing ones for F4 (set -e) in PR2 — they MUST be resolved by T2.2 before `set -u` ships.

## Diff Sanity

| Metric | Forecast (tasks.md) | Actual | Verdict |
|---|---|---|---|
| PR1 implementation commits | 4 (T1.1–T1.4) | 4 (`fa2b10e`→`e0904be`) | ✅ |
| PR1 implementation changed lines | ≈710 | 688 ins + 284 del = 972 (incl. T1.1 verbatim move) | ⚠ above forecast, but T1.1 is `size:exception` |
| PR1 reviewable lines (excl. T1.1 verbatim move) | ≈140 | T1.2+T1.3+T1.4 = 360 ins + 57 del = 417 | ⚠ marginally over 400-line budget; F3 probe (~163 LOC) is the bulk |
| T1.1 `size:exception` footer | required in commit body | present as `size-exception: mechanical extraction move (no logic change)` | ⚠ WARN — see below |
| Files touched (implementation) | engine, lib, i18n, template, installer, tests, tasks.md | exactly matches | ✅ |

### Branch observation (WARN)

The branch contains **5 commits between `main` and `HEAD`**, not 4 as stated in the verify brief. The 5th is `fbbc516 docs(sdd): baseline-hardening planning artifacts (explore, proposal, specs, design, tasks)`, which also lands `.atl/skill-registry.md` (39 lines) and `.engram/config.json` (3 lines). The 4 implementation commits (`fa2b10e` → `e0904be`) are exactly as expected. The planning docs commit is reasonable to ship alongside the change (reviewers need the spec/design to evaluate the code), but `.atl/` and `.engram/` are tool-state directories that arguably belong in `.gitignore` rather than the PR diff. Flagged for the orchestrator/PR-author — squashing the planning commit into the PR is fine; consider adding `.atl/` and `.engram/` to `.gitignore` before push (or in a follow-up).

## Design Coherence

| Decision (design.md) | Followed? | Notes |
|---|---|---|
| Repo file layout (`engine/`, `lib/`, `i18n/`, `template/`) | ✅ Yes | All paths match `installer-delta` exactly; `diff -q` clean |
| Allowlist via assoc array; `MSG_*` prefix glob for i18n | ✅ Yes | `_PROFILE_KEYS` declared at lib top; `-v` (is-set) test used instead of `${arr[$k]}` for `set -u` safety — re-verified by F14 |
| First-`=` split preserves `=` in passwords | ✅ Yes | `${line%%=*}` / `${line#*=}` — F8 confirms |
| Quote/comment handling (3 value forms) | ✅ Yes | F4/F5/F6 confirm; F10 augmentation (reject unquoted `#` without whitespace) is documented deviation flagged for archive |
| `printf -v` retained despite spec wording | ✅ Yes (with caveat) | Spec says "parameter expansion only"; `printf -v` is the codebase's existing pattern and does NOT execute content. Open question carried to archive. |
| No `source` of any `.env` or `~/.config/rdp/**` | ✅ Yes | grep returns 0 matches |
| PID path `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-$(id -u).pid` | ✅ Yes | Verbatim from design §"PID path + stale-lock reclamation" |
| Stale reclamation via flock process-bound semantics | ✅ Yes | No explicit stale-PID liveness check; relies on kernel releasing flock on peer crash. Validated by integration probe (stale PID 99999 → flock -n succeeds → engine proceeds). |
| Live-peer branch: focus + exit 0 | ✅ Yes | Integration probe confirmed exit 0 |
| EXIT trap `[ -f ] && rm -f` on new path | ✅ Yes | Trap tolerates early-exit; F9 LOG_FILE guard correctly deferred to T2.2 |
| Engine call site gates on parser rc (`parse_env_safe … \|\| { notify-send; exit 1; }`) | ✅ Yes | This is what makes F3 load-bearing in PR1 (no `set -e` yet — F4 lands in T2.2). Without this gate, hostile profiles would silently continue. |

## Issues Found

**CRITICAL**: None.

**WARNING** (3 — none block merge):

1. **Branch contains 5 commits, not 4.** The extra commit is `fbbc516 docs(sdd)` (SDD planning artifacts, 1714 insertions). It also lands `.atl/skill-registry.md` and `.engram/config.json` — tool-state files that probably belong in `.gitignore`. The 4 implementation commits are correct; only the planning/docs commit is hygienically noisy. **Recommended action**: either (a) accept as-is (planning docs are useful PR context), or (b) split the tool-state files out into a separate `chore(repo)` commit on `main` before opening PR1. Not a merge blocker.

2. **`size:exception` footer spelling drift.** The T1.1 commit body uses `size-exception:` (hyphen) but the canonical token in `_shared/sdd-phase-common.md` §E and `tasks.md` is `size:exception` (colon). The maintainer's intent is unambiguous and the footer is present, but automated tooling that greps for the literal `size:exception` token will miss this commit. **Recommended action**: amend the T1.1 commit body to use `size:exception:` (colon) before push, OR update the convention to accept both spellings.

3. **Engine shellcheck SC2086 on `$MON_FLAGS` / `$DPI_FLAGS` (lines 220-221).** These are the load-bearing cases for F4's `set -u` in T2.2. They are pre-existing (not introduced by PR1) and are explicitly owned by T2.2 (F8 array refactor). Not a PR1 merge blocker, but **MUST** be resolved before PR2 lands `set -euo pipefail` — otherwise the engine will abort on every empty-`DPI_FLAGS` invocation.

**SUGGESTION** (2 — optional polish):

1. **`compute_pid_path` mocking in `pid-path-probe.sh` triggers SC2329.** The `id()` function override is invoked indirectly by the sourced lib, which shellcheck cannot see. The existing `# shellcheck disable=SC2329` is not present on line 23 — adding it would silence the warning without changing behavior. Optional.

2. **Tests use `ok … && … \|\| no …` ternary pattern (SC2015).** Safe in this context (no side effects in `ok`/`no`), but a future refactor to `if/then/else` would be cleaner. Optional.

## Open Items Deferred to PR2

These are explicitly OUT OF SCOPE for PR1 and ride in PR2 (T2.1 / T2.2 / T2.3). Listed here so reviewers know what PR1 does NOT close:

- **F1 HiDPI math (T2.1)** — `bc` and `python3` are still invoked at engine lines 186-187 (`$(echo "$SCALE > 1.0" \| bc -l …)` and `python3 -c "print(int($SCALE * 100))"`). PR1 does not touch this. SC2086 on `$DPI_FLAGS` (line 221) is the same area.
- **F4 `set -euo pipefail` (T2.2)** — engine line 4 is `set -o pipefail` only. Full strict mode lands in T2.2 alongside F8 arrays (atomic — never an intermediate `set -u` without arrays).
- **F6 `require_cmd` preflight (T2.2)** — no startup binary check for `xfreerdp3`/`hyprctl`/`jq`/`notify-send`/`flock`/`wofi|rofi` yet. The engine currently fails late at first use.
- **F7 `/from-stdin:force` gate (T2.2)** — engine unconditionally passes `/from-stdin:force` to `xfreerdp3` (line 216); no `xfreerdp3 /help` build check yet.
- **F8 array flags (T2.2)** — `$MON_FLAGS` and `$DPI_FLAGS` still interpolated as unquoted strings (lines 220-221). Resolve via `"${MON_FLAGS[@]-}"` / `"${DPI_FLAGS[@]-}"` in T2.2.
- **F9 LOG_FILE trap guard (T2.2)** — T1.4 ships ONLY the F5 PID_FILE guard (`[ -f "$PID_FILE" ] && rm -f "$PID_FILE"` at line 156). The matching `[ -f "$LOG_FILE" ]` guard for the ERROR-tail `grep` at line 142 rides in T2.2 where `set -e` makes it load-bearing. Pre-PR2 this is dormant because `set -e` is not active.
- **F10 cross-distro installer (T2.3)** — current installer is the simplified T1.1 version (no `detect_pkgr`, no dep-manifest, no smoke test, no checksum manifest). PR1's installer change is purely the heredoc→`install -D` refactor.
- **Multi-peer EXIT-trap race** (noted in `apply-progress.md` T1.4 discoveries): if the peer-detected branch fires, the trap unlinks a PID file the first instance still holds open via fd 200 — flock continues to work for the first instance (kernel-level, per-inode), but a THIRD instance starting later could `exec 200>` a new inode at the same path and bypass the first's lock. The spec scenario "Live lock from a running peer is honored" tests only a single second peer (which works correctly), so this is NOT a PR1 spec violation. Real fix: gate the trap `rm` on a `_LOCK_ACQUIRED` flag set only after `flock -n` succeeds. Flagged for PR2 or a follow-up hardening task.

## Verdict

**PASS WITH WARNINGS**

All 16 in-scope spec scenarios are compliant with runtime evidence. All structural checks pass (engine shellcheck findings are pre-existing and explicitly owned by PR2 tasks). The F3 security boundary is verifiably load-bearing: hostile `PATH=` injection in either a profile or an i18n file aborts the engine at exit 1 with the ambient `$PATH` byte-identical before/after. The F5 PID path is uid-private under `XDG_RUNTIME_DIR`, stale locks are reclaimed, live peers are honored with exit 0, and the EXIT trap tolerates early-exit-before-flock. PR1 is **ready to merge** once the 3 WARN-level hygiene items are resolved or explicitly accepted by the maintainer.

---

## Return Envelope (to orchestrator)

- **status**: `pass` (with warnings — see Issues Found §WARNING)
- **executive_summary**: 16/16 PR1 spec scenarios compliant with runtime evidence; all structural checks green; 4/4 PR1 tasks implementation-complete. Three WARN-level hygiene observations (extra planning commit + tool-state files in diff, `size-exception` vs `size:exception` spelling drift, SC2086 cases owed to PR2) — none block merge.
- **artifacts**:
  - `openspec/changes/baseline-hardening/verify-report-pr1.md`
  - engram topic_key `sdd/baseline-hardening/verify-report-pr1` (project `rdp-connect`)
- **scenarios_verified**: `{ passed: 16, warned: 0, failed: 0, total: 16 }`
- **scenario_results**: see Compliance Matrix above (16 ✅ COMPLIANT rows)
- **structural_checks**: `{ shellcheck: pass (lib/installer/probes clean; engine has 12 pre-existing info-level findings owned by PR2), bash_n: pass, parser_probe: pass (15/15), pid_probe: pass (6/6), throwaway_install: pass (5/5 files diff-clean, modes match design) }`
- **open_items_for_pr2**:
  - F1 HiDPI jq-native math (T2.1) — `bc`/`python3` still at engine lines 186-187
  - F4 `set -euo pipefail` (T2.2) — only `set -o pipefail` active in PR1
  - F6 `require_cmd` preflight (T2.2) — no startup binary checks
  - F7 `/from-stdin:force` xfreerdp3 build gate (T2.2)
  - F8 array flags (T2.2) — SC2086 on `$MON_FLAGS`/`$DPI_FLAGS` lines 220-221 is the load-bearing case
  - F9 LOG_FILE trap guard (T2.2) — only PID_FILE guard shipped in T1.4
  - F10 cross-distro installer (T2.3) — no detect_pkgr / dep manifest / smoke / checksum yet
  - Multi-peer EXIT-trap race (T1.4 discovery) — spec-compliant for single-peer scenario; real multi-peer fix needs `_LOCK_ACQUIRED` flag
- **pr1_ready_to_merge**: `true` (after the 3 WARN items are resolved or explicitly accepted)
- **next_recommended**:
  1. Address the 3 WARNs (amend T1.1 commit body to `size:exception:`; decide on `.atl/`+`.engram/` disposition; ack SC2086 deferral to T2.2).
  2. Push `pr1/security-core` to remote.
  3. Open **PR1 targeting `main`** (stacked-to-main strategy — NOT a feature-tracker chain; PR2 branches from `main` after PR1 merges).
  4. After PR1 merges, run `sdd-apply` for **PR2 (T2.1 → T2.3)** branching from updated `main`.
- **skill_resolution**: `paths-injected` — 3 skills loaded (`sdd-verify`, `_shared`, `omarchy`) via the orchestrator's `## Skills to load before work` block before any task work. The `omarchy` skill provided Hyprland context useful for interpreting `hyprctl dispatch focuswindow` behavior in the live-peer-honored scenario; no Omarchy source files were modified (verify is read-only).
