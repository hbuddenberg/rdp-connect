# Archive Report: `multi-peer-race`

**Change**: `multi-peer-race`
**Project**: `rdp-connect`
**Mode**: `openspec` + engram mirror
**Delivery**: single-PR (#6 merged to `main` at `0d6a790`) · 199 changed lines · 49.75% of 400-line budget
**Verify verdict**: PASS WITH WARNINGS (engine correct; 3 spec scenarios S6/S9/S10 lack direct behavioral coverage — follow-up tracked)
**Archive date**: 2026-07-21
**Executor**: `sdd-archive` (paths-injected)

---

## Executive Summary

Synced both delta specs from `multi-peer-race` into the canonical source of truth under `openspec/specs/`, moved the change folder into the audit-trail archive, updated `README.md` to document the R7 fix and the orphan-kill reap, and committed the lot as a single docs commit on `main`. The SDD cycle for `multi-peer-race` is complete: explore → propose → spec → design → tasks → apply (RED/GREEN, 2 commits) → verify (PASS WITH WARNINGS) → **archive** (this report).

Two canonical capabilities were MODIFIED:
- `instance-locking` — the load-bearing "EXIT trap MUST remove the lockfile" requirement was **inverted** to "EXIT trap MUST NOT unlink while fd 200 may still hold the inode lock" (R7 closure), plus a new "Path-persistence reclamation by next start" requirement naming the kernel-fd-close contract the new behavior relies on.
- `engine-robustness` — a new "Process-group isolation and signal-induced cleanup" requirement was appended (engine `setpgid 0 0` at startup; trap `kill -- -$$` before logging; scoped to own group only).

Both amendments pair (per the deltas' framing): together they guarantee that a signal-induced exit reaps the `xfreerdp3` child AND preserves the lockfile path so a contender cannot bypass the lock during cleanup — closing both R7 and the orphan-kill footgun in one diff.

## Specs Synced

| Domain | Action | Details |
|--------|--------|---------|
| `instance-locking` | **MODIFIED** (1 requirement inverted) + **ADDED** (1 requirement) | "EXIT trap cleans the new path" → "EXIT trap preserves the lockfile path" (normative inversion — `MUST remove` → `MUST NOT unlink`); added "Path-persistence reclamation by next start". Scenarios: 2 → 6 (3 under MODIFIED, 3 under ADDED). Banner at top of spec updated to reflect the new pairing with engine-robustness process-group isolation. |
| `engine-robustness` | **ADDED** (1 requirement) | "Process-group isolation and signal-induced cleanup" (4 sub-clauses, 5 scenarios) appended at the end. No existing requirement text changed. |

### Requirements-level change ledger

**`instance-locking` (MODIFIED requirement — `MUST` inverted):**

| Before (canonical pre-archive) | After (canonical post-archive) |
|--------------------------------|--------------------------------|
| "The engine's EXIT trap **MUST remove** the lockfile at the NEW uid-private path on every exit (success, error, signal)." | "The engine's EXIT trap **MUST NOT** `rm -f` (or otherwise unlink) the lockfile at the NEW uid-private path on any exit path — success, error, or signal-induced." |

Rationale (R7): unlinking the path while fd 200 still holds the inode flock creates an anonymous inode; a contender's `exec 200>"$PID_FILE"` materializes a NEW inode at the same path and `flock -n` succeeds on it — bypassing the first owner during the cleanup window. The kernel releases the flock on fd-200 close automatically; path persistence is therefore benign, and the next start's `flock -n` reclaims the stale path.

**`instance-locking` (ADDED requirement):**
- "Path-persistence reclamation by next start" — extends the existing "Stale lockfile reclamation" requirement by making the reclamation contract EXPLICIT for the post-fix world where EVERY clean exit also leaves a lockfile on disk. Single kernel guarantee: a dead process holds no flock, regardless of whether its lockfile path was removed.

**`engine-robustness` (ADDED requirement):**
- "Process-group isolation and signal-induced cleanup" — engine MUST `setpgid` (or `setsid`) at startup; trap MUST `kill -- -$$`; kill MUST be scoped to the engine's OWN group only (negative PID/PGID, never positive PID alone, never broader scope).

## Scenarios Amended

| Spec | Requirement | Scenario | Status |
|------|-------------|----------|--------|
| `instance-locking` | EXIT trap preserves the lockfile path | Normal session exit leaves the lockfile on disk | MODIFIED (was "cleans up") |
| `instance-locking` | (same) | Signal-induced EXIT trap does NOT unlink the lockfile | MODIFIED (was implicit) |
| `instance-locking` | (same) | Early-exit before flock does not error | KEPT (text tightened to reference the new no-unlink contract) |
| `instance-locking` | Path-persistence reclamation by next start | Next start after a CLEAN exit reclaims via flock -n | ADDED |
| `instance-locking` | (same) | Next start after a CRASHED predecessor reclaims via flock -n | ADDED |
| `instance-locking` | (same) | Two concurrent starts against the same profile serialize | ADDED |
| `engine-robustness` | Process-group isolation and signal-induced cleanup | Engine calls setpgid (or setsid) at startup | ADDED |
| `engine-robustness` | (same) | EXIT trap fires kill on the engine's process group | ADDED |
| `engine-robustness` | (same) | Orphaned xfreerdp3 (simulated via background sleep) is killed when the trap fires | ADDED |
| `engine-robustness` | (same) | Process-group kill does NOT affect processes outside the engine's group | ADDED |
| `engine-robustness` | (same) | Single-instance PID-file behavior is unchanged (regression) | ADDED |

**Total: 6 scenarios added to `instance-locking`, 5 scenarios added to `engine-robustness`. The 2 pre-existing `instance-locking` "EXIT trap" scenarios were absorbed into the inverted requirement (3 scenarios) — net +3 on that requirement.**

## Archive Contents

- `proposal.md` ✅
- `specs/instance-locking-delta.md` ✅
- `specs/engine-robustness-delta.md` ✅
- `design.md` ✅
- `tasks.md` ✅ (3/3 phases complete; T3 REFACTOR folded into T2 GREEN per orchestrator instruction)
- `verify-report.md` ✅ (PASS WITH WARNINGS — 5/11 COMPLIANT, 3/11 PARTIAL, 3/11 UNTESTED, 0 FAILING)
- `explore.md` ✅
- `archive-report.md` ✅ (this file)

## Source of Truth Updated

The following canonical specs now reflect the post-`multi-peer-race` behavior:
- `openspec/specs/instance-locking/spec.md` — banner + 1 inverted requirement + 1 added requirement
- `openspec/specs/engine-robustness/spec.md` — 1 added requirement

## Commits Made

| SHA | Subject |
|-----|---------|
| (this archive commit) | `docs(sdd): archive multi-peer-race — sync delta specs to canonical, document R7 fix` |

Single commit on `main`. Includes:
- Canonical spec amendments (`openspec/specs/instance-locking/spec.md`, `openspec/specs/engine-robustness/spec.md`)
- Change folder move (`openspec/changes/multi-peer-race/` → `openspec/changes/archive/multi-peer-race/`)
- `README.md` updates (capabilities matrix, PID lockfile note, Recent changes section, test-count badge 66 → 74)
- This archive report (`openspec/changes/archive/multi-peer-race/archive-report.md`)

## Carry-Forward Resolution

| Carry-forward | Status | Evidence |
|---------------|--------|----------|
| Original T1.4 race (`baseline-hardening`) | ✅ RESOLVED (superseded) | Pre-fix: trap unlinked `$PID_FILE` only if `_LOCK_ACQUIRED=true`. Post-fix: unlink removed entirely; `_LOCK_ACQUIRED` retained as diagnostic-only. The original race is moot because **no exit path** can unlink. |
| R7 (`multi-peer-race` explore finding) | ✅ RESOLVED | Root cause: unlinking path while fd 200 holds inode flock → anonymous inode → contender's `exec 200>"$PID_FILE"` materializes new inode → fresh flock succeeds → two concurrent xfreerdp3 sessions. Fix: never unlink. Canonical `instance-locking` spec now mandates the no-unlink contract. |
| Orphan-kill footgun (bonus) | ✅ RESOLVED | Pre-fix: `pkill rdp-connect` orphaned `xfreerdp3` to PID 1. Post-fix: `setpgid 0 0` makes engine its own group leader; trap's `kill -- -$$` reaps the whole group before logging/notification. Canonical `engine-robustness` spec now mandates the process-group isolation contract. |

## Known Gaps (deferred to follow-up — NOT blocking archive)

Per the verify report:
1. **3 spec scenarios UNTESTED at named-`@test` level** — S6 (`two_concurrent_starts_serialize_via_flock`), S9 (`orphan_xfreerdp3_killed_on_signal_exit`), S10 (`process_group_kill_is_scoped_to_engine_group_only`). The design's sentinel-synced subshell reproductions were traded for pattern-contract backstops due to CI environment constraints (cannot host `xfreerdp3` + `hyprctl` + `notify-send` + `jq` + `wofi/rofi` + `:3389` TCP listener). Mitigated by POSIX guarantees + source-grep presence proofs.
2. **3 spec scenarios PARTIAL** — S2 (signal-induced trap), S3 (early-exit-before-flock), S8 (trap fires kill on group) have only source-grep coverage (static presence), not behavioral coverage.
3. **Assertion quality weakness** — `setpgid_makes_engine_process_group_leader_pattern` (test 6) asserts only sentinel presence; the header claims "Verified via ps" but no `ps` invocation is present.

**Recommended follow-up**: open an issue titled "Add sentinel-synced subshell reproductions for S6/S9/S10 + strengthen test 6 (multi-peer-race follow-up)".

## SDD Cycle Complete

The change has been fully planned, implemented, verified, and archived.

**Next recommended action**: tag release `v0.3.0` (the user-visible behavior changes — persistent `$PID_FILE`, `pkill rdp-connect` reaps `xfreerdp3` — warrant a minor bump from `v0.2.0`).
