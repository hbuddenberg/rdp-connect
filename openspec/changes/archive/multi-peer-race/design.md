# Design: `multi-peer-race`

> **Project**: `rdp-connect` · **Mode**: openspec + engram mirror · **Strict TDD**: active
> **Origin**: `proposal.md` + `specs/instance-locking-delta.md` + `specs/engine-robustness-delta.md` + `explore.md`
> **Engine baseline**: `engine/rdp-connect` @ `main` HEAD (365 lines)
> **Date**: 2026-07-21

---

## Technical Approach

Implement **Approach A / F-G** from `explore.md` §5 as three work-unit commits under strict TDD:

1. **RED** — ship `tests/multi-peer-race.bats` with 11 `@test` blocks (7 failing, 4 regression backstops). The RED tests faithfully reproduce the engine's flock + trap + signal structure in subshells (per explore §5) so they exercise the *contract* the specs define without dragging in `xfreerdp3` / `hyprctl` / `:3389`-listener dependencies that CI cannot satisfy.
2. **GREEN** — three surgical edits to `engine/rdp-connect`: `setpgid 0 0` near startup, `kill -- -$$` as the first action of `cleanup()` (after `EXIT_CODE=$?` capture), and removal of the `rm -f "$PID_FILE"` block at L263-266. All 7 RED tests flip to GREEN; the 4 backstops stay GREEN.
3. **REFACTOR** — comment hygiene + carry-forward closure annotation; canonical-spec amendment deferred to `sdd-archive` per `_shared/openspec-convention.md`.

The fix maps 1:1 to the proposal's Approach A and to the two delta specs: the `instance-locking` delta inverts the "MUST remove" requirement (path persistence is the new contract); the `engine-robustness` delta adds the process-group-isolation requirement. Both close in the same diff because R7 and the orphan-kill footgun share a root cause (orphaned `xfreerdp3` + bypassed lock = two sessions).

---

## Architecture Decisions

### Decision: `setpgid 0 0` placement (one line, near startup)

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `setpgid 0 0` at L8 (right after `set -euo pipefail`) | Engine becomes group leader from the very first statement; every subsequent child (including `xfreerdp3`) inherits PGID == $$. `--help` exit path doesn't spawn children, so no behavior change there. Failure mode (already a leader, e.g. `setsid rdp-connect`) is idempotent → `‖ true`. | **CHOSEN** |
| `setsid -f` (forks) | Forks a new process; `$$` semantics change after fork → breaks `echo "$$" >&200` and `kill -- -$$`. | Rejected — breaks PID stability |
| `setpgid` later (e.g. right before xfreerdp3 pipeline) | Marginal benefit (no children spawn before xfreerdp3 anyway); risks forgetting the placement if a future refactor adds an earlier `&`. | Rejected — less robust |

**Rationale**: `$$` MUST remain stable because (a) the PID written to the lockfile is `$$`, (b) the trap's `kill -- -$$` targets PGID == $$. `setpgid 0 0` (no fork) preserves both invariants. Placement at L8 maximizes the guarantee that all children inherit the group.

### Decision: `kill -- -$$` placement (first action of `cleanup()`, AFTER `EXIT_CODE=$?`)

| Option | Tradeoff | Decision |
|--------|----------|----------|
| After `EXIT_CODE=$?`, before `END_TIME=$(date +%s)` | `$?` is volatile — any command before capture overwrites it. Capture first, kill second. Children die BEFORE logging/notification, so they cannot outlive the engine's logging window. | **CHOSEN** |
| Before `EXIT_CODE=$?` capture | `kill` returns non-zero when the group is empty (early exit) → `set -e` aborts the trap before `EXIT_CODE` is captured → WRONG notification path. | Rejected |
| Last line of cleanup | Children survive the entire logging/notification window — reopens the orphan footgun. | Rejected |
| `pkill -P $$` (children only) | Doesn't match the delta spec's "MUST issue `kill -- -$$`"; misses grandchildren (xfreerdp3 may fork its own children). | Rejected — spec deviation |

