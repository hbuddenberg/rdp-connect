# Tasks: multi-peer-race

> **Project**: `rdp-connect` · **Mode**: openspec + engram mirror · **Strict TDD**: active (RED → GREEN → REFACTOR)
> **Origin**: `proposal.md` + `specs/{instance-locking,engine-robustness}-delta.md` (3 requirements, 11 scenarios) + `design.md`
> **Date**: 2026-07-21

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~186 (engine +16 net, tests +170) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR · 3 work-unit commits (RED → GREEN → REFACTOR) |
| Delivery strategy | single-pr |
| Chain strategy | pending (single PR, no chain active) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Base |
|------|------|-----------|------|
| 1 (RED) | `tests/multi-peer-race.bats` — 11 `@test` blocks (7 failing, 4 backstops) | `pr/multi-peer-race` | `main` |
| 2 (GREEN) | `engine/rdp-connect` — `setpgid 0 0` + `kill -- -$$` + drop unlink | `pr/multi-peer-race` | commit 1 |
| 3 (REFACTOR) | `engine/rdp-connect` — comment hygiene only, no behavior change | `pr/multi-peer-race` | commit 2 |

---

## Phase 1: RED — failing bats for R7 race + orphan-kill

> **Commit**: `test(multi-peer-race): add failing bats for R7 race + orphan-kill`
> **Files**: `tests/multi-peer-race.bats` (new) · **Size**: ~+170 LOC · **Depends on**: nothing

- [ ] 1.1 Create `tests/multi-peer-race.bats`; load `tests/test_helper.bash`; add header documenting strict-TDD RED intent and the 7 RED / 4 GREEN split per `design.md` table.
- [ ] 1.2 Add source-grep test `engine_calls_setpgid_at_startup` (tier 1): asserts `grep -E 'setpgid|setsid' engine/rdp-connect` matches.
- [ ] 1.3 Add subshell-reproduction tests for the instance-locking contract using **sentinel files** (NOT fixed sleeps): `clean_exit_leaves_pid_file_on_disk`, `sigterm_exit_trap_does_not_unlink_pid_file`, `early_exit_before_flock_does_not_error` (backstop), `next_start_reclaims_after_clean_exit`, `next_start_reclaims_after_crashed_predecessor` (backstop), `two_concurrent_starts_serialize_via_flock`.
- [ ] 1.4 Add subshell-reproduction tests for the engine-robustness signal contract using `child_running.sentinel` / `corpse.sentinel`: `exit_trap_fires_kill_on_process_group`, `orphan_xfreerdp3_killed_on_signal_exit`, `process_group_kill_is_scoped_to_engine_group_only`.
- [ ] 1.5 Add meta-test `single_instance_behavior_unchanged_regression` asserting the existing 7 `.bats` files (66 `@test`) are intact via `$BATS_TEST_NAMES` count.
- [ ] 1.6 Run `bats tests/multi-peer-race.bats`; confirm expected split **7 RED + 4 GREEN**. Confirm `make ci` is RED (expected — this is the RED gate).
- [ ] manual-verification — scenario `Normal session exit leaves the lockfile on disk` (`@test clean_exit_leaves_pid_file_on_disk`): RED — current engine unlinks `$PID_FILE` in cleanup.
- [ ] manual-verification — scenario `Signal-induced EXIT trap does NOT unlink the lockfile` (`@test sigterm_exit_trap_does_not_unlink_pid_file`): RED.
- [ ] manual-verification — scenario `Next start after a CLEAN exit reclaims via flock -n` (`@test next_start_reclaims_after_clean_exit`): RED — current engine leaves no file to reclaim.
- [ ] manual-verification — scenario `Two concurrent starts against the same profile serialize` (`@test two_concurrent_starts_serialize_via_flock`): RED — reproduces R7 (contender's `flock -n` succeeds on a fresh inode during owner's unlink window).
- [ ] manual-verification — scenario `Engine calls setpgid (or setsid) at startup` (`@test engine_calls_setpgid_at_startup`): RED — `setpgid`/`setsid` absent from engine source.
- [ ] manual-verification — scenario `EXIT trap fires kill on the engine's process group` (`@test exit_trap_fires_kill_on_process_group`): RED — no group kill in cleanup.
- [ ] manual-verification — scenario `Orphaned xfreerdp3 (simulated via background sleep) is killed when the trap fires` (`@test orphan_xfreerdp3_killed_on_signal_exit`): RED — simulated xfreerdp3 survives engine SIGTERM (`corpse.sentinel` appears).
- [ ] manual-verification — scenario `Process-group kill does NOT affect processes outside the engine's group` (`@test process_group_kill_is_scoped_to_engine_group_only`): RED — no kill → scope invariant untestable.
- [ ] manual-verification — backstop scenarios `Early-exit before flock does not error`, `Next start after a CRASHED predecessor reclaims via flock -n`, `Single-instance PID-file behavior is unchanged (regression)` — GREEN at T1 (regression backstops already satisfied by current engine).

---

