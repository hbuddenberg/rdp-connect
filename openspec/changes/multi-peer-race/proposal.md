# Proposal: `multi-peer-race`

> **Project**: `rdp-connect` · **Branch**: `main` (v0.2.0, `strict_tdd: true`)
> **Origin artifact**: `openspec/changes/multi-peer-race/explore.md` (Engram `sdd/multi-peer-race/explore`)
> **Carry-forward**: `openspec/changes/archive/baseline-hardening/apply-progress.md` §T1.4 (race description) + §T2.2 (`_LOCK_ACQUIRED`)
> **Date**: 2026-07-21

---

## Intent

Close the T1.4 carry-forward from `baseline-hardening` as **resolved-as-described** (the original peer-branch-triggers-cleanup race is closed by trap-after-flock ordering), AND fix the **different real race R7** that exploration uncovered and empirically reproduced (signal-induced EXIT trap unlinks `$PID_FILE` while fd 200 still holds the inode flock, letting a third instance `exec 200>` a fresh inode and bypass the first), AND bundle the **orphan-kill footgun** (`pkill rdp-connect` today leaves xfreerdp3 alive) — all under strict TDD (red-green-refactor).

## Scope

### In Scope
- **R7 fix**: engine no longer unlinks `$PID_FILE` in the EXIT trap ( Approach A / F-G from explore). Stale lockfiles are reclaimed by the next start's `flock -n` (kernel releases the lock on process death).
- **Orphan-kill fix**: engine calls `setpgid` (or `setsid`) at startup so the EXIT trap can `kill -- -$PGID` and reap the xfreerdp3 child on signal-induced exit.
- **Spec amendment** to canonical `instance-locking` (delta): the "EXIT trap MUST remove the lockfile" requirement (current `spec.md:63-68`) is amended to "EXIT trap MUST NOT remove the lockfile path while fd 200 may still hold the inode lock".
- **Spec amendment** to canonical `engine-robustness` (delta): adds requirements for `setpgid` at startup and process-group kill on trap fire.
- **Strict-TDD tests** in NEW `tests/multi-peer-race.bats`: RED→GREEN for R7 (flock-on-path-unlinked-while-fd-held invariant), trap-ordering regression, orphan-kill-on-SIGTERM.
- **Carry-forward closure documentation**: explicit "resolved-as-described" note pointing at this change (no code change for T1.4 itself).