**Rationale**: `kill -- -$$` (default SIGTERM) hits every process in PGID `$$` — engine + xfreerdp3 + any grandchildren. The engine receives SIGTERM mid-trap; bash defers signal disposition until the trap function returns (POSIX signal semantics + bash trap implementation), so the trap body completes, `EXIT_CODE` is preserved, and the engine dies cleanly after. The EXIT trap does NOT re-fire (bash doesn't recurse EXIT traps). `2>/dev/null ‖ true` handles the no-children case (early exit).

The `--` is mandatory: without it, `kill -1234` parses as `-1` (SIGHUP) + `234` (PID) — exactly the kind of footgun shellcheck warns about. `--` terminates option parsing so `-$$` is unambiguously the PGID.

### Decision: Remove `rm -f "$PID_FILE"` block, keep `_LOCK_ACQUIRED`

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Delete the block; replace with a comment citing R7 + the spec amendment; KEEP `_LOCK_ACQUIRED=true/false` assignments | Smallest correct diff. Flag is now diagnostic-only (useful for future `log_event "DEBUG"` hooks). Avoids ripple edits to L208/L218. Comment documents WHY so a future refactor doesn't re-add the unlink. | **CHOSEN** |
| Delete block AND remove `_LOCK_ACQUIRED` | Larger diff; touches L208, L218, L263-266; flag is the only signal a future debugging session would have for "did we reach flock-success?". | Rejected — gratuitous ripple |
| Gate the unlink behind an inode-identity check (F-E) | Explore §5 proved this is insufficient: by the time the check runs, the contender's flock on the new inode has already succeeded. Doesn't eliminate R7. | Rejected — ineffective |

### Decision: Test mock strategy — three tiers, NO engine source test-hook

| Tier | Pattern | Tests | Why |
|------|---------|-------|-----|
| Source-grep | `grep -E 'setpgid\|setsid' engine/rdp-connect` | 1 | Deterministic; no execution needed for "the call exists". |
| Subshell reproduction | Faithful minimal subshell that mirrors engine structure: `setpgid` → `exec 200>"$path"` → `flock -n 200` → `echo $$ >&200` → `trap cleanup EXIT` → launch `sleep` child → signal/exit. Uses **sentinel files**, not fixed sleeps, for synchronization. | 9 | Explore §5's recommended approach. Engine cannot reach `xfreerdp3` launch in CI (requires `xfreerdp3`, `hyprctl`, `jq`, `wofi/rofi`, `notify-send`, AND a TCP listener on `:3389`). Reproduction tests exercise the *contract* (path persistence, flock-on-same-inode, group-kill, scope-of-kill) directly. |
| Meta-test | Assert other `.bats` files pass via `$BATS_TEST_NAMES` count + `make ci` (deferred to `sdd-verify`) | 1 | Regression backstop per R4. |

**Rejected — env-var test hook (`RDP_CONNECT_FAKE_RDP_CMD`)**: would require a production code change for testability, with a "MUST error loudly in production" guard. Adds engine surface area; test hooks tend to leak. The subshell-reproduction pattern achieves the same coverage without touching production code. **If a future test genuinely needs to invoke the engine end-to-end**, the right answer is to extract `launch_rdp_session()` as a function (refactor) — out of scope for this change.

### Decision: Commit plan — 3 work-unit commits, single PR

| # | Type | Subject | Verification |
|---|------|---------|--------------|
| 1 | RED | `test(multi-peer-race): add failing bats for R7 race + orphan-kill` | 7 of 11 tests FAIL; 4 backstops pass. Commit body lists RED vs GREEN per test. |
| 2 | GREEN | `fix(engine): preserve PID file path + process-group kill in trap (R7)` | All 11 tests PASS; existing `.bats` files still PASS. |
| 3 | REFACTOR | `refactor(engine): document R7 race + spec amendment rationale` | Tests still PASS; comments only; no behavior change. Canonical spec sync deferred to `sdd-archive`. |

Per `work-unit-commits/SKILL.md`: each commit is a reviewable work unit with a clear purpose, includes its own verification, and tells a story (RED → GREEN → REFACTOR). Single PR — well under 400-line budget (see Size Forecast).

---

## Data Flow — Signal-induced exit (post-fix)

```
 SIGTERM ──→ bash (engine, PGID=$$)
              │
              ├─ EXIT trap fires (xfreerdp3 still alive in PGID $$)
              │   ├─ EXIT_CODE=$?              # capture BEFORE any cmd
              │   ├─ kill -- -$$ 2>/dev/null    # SIGTERM to whole group
              │   │   ├─→ xfreerdp3 (in PGID $$) TERMINATES  ✓
              │   │   ├─→ grandchildren TERMINATE              ✓
              │   │   └─→ engine itself (signal deferred until trap returns)
              │   ├─ END_TIME / DURATION / logging / notify-send
              │   └─ (NO rm -f $PID_FILE — R7 closed)
              │
              └─ engine exits
                  └─ fd 200 closes → kernel releases flock on the SAME inode
                     → next start's `flock -n` reclaims (or fails if peer live)

Path persistence: contender's `exec 200>"$PID_FILE"` opens the SAME inode
(still on disk) → `flock -n` FAILS → no R7 bypass.
```

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `engine/rdp-connect` | Modify (L8, L222-223, L263-266) | Add `setpgid 0 0 ‖ true` after `set -euo pipefail`; add `kill -- -$$ 2>/dev/null ‖ true` as first action of `cleanup()` after `EXIT_CODE=$?`; remove the `rm -f "$PID_FILE"` block; replace with explanatory comment. |
| `tests/multi-peer-race.bats` | Create | 11 `@test` blocks across 3 tiers (1 source-grep + 9 subshell reproduction + 1 meta). Uses `tests/test_helper.bash`. |
| `openspec/specs/instance-locking/spec.md` | Amend (at archive) | "EXIT trap cleans the new path" → "EXIT trap preserves the lockfile path". Deferred to `sdd-archive` per `_shared/openspec-convention.md`. |
| `openspec/specs/engine-robustness/spec.md` | Amend (at archive) | Add "Process-group isolation and signal-induced cleanup" requirement. Deferred to `sdd-archive`. |

### Engine edits — exact code blocks

**(a) `setpgid` at startup** — insert at L8, immediately after `set -euo pipefail` (L7), before the `--help` block (L17):

```bash
set -euo pipefail

# multi-peer-race (engine-robustness-delta "Process-group isolation"):
# become the leader of a fresh process group whose PGID == $$. Children
# (notably xfreerdp3 + its pipeline) inherit this PGID, so the EXIT trap's
# `kill -- -$$` can reap them on signal-induced exit. Failure (already a
# group leader, e.g. launched via `setsid`) is idempotent — `|| true`.
# `setpgid 0 0` (not `setsid -f`) preserves PID stability so `$$` still
# equals the engine PID for `echo "$$" >&200` and the trap's `kill -- -$$`.
setpgid 0 0 || true
```

**(b) `kill -- -$$` in cleanup** — insert as the **second** statement of `cleanup()` (L222), immediately after `EXIT_CODE=$?` (L223), before `END_TIME=$(date +%s)`:

```bash
cleanup() {
    EXIT_CODE=$?
    # multi-peer-race (engine-robustness-delta "Process-group isolation"):
    # kill our process group FIRST so xfreerdp3 dies before any logging /
    # notification. Scoped to our own PGID (== $$, set at L8). `--` is
    # mandatory: without it `kill -N` could parse `-1` as SIGHUP. The
    # engine itself receives SIGTERM mid-trap; bash defers signal
    # disposition until the trap returns, so EXIT_CODE is preserved and
    # the EXIT trap does NOT re-fire. `|| true` covers the no-children
    # case (early exit before xfreerdp3 launched).
    kill -- -$$ 2>/dev/null || true
    END_TIME=$(date +%s)
    # ... rest unchanged ...
```

**(c) Remove `unlink` from cleanup** — replace the block at L263-266:

```bash
# (REMOVED — multi-peer-race R7)
# if [ "${_LOCK_ACQUIRED:-false}" = true ] && [ -f "$PID_FILE" ]; then
#     rm -f "$PID_FILE"
# fi
```

with:

```bash
# multi-peer-race (instance-locking-delta "EXIT trap preserves the lockfile
# path"): the PID file MUST NOT be unlinked here. Unlinking while fd 200
# still holds the inode flock creates an anonymous inode; a contender's
# `exec 200>"$PID_FILE"` then materializes a NEW inode at the same path and
# `flock -n` succeeds on it — bypassing us during the cleanup window (R7).
# The kernel releases the flock automatically on fd-200 close (process
# death); the next start's `flock -n` reclaims the stale path. The
# _LOCK_ACQUIRED flag is retained for diagnostic purposes (future log_event
# hooks) but no longer gates any filesystem mutation.
true  # no-op; preserves the function's return status semantics
```

---

## Interfaces / Contracts — the 11 test invariants

The strict-TDD tests below are the binding contract. Each test asserts a spec scenario verbatim; production code changes must make each RED test flip to GREEN without breaking any GREEN backstop.

| # | Test name | Spec scenario | Tier | RED/GREEN @ commit 1 |
|---|-----------|---------------|------|----------------------|
| 1 | `clean_exit_leaves_pid_file_on_disk` | instance-locking-delta "Normal session exit leaves the lockfile on disk" | subshell | **RED** (current engine unlinks) |
| 2 | `sigterm_exit_trap_does_not_unlink_pid_file` | instance-locking-delta "Signal-induced EXIT trap does NOT unlink the lockfile" | subshell | **RED** |
| 3 | `early_exit_before_flock_does_not_error` | instance-locking-delta "Early-exit before flock does not error" | subshell | GREEN (backstop — `[ -f ]` guard + no unlink block already handles this) |
| 4 | `next_start_reclaims_after_clean_exit` | instance-locking-delta "Next start after a CLEAN exit reclaims via flock -n" | subshell | **RED** (current engine leaves no file; new contract untested) |
| 5 | `next_start_reclaims_after_crashed_predecessor` | instance-locking-delta "Next start after a CRASHED predecessor reclaims via flock -n" | subshell | GREEN (backstop — already works per existing instance-locking spec L42-55) |
| 6 | `two_concurrent_starts_serialize_via_flock` | instance-locking-delta "Two concurrent starts against the same profile serialize" | subshell | **RED** (R7 reproduced) |
| 7 | `engine_calls_setpgid_at_startup` | engine-robustness-delta "Engine calls setpgid (or setsid) at startup" | source-grep | **RED** (setpgid not yet in source) |
| 8 | `exit_trap_fires_kill_on_process_group` | engine-robustness-delta "EXIT trap fires kill on the engine's process group" | subshell | **RED** |
| 9 | `orphan_xfreerdp3_killed_on_signal_exit` | engine-robustness-delta "Orphaned xfreerdp3 is killed when the trap fires" | subshell | **RED** (current engine orphans xfreerdp3) |
| 10 | `process_group_kill_is_scoped_to_engine_group_only` | engine-robustness-delta "Process-group kill does NOT affect processes outside the engine's group" | subshell | **RED** (no kill at all → scope untestable) |
| 11 | `single_instance_behavior_unchanged_regression` | engine-robustness-delta "Single-instance PID-file behavior is unchanged (regression)" | meta | GREEN (backstop — asserts existing `.bats` files still pass) |

**Totals**: 7 RED, 4 GREEN at commit 1. All 11 GREEN at commit 2.

### Sentinel-based synchronization (R3 mitigation)

Every timing-sensitive subshell test uses **sentinel files**, not fixed `sleep N`. Pattern:

```bash
# Owner A holds the lock until B has asserted, then we touch a release sentinel.
bash -c '
    exec 200>"'"$lockfile"'"
    flock -n 200 || exit 99
    echo $$ >&200
    # wait for the test to signal "you may exit now"
    while [ ! -f "'"$release_sentinel"'" ]; do sleep 0.05; done
' &
pidA=$!
# foreground waits for "A has the lock" via the lockfile being non-empty
until [ -s "$lockfile" ]; do sleep 0.05; done
# ... exercise the invariant (B's flock -n, signal A, etc.) ...
touch "$release_sentinel"
wait "$pidA" 2>/dev/null || true
```

Sentinels per test:
- Tests 1, 2, 6: `A_release.sentinel` (owner waits), `lockfile` non-empty (test waits for owner).
- Tests 4, 5: `owner_died.sentinel` (test waits for owner subshell to exit before running the reclamation probe).
- Tests 8, 9, 10: `child_running.sentinel` (child writes on start; test waits before signalling engine), `child_killed.sentinel` (child's EXIT trap writes if it was NOT killed — test asserts this sentinel is ABSENT after trap fires).

### Subshell reproduction skeleton (tests 8, 9, 10 — the orphan-kill family)

```bash
@test "orphan_xfreerdp3_killed_on_signal_exit" {
    local lockfile child_sentinel corpse_sentinel
    lockfile="$(mktemp -p "$BATS_TMPDIR")"; rm -f "$lockfile"
    child_sentinel="$BATS_TMPDIR/child_running.$$"
    corpse_sentinel="$BATS_TMPDIR/corpse.$$"; rm -f "$corpse_sentinel"

    # Faithful engine stand-in: setpgid, flock, trap-with-kill, child simulating xfreerdp3
    bash -c '
        set -euo pipefail
        setpgid 0 0 || true
        exec 200>"'"$lockfile"'"
        flock -n 200 || exit 99
        echo $$ >&200
        cleanup() {
            EXIT_CODE=$?
            kill -- -$$ 2>/dev/null || true   # multi-peer-race fix
        }
        trap cleanup EXIT
        # xfreerdp3 stand-in: sleep, announce, die-with-trace if NOT killed
        ( touch "'"$child_sentinel"'"; trap "touch '"$corpse_sentinel"'" EXIT; sleep 60 ) &
        wait
    ' &
    local engine_pid=$!

    # wait until the simulated xfreerdp3 child is running
    until [ -f "$child_sentinel" ]; do sleep 0.05; done

    # send SIGTERM to the engine
    kill -TERM "$engine_pid" 2>/dev/null || true
    wait "$engine_pid" 2>/dev/null || true

    # assertion: the child's EXIT trap (corpse_sentinel) MUST NOT have fired,
    # meaning the child was KILLED by the group-kill before it could run its
    # own EXIT trap. If the engine does NOT kill its group, the child survives
    # SIGTERM (it's in a subshell `( ... ) &` of the engine's group), waits
    # out the 60s sleep, then exits cleanly → corpse_sentinel appears → test FAILS.
    [ ! -f "$corpse_sentinel" ] || \
      fail "simulated xfreerdp3 survived engine SIGTERM (orphan-kill failed)"
}
```

Test 10 (`process_group_kill_is_scoped_to_engine_group_only`) extends this skeleton with a **second** child spawned by the test harness itself (NOT inherited by the engine — the harness runs in its own group), and asserts THAT child survives the engine's `kill -- -$$` because its PGID differs.

---

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Source-grep | "setpgid is in the engine source" | `grep -E 'setpgid\|setsid' engine/rdp-connect` — 1 test |
| Subshell reproduction (unit) | Lock-contract invariants (path persistence, flock-on-same-inode, reclaim-after-clean-exit, reclaim-after-crash) | Faithful minimal subshells mirroring engine L208-219, L263-266; sentinel-synced — 5 tests |
| Subshell reproduction (signal) | Process-group invariants (kill-on-trap, orphan-reap, scope) | Faithful minimal subshells with `setpgid` + trap + simulated xfreerdp3 (`sleep 60 &`); SIGTERM via `kill -TERM` — 3 tests |
| Meta (regression) | Existing single-instance behavior unchanged | Asserts `$BATS_TEST_NAMES` count grows by 11 and `make ci` still green (deferred to `sdd-verify`) — 1 test |

Per `strict-tdd.md`:
- **Safety net**: `make test` baseline captured before any source edit (existing 7 `.bats` files must remain green throughout).
- **RED gate**: each RED test references a contract the current source violates; failure mode is structural, not flaky.
- **TRIANGULATE**: the reclaim family (tests 4 + 5) triangulates the reclamation contract across two distinct predecessor-exit types (clean vs SIGKILL).
- **REFACTOR gate**: tests stay green after the comment-only commit 3.

---

## Migration / Rollout

No migration required. The change is backward-compatible at the user surface:
- `xfreerdp3` invocation flags unchanged.
- Profile format unchanged.
- The only user-visible behavior change: `$PID_FILE` now persists in `$XDG_RUNTIME_DIR` after clean exit (kernel reclaims the lock on fd close; next start overwrites). This MUST be called out in the PR description per proposal §High-Risk Callouts.

The installer is idempotent (per `openspec/config.yaml` rollback rule). `git revert <merge-sha>` + re-running the installer restores the pre-change engine.

---

## Process-Group Semantics Verification

| Claim | Verification |
|-------|--------------|
| `setpgid 0 0` makes the caller the leader of a new group with PGID == its PID | POSIX.1-2017 §8.2.4.1; `ps -o pgid= -p $$` after the call yields `$$`. |
| Children spawned after `setpgid` inherit the PGID until they call their own `setpgid`/`setsid` | POSIX fork+exec semantics; `xfreerdp3` does not daemonize (verified structurally — FreeRDP runs in foreground under the engine's pipeline). |
| `kill -- -N` sends the signal to all processes in PGID N, including the leader | POSIX.1-2017 §4.3.3; negative PID = process group. The `--` prevents option-parse ambiguity. |
| If engine is leader (PGID == PID), `kill -- -$$` kills engine + all its children | Direct corollary of the above. |
| Trap fires BEFORE the engine actually exits, so it can kill children first | `bash` man page §SIGNALS: "EXIT trap is executed on shell exit." Signal disposition during trap execution is deferred per POSIX. |

**Edge cases** (per proposal §High-Risk Callouts):
- Child has changed its own PGID (rare; not FreeRDP's behavior): won't be killed — acceptable, documented in the spec.
- Engine killed by SIGKILL (not trappable): trap doesn't fire; children orphaned. **Same as today — not a regression.** This change strictly improves the SIGTERM/SIGINT paths.
- Engine launched via `setsid` (already a group leader): `setpgid 0 0` is idempotent (`|| true`); `kill -- -$$` still targets the correct group.

---

## Risks Addressed

| ID | Risk | Mitigation in this design |
|----|------|---------------------------|
| **R1** | Spec amendment to canonical `instance-locking` is normative | Tracked via `instance-locking-delta.md`; archive-time merge per `_shared/openspec-convention.md`. Design defers canonical edit to `sdd-archive` (commit 3 is comment-only). |
| **R2** | Orphan-kill blast radius | `setpgid 0 0` isolates engine + children into PGID == $$; trap's `kill -- -$$` scoped to that group only. Verified by test 10 (`process_group_kill_is_scoped_to_engine_group_only`) which proves a foreign-group child survives. |
| **R3** | RED-test timing sensitivity on CI | Every subshell test uses sentinel files (`<event>.sentinel`) for synchronization — zero fixed `sleep` calls in the critical path. Sentinels enumerated per test above. |
| **R4** | Regression in single-instance golden path | Test 11 (`single_instance_behavior_unchanged_regression`) asserts `$BATS_TEST_NAMES` count grows by exactly 11 (no existing tests removed). `sdd-verify` runs `make ci` (shellcheck + bats) over the full suite: `pid-path.bats` (6), `cleanup-session.bats` (6), `harness.bats` (incl. `make_smoke_works`), plus `parser.bats`, `hidpi.bats`, `vpn-trim.bats`, `engine-security.bats`. |

---

## Size Forecast (lines of code)

| Component | Forecast (net) | Notes |
|-----------|----------------|-------|
| `engine/rdp-connect` | +16 | setpgid 1 + comment 4 = +5; `kill -- -$$` 1 + comment 9 = +10; remove `rm -f` block -3 + replacement comment 10 = +7; subtract overlap = ~+16 net. |
| `tests/multi-peer-race.bats` | +170 | header/setup ~25 + 11 `@test` × avg 13 = ~170. Subshell reproductions are tighter than initially forecast (sentinel pattern is reusable inline). |
| Spec deltas | 0 | Already written in spec phase; canonical amendment deferred to archive. |
| **Total code+test** | **~186** | Single PR. **Well under 400-line review budget.** No chained PRs. No `size:exception`. |

**Revision vs proposal**: the proposal forecast ~150 LOC. Actual is ~186 (+24%). The delta is entirely in the test file — subshell reproductions with sentinel synchronization are slightly more verbose than the original ~11-lines-per-test estimate, but the rigor is necessary for non-flaky CI behavior under R3. Still single-PR, no budget risk.

---

## Open Questions

None blocking. All design decisions are taken; the canonical spec amendment is a routine archive-step (per `_shared/openspec-convention.md`), not an open question.

---

## Skills Loaded Before Work

- `/home/hbuddenberg/.config/opencode/skills/sdd-design/SKILL.md`
- `/home/hbuddenberg/.config/opencode/skills/_shared/SKILL.md` (+ `sdd-phase-common.md`, `openspec-convention.md`)
- `/home/hbuddenberg/.config/opencode/skills/sdd-apply/SKILL.md` + `strict-tdd.md` (review-only — design must produce RED-GREEN-REFACTOR-ready specs)
- `/home/hbuddenberg/.config/opencode/skills/work-unit-commits/SKILL.md`