## Phase 2: GREEN — engine fix for R7 + orphan-kill

> **Commit**: `fix(engine): preserve PID file path + process-group kill in trap (R7)`
> **Files**: `engine/rdp-connect` · **Size**: ~+16 LOC net · **Depends on**: T1 (RED must exist to confirm GREEN)

- [ ] 2.1 At engine L8 (immediately after `set -euo pipefail` at L7, before the `--help` block at L17), insert `setpgid 0 0 || true` — engine becomes group leader with PGID == `$$`; `|| true` covers the already-leader case (e.g. launched via `setsid`).
- [ ] 2.2 In `cleanup()` (L222), insert `kill -- -$$ 2>/dev/null || true` as the **second** statement — immediately AFTER `EXIT_CODE=$?` (L223) and BEFORE `END_TIME=$(date +%s)` (L224). The `--` is mandatory (without it `kill -$$` could parse as `-1`/SIGHUP); `|| true` covers the no-children early-exit case.
- [ ] 2.3 Replace the unlink block at L264-266 (`if [ "${_LOCK_ACQUIRED:-false}" = true ] && [ -f "$PID_FILE" ]; then rm -f "$PID_FILE"; fi`) with `true` plus a 1-line placeholder comment (full rationale added in Phase 3). KEEP the `_LOCK_ACQUIRED=true` assignment at L208/L218 (now diagnostic-only — no ripple edits).
- [ ] 2.4 Run `bats tests/multi-peer-race.bats`; confirm **11/11 PASS**. Run `make ci`; confirm exit 0 AND all existing `.bats` still pass (66 + 11 = 77 `@test` total).
- [ ] manual-verification — scenarios `Normal session exit leaves the lockfile on disk`, `Signal-induced EXIT trap does NOT unlink the lockfile`, `Next start after a CLEAN exit reclaims via flock -n`, `Two concurrent starts against the same profile serialize` now PASS (R7 closed: path persists, contender's `flock -n` fails on the SAME inode).
- [ ] manual-verification — scenario `Engine calls setpgid (or setsid) at startup` now PASS (source-grep matches `setpgid 0 0`).
- [ ] manual-verification — scenarios `EXIT trap fires kill on the engine's process group`, `Orphaned xfreerdp3 (simulated via background sleep) is killed when the trap fires`, `Process-group kill does NOT affect processes outside the engine's group` now PASS (group kill reaps simulated xfreerdp3; foreign-group child survives).
- [ ] manual-verification — backstop scenarios `Early-exit before flock does not error`, `Next start after a CRASHED predecessor reclaims via flock -n`, `Single-instance PID-file behavior is unchanged (regression)` still PASS (no regression — R4 closed).

---

## Phase 3: REFACTOR — documentation only

> **Commit**: `refactor(engine): document R7 race rationale + spec amendment pointer`
> **Files**: `engine/rdp-connect` · **Size**: ±0 LOC (comment churn) · **Depends on**: T2

- [ ] 3.1 Replace the Phase-2 placeholder comment at the (now-stub) `true` line in `cleanup()` with the full R7 race explanation block from `design.md` §(c) — cite `instance-locking-delta` "EXIT trap preserves the lockfile path" and note the canonical spec amendment is deferred to `sdd-archive` per `_shared/openspec-convention.md`.
- [ ] 3.2 Add the rationale comment near `setpgid 0 0` (L8) from `design.md` §(a) — PGID == `$$` stability for `echo "$$" >&200` + `kill -- -$$`; `setpgid 0 0` (not `setsid -f`) preserves PID; `|| true` for idempotency.
- [ ] 3.3 Add the rationale comment near `kill -- -$$` in `cleanup()` from `design.md` §(b) — process-group reaper contract: `--` mandatory, `|| true` for no-children case, bash defers signal disposition until the trap returns so `EXIT_CODE` is preserved and the EXIT trap does not re-fire.
- [ ] 3.4 Run `make ci`; confirm still exit 0 with NO behavior change (diff is comment-only — REFACTOR gate per strict-tdd).
- [ ] manual-verification — scenario `Single-instance PID-file behavior is unchanged (regression)` (`@test single_instance_behavior_unchanged_regression`): `make ci` still green after the comment-only commit (REFACTOR gate holds).

---

## Ordering Constraints

**T1 (RED) → T2 (GREEN) → T3 (REFACTOR).** Strict TDD: the RED test file must exist and be confirmed failing (7 RED + 4 GREEN) BEFORE the GREEN engine fix is applied; GREEN must reach 11/11 BEFORE the REFACTOR comment commit. Canonical spec amendment into `openspec/specs/{instance-locking,engine-robustness}/spec.md` is **deferred to `sdd-archive`** per `_shared/openspec-convention.md` — not a task in this change.

## Branch Plan

Single branch **`pr/multi-peer-race`** branched from **`main`** → 3 work-unit commits (RED, GREEN, REFACTOR) → **single PR merges to `main`**. No chained PRs. No `size:exception`. Well under the 400-line review budget.