### Out of Scope
- **T1.4 carry-forward code change** — already fixed in current engine; only documentation closure here.
- **Hyprland window-kill** (different bug class — window dies but bash receives no signal; bash waits on pipeline forever) — separate change.
- **R2** (peer `exec 200>` truncates owner's PID — cosmetic `pid=?` log) — noted as known, not worth fixing standalone.
- **R8** (microsecond signal window between flock and trap registration) — negligible.
- **Performance work**, mocking `xfreerdp3` itself (tests simulate it with `sleep`).

## Capabilities

> Contract for `sdd-spec`. Two MODIFIED capabilities — both go through the delta flow.

### New Capabilities
- None.

### Modified Capabilities
- **`instance-locking`** — amend the "EXIT trap cleans the new path" requirement (`spec.md:63-68`): "MUST remove the lockfile" → "MUST NOT remove the lockfile path while fd 200 may still hold the inode lock". Add a scenario asserting the path persists after a clean exit and is reclaimed by the next start's flock.
- **`engine-robustness`** — add a new requirement "Process-group isolation and signal-induced cleanup": engine MUST call `setpgid` (or `setsid`) at startup; the EXIT trap MUST `kill -- -$PGID` to reap the xfreerdp3 child on signal-induced exit; the kill MUST be scoped to the engine's own process group (no collateral damage).

## Approach

**Approach A (F-G from explore — RECOMMENDED)**: don't unlink in cleanup + `setpgid` at startup + `kill -- -$PGID` in trap + spec amendment. Eliminates R7 AND the orphan-kill footgun in one diff. Marginal cost over B is the `setpgid` + trap kill (~8 LOC) — well worth the orphan-kill fix on its own.

**Approach B (F-C fallback)**: don't unlink in cleanup, NO process-group kill. Smallest diff (~3 LOC + tests). Closes R7 but leaves the orphan-xfreerdp3 footgun open. Use only if A's `setpgid`/kill introduces instability (e.g. CI signal-handling regression).

**Approach C (F-D — REJECTED)**: re-verify flock ownership in the trap (`flock -n 200` again). The explore §5 proves this is misconceived: `flock -n` on an fd we already hold is idempotent — always succeeds, never detects "we lost the lock". Documented only to record why it's not viable.

**Recommendation: A.** R7 and the orphan-kill footgun share a root cause (orphaned xfreerdp3 + bypassed lock = two sessions). Fixing both together costs little and avoids a second change in two weeks.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `engine/rdp-connect` (L198-219 flock block, L222-268 trap, L336-364 xfreerdp3 pipeline) | Modified | Remove `rm -f "$PID_FILE"` (L264-266); add `setpgid $$` near startup; add `kill -- -$PGID` to trap |
| `openspec/specs/instance-locking/spec.md` (L63-68) | Delta (normative) | "MUST remove" → "MUST NOT unlink while fd may hold lock" |
| `openspec/specs/engine-robustness/spec.md` | Delta (additive) | New requirement: process-group isolation + trap-kill |
| `tests/multi-peer-race.bats` | New | RED-GREEN-REFACTOR coverage for R7 + orphan-kill |

## Risks

| ID | Risk | Likelihood | Mitigation |
|----|------|-----------|------------|
| **R1** | Spec amendment is a normative change to canonical `instance-locking` | Med | Tracked via delta in this change; archive syncs to canonical at end. Goes through full SDD review. |
| **R2** | Orphan-kill blast radius — `kill -- -$PGID` could hit unrelated processes | Med | Engine MUST `setpgid` at startup to isolate its own group; trap kills ONLY that group. Contract documented in spec + tested. |
| **R3** | RED-test timing sensitivity on CI | Med | Use sentinel files / `flock -u`-on-demand, NOT fixed sleeps. Test asserts the INVARIANT (flock on path-unlinked-but-fd-held inode), not a timing window. |
| **R4** | Regression in the single-instance golden path | Low | Existing `tests/pid-path.bats`, `tests/cleanup-session.bats`, `tests/harness.bats` MUST still pass. Verify gate in `sdd-verify`. |
| **R5** | Stale carry-forward text in `baseline-hardening` archive | Low | Add "resolved-as-described" closure note here. Archive is immutable audit trail — we annotate, don't rewrite. |

## High-Risk Callouts

> Per `openspec/config.yaml` rule: "State blast radius: the deployed script runs as the user and handles real RDP credentials."

1. **Cleanup behavior changes visibly**: `$PID_FILE` now persists in `$XDG_RUNTIME_DIR` after clean exit. Users who `ls` the runtime dir will see stale `.pid` files. Acceptable (kernel reclaims the lock; next start overwrites) but must be documented in the spec delta and called out in the PR description.
2. **Spec amendment to a canonical, security-adjacent spec**: `instance-locking` gates the RDP credential session. The "MUST remove" requirement is currently load-bearing in the spec narrative (pairs with `engine-robustness` cleanup guard). The amendment MUST keep the pairing coherent — the cleanup guard still tolerates missing files; the lockfile just stops being removed by the trap.
3. **`setpgid` at engine startup affects signal handling for child processes**: signals sent to the engine's PID no longer propagate to the child by default; the trap's `kill -- -$PGID` becomes the explicit reaper. If the trap fails to fire (e.g. `SIGKILL`), the orphan persists — acceptable (the same is true today; this change strictly improves on the status quo).

## Delivery Strategy

- **Single PR.** Forecast ~150 LOC (engine ~+20, tests ~+80, spec deltas ~+50). Well under the **400-line** review budget (`openspec/config.yaml: review_budget_lines: 400`). **No chained PRs.** No `size:exception`.

## Rollback Plan

- `git revert <merge-sha>` restores the pre-change engine: `rm -f "$PID_FILE"` returns to the trap (R7 race reappears) and `setpgid`/`kill -- -$PGID` are removed (orphan-kill footgun returns). The installer is idempotent — re-running it redeploys the reverted engine. Spec deltas are reverted from `openspec/specs/` at archive-unmerge. **Acceptable rollback**: the reverted state is the current public v0.2.0 behavior, which is the status quo ante.

## Dependencies

- `xfreerdp3`, `flock` (util-linux), `bash` 5.3 — all already declared in `openspec/config.yaml`.
- `bats-core` 1.5.0+ for the new test file (already enforced by `tests/test_helper.bash`).
- No new runtime deps. No new dev deps.

## Success Criteria

- [ ] `tests/multi-peer-race.bats` exists with RED→GREEN→REFACTOR history (RED commit shows the failing assertion; GREEN commit shows it passing after the engine fix).
- [ ] R7 is empirically closed: a third process cannot acquire a fresh lock during the owner's cleanup window (bats assertion).
- [ ] Orphan-kill is empirically closed: SIGTERM to the engine reaps the xfreerdp3 child (simulated as `sleep`); no `sleep` survives the trap.
- [ ] All existing tests pass (`make ci` = shellcheck + bats) — no regression in single-instance / cleanup / parser / hidpi / vpn-trim paths.
- [ ] `instance-locking` and `engine-robustness` canonical specs amended via deltas (normative change tracked).
- [ ] Carry-forward T1.4 race text in `baseline-hardening` archive annotated as "resolved-as-described — see `multi-peer-race` proposal".
- [ ] Single PR, under 400-line budget.

---

## Skills Loaded Before Work
- `/home/hbuddenberg/.config/opencode/skills/sdd-propose/SKILL.md`
- `/home/hbuddenberg/.config/opencode/skills/_shared/SKILL.md` (+ `_shared/sdd-phase-common.md`, `openspec-convention.md`)
- `sdd-explore` artifact at `sdd/multi-peer-race/explore` (Engram) and `openspec/changes/multi-peer-race/explore.md` (read in full)
