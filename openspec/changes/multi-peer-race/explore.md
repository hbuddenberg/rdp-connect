# Exploration — `multi-peer-race`

> **Project**: `rdp-connect`
> **Branch**: `main` (v0.2.0 tagged, public, `strict_tdd: true` active)
> **Mode**: openspec (artifact_store) + engram mirror (`sdd/multi-peer-race/explore`)
> **Carry-forward origin**: `openspec/changes/archive/baseline-hardening/apply-progress.md` (T1.4 discovery)
> **Engine baseline**: `engine/rdp-connect` @ `main` HEAD (365 lines)
> **Date**: 2026-07-21

---

## Current State Verdict

**`partial`** — The original T1.4 carry-forward (peer-branch triggers cleanup, unlinking the first
instance's PID file) is **RESOLVED** in the current engine. A **different, real race (R7)** remains in
the owner-side cleanup path, was empirically reproduced on the actual code structure, and is exploitable
on signal-induced exit. The carry-forward log is **stale about which race** — it should be closed as
"resolved as described" and replaced with an R7-focused change.

---

## Executive Summary

The T1.4 discovery text describes a peer-branch-triggers-`rm -f` race. That specific race is closed:
the trap is registered after the flock block (L268 > L210-216), so the peer's `exit 0` (L216) fires
before any EXIT trap exists, and `_LOCK_ACQUIRED` (L208/L218/L264) belt-and-suspenders the invariant
against future refactors. **All five claims (a)-(e) in the launch prompt are TRUE in the current code.**

However, the launch prompt's **R7 hypothesis is correct**: the owner's own cleanup `rm -f "$PID_FILE"`
(L264-265) opens a window between path-unlink and fd-200-close where a third instance can `exec 200>`
against a **freshly-created inode** at the same path and acquire a brand-new lock, bypassing the first
instance entirely. This was **empirically reproduced** (see Evidence §3): a SIGTERM mid-session causes
the EXIT trap to fire while the xfreerdp3 child is still alive; during cleanup's 2-second unlink window,
a peer process successfully acquires a "second" lock — yielding two concurrent sessions against the same
profile, the exact invariant `instance-locking` exists to prevent.

R7's severity is **MEDIUM** (not HIGH) because exploitation requires signal-induced exit with the
xfreerdp3 child still running; the normal-exit path is safe (xfreerdp3 has terminated before the trap
fires). But the trigger is realistic: `pkill rdp-connect`, Hyprland killing the window, or Ctrl-C in a
terminal all send SIGTERM/SIGINT to bash, which fires the EXIT trap while the xfreerdp3 child is alive.

**Recommendation**: Scope **(b) — real race, small code change, single PR under strict TDD**. The fix
is to stop unlinking the PID file in the trap (or guard the unlink with an inode-identity check) and
**amend the `instance-locking` spec**, which currently REQUIRES the trap to remove the lockfile — that
requirement is the root cause of R7.

---

## 1. Current State Verification — Evidence Base

Engine: `engine/rdp-connect` @ `main` HEAD. All line numbers from this revision.

### Claim (a): `_LOCK_ACQUIRED=false` initialized before flock — **TRUE**

> `engine/rdp-connect:208`
```bash
_LOCK_ACQUIRED=false
```
Set on L208, immediately before the `exec 200>` on L209.

### Claim (b): Set to `true` only after `flock -n` succeeds — **TRUE**

> `engine/rdp-connect:210-218`
```bash
if ! flock -n 200; then
    # ... peer branch ...
    exit 0
fi
_LOCK_ACQUIRED=true
```
The `=true` assignment (L218) is reachable only by falling through the `fi` — i.e., `flock -n`
succeeded. The peer branch unconditionally `exit 0`s on L216 before reaching L218.

### Claim (c): Peer branch exits WITHOUT triggering cleanup — **TRUE**

> `engine/rdp-connect:216, 268`
```bash
216:    exit 0           # peer branch exit — trap NOT YET installed
...
268: trap cleanup EXIT   # trap registered AFTER entire flock block (198-219)
```
The peer's `exit 0` (L216) fires before the `trap cleanup EXIT` statement (L268). A trap only fires
for EXIT after it is installed; the peer's exit happens with no EXIT trap registered, so `cleanup()`
never runs for the peer. **The original T1.4 carry-forward race is closed by this ordering.**

### Claim (d): Cleanup checks `_LOCK_ACQUIRED` before `rm -f $PID_FILE` — **TRUE**

> `engine/rdp-connect:264-266`
```bash
if [ "${_LOCK_ACQUIRED:-false}" = true ] && [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
fi
```
The orchestrator's pre-explore note ("L264 DOES consult `_LOCK_ACQUIRED`") is accurate.

### Claim (e): `echo "$$">&200` writes PID AFTER acquiring lock — **TRUE**

> `engine/rdp-connect:219`
```bash
echo "$$" >&200
```
Reached only on the owner branch (after L218). A peer reading `$(<"$PID_FILE")` (L212) either sees the
owner's PID (owner reached L219) or empty content (owner crashed between L210 and L219 — kernel
released the lock, peer wouldn't be in the peer branch). The PID is always valid when a peer reads it.

### Sub-conclusion

The carry-forward text ("engine ships `_LOCK_ACQUIRED` flag (T2.2) but the trap doesn't consult it") is
**stale**. The trap DOES consult it (L264). The carry-forward should be **closed as resolved-as-described**.

---

## 2. Race Scenarios — Exhaustive Evidence Table

| ID | Scenario | Vulnerable? | Severity | Evidence (engine line numbers) |
|----|----------|-------------|----------|--------------------------------|
| **R1** | Two simultaneous starts both succeed flock | **NO** | none | L210 `flock -n 200` is kernel-level LOCK_EX\|LOCK_NB on the inode pointed to by fd 200; the kernel serializes acquisition. Two processes cannot both hold LOCK_EX on the same inode. |
| **R2** | Peer truncates PID file via `exec 200>` | **EDGE** | LOW (cosmetic) | L209 `exec 200>"$PID_FILE"` opens with `O_TRUNC`. A peer's `exec 200>` truncates the owner's already-written PID content. Impact: subsequent peers read empty PID and display `pid=?` (L212-213) instead of the owner's PID. **No concurrent xfreerdp3** — flock still serializes correctly on the unchanged inode. Pure cosmetic regression in the WARN log line. |
| **R3** | TOCTOU symlink swap on `$PID_FILE` path | **EDGE** | LOW | L191 `compute_pid_path` → L209 `exec 200>` follows symlinks. The XDG_RUNTIME_DIR path is `0700` per-user (per `instance-locking/spec.md` lines 7-9), so only the user or root can write the directory — attacker == user, not an attack. The `/tmp` fallback has uid suffix (`/tmp/rdp-<profile>-<uid>.pid`) plus sticky-bit on `/tmp`, so an attacker cannot replace a file the user already created. Pre-creation symlink attack requires predicting profile name + uid before first run — narrow. |
| **R4** | A crashes between flock-success and `echo "$$">&200` | **NO** | none | L219 echo is the only write. A crash between L210 (flock ok) and L219 leaves an empty PID file + kernel-released lock. Next start opens the same inode, `flock -n` succeeds (lock was released), `exec 200>` truncates (no-op), writes its own PID. Normal reclamation. |
| **R5** | Stale PID file from crashed prior + new start | **NO** | none | Same as R4. Kernel releases flock on process death (fd close). New start's `flock -n` succeeds regardless of stale content. Spec `instance-locking/spec.md:42-55` "Stale lockfile reclamation" already covers this. |
| **R6** | Cleanup trap fires while peer reads `$PID_FILE` | **NO** | none (theoretical) | L219 `echo "$$" >&200` is a single `write()` syscall of < 4096 bytes (PID + newline). POSIX guarantees atomicity for writes ≤ `PIPE_BUF` to regular files. `$(<file)` reads via a single `read()` loop. A reader sees either old or new content, never partial. Not exploitable. |
| **R7** | **Owner's cleanup unlinks path while still holding fd 200 → third instance creates new inode and acquires fresh lock** | **YES** | **MEDIUM** (signal-induced exit only; normal exit safe) | L264-265 `rm -f "$PID_FILE"` in trap → path unlinks while fd 200 (anonymous inode) still holds the lock. Window: unlink → fd close (at shell exit). A third process's `exec 200>"$PID_FILE"` (L209) creates a NEW inode (path was unlinked); its `flock -n 200` (L210) succeeds on the new inode. **Empirically reproduced — see §3.** The `_LOCK_ACQUIRED` check (L264) does NOT mitigate: the owner legitimately holds the flag. |
| **R8** | SIGINT/SIGTERM during the narrow flock-block window (L210-L268, trap not yet installed) | **EDGE** | NEGLIGIBLE | Trap installed on L268, after flock block. A signal between L210 (lock acquired) and L268 (trap installed) kills bash with default handlers; no EXIT trap fires; PID file may be left stale but kernel released the lock. Next start reclaims normally (R5). Window is microseconds (a few statements). No security impact, only a missing log entry. |

---

## 3. R7 Deep Dive — Empirical Reproduction

### 3.1 The race, step by step

The dangerous sequence, against the actual engine structure:

1. **A starts.** `exec 200>"$PID_FILE"` (L209) opens inode **I1** at path **P**. `flock -n 200` (L210)
   succeeds. `_LOCK_ACQUIRED=true` (L218). `echo "$$" >&200` (L219) writes A's PID to I1. Trap
   registered (L268). xfreerdp3 pipeline (L336-364) starts.
2. **Signal arrives at A.** Realistic triggers: `pkill rdp-connect`, Hyprland killing the window
   (`hyprctl` kills the client), user pressing Ctrl-C in a terminal. SIGTERM/SIGINT to bash with no
   explicit handler → bash runs the EXIT trap.
3. **A's EXIT trap fires WHILE xfreerdp3 is still alive.** The xfreerdp3 child is a separate process;
   bash's exit does not wait for it (especially when bash itself was killed). The child becomes
   orphaned (reparented to PID 1) but keeps the RDP session alive.
4. **A's cleanup hits L264-265.** `_LOCK_ACQUIRED=true` ✓, `[ -f "$PID_FILE" ]` ✓ → `rm -f "$PID_FILE"`
   unlinks **P**. Inode **I1** is now **anonymous** (still has a directory entry count of 0 but a
   positive open-fd count, so the kernel keeps it alive). **A still holds the exclusive flock on I1
   via fd 200.**
5. **C starts during the window (between A's L265 unlink and A's process-end fd-200 close).** C's
   `exec 200>"$PID_FILE"` (L209) finds path P missing → kernel **creates a NEW inode I2** at path P.
   C's `flock -n 200` (L210) targets I2 — which has no lock holder (A's lock is on I1, a different
   inode). **flock succeeds.**
6. **C proceeds.** Writes its PID to I2 (L219), starts its own xfreerdp3 pipeline.
7. **Two xfreerdp3 sessions now run concurrently against the same profile** — A's orphaned child +
   C's new child. RDP server sees two connections from the same user.

### 3.2 Empirical reproduction (executed 2026-07-21)

A faithful simulation of the engine structure (`_LOCK_ACQUIRED` flag, trap-after-flock ordering,
long-running child representing xfreerdp3, `rm -f` in trap, 2-second post-unlink sleep to enlarge the
observable window):

```
OWNER (1088103): lock acquired, starting 'xfreerdp3' (simulated as sleep 10)
OWNER (1088103): xfreerdp3 (sim) pid=1088106, waiting...
TRAP (1088103): cleanup fired, _LOCK_ACQUIRED=true
TRAP (1088103): unlinking /tmp/.../pid.lock (R7 WINDOW OPENS NOW)
TRAP (1088103): unlinked. fd 200 still open, lock still held on anonymous inode.
===Sent SIGTERM to A===
===A's sleep child (xfreerdp3 sim) still alive? Sleeper PIDs: 1088106   ← orphaned
===C attempts to acquire lock (A should be in cleanup window)===
C: LOCK ACQUIRED on new inode (R7 EXPLOITED) pid=1088146              ← BYPASS
===Remaining sleepers (orphaned xfreerdp3 sim)?===
1088106 sleep 10                                                       ← STILL ALIVE
```

Three facts established:
1. The EXIT trap fires while the xfreerdp3 child is still alive (signal-induced exit).
2. The child is orphaned but NOT killed — the RDP session persists.
3. A third process acquires a fresh lock on a new inode during the cleanup window.

### 3.3 Window of vulnerability (engine line numbers)

The window opens at **L265** (`rm -f "$PID_FILE"` — path unlinked, inode I1 anonymous but locked) and
closes when **A's bash process exits** (fd 200 closes, kernel releases lock on I1, kernel frees I1).

In the normal-exit path, this window is **benign** because the xfreerdp3 pipeline has already completed
(L336-364 is the last statement; trap fires after). A peer acquiring a new lock during this window would
find no concurrent xfreerdp3 to race with.

In the **signal-induced-exit path**, the window is **exploitable** because the xfreerdp3 child is still
alive (orphaned) when the trap fires. The window duration equals the time between A's `rm -f` and A's
process exit — typically milliseconds, but the orphaned xfreerdp3 keeps the RDP session alive for
seconds to minutes, so the RACE WINDOW for C to start is the cleanup-to-exit gap, not the xfreerdp3
lifetime.

### 3.4 What does NOT mitigate R7

- **`_LOCK_ACQUIRED` check (L264)**: irrelevant — the owner legitimately holds the flag; the check
  passes; the unlink proceeds.
- **`[ -f "$PID_FILE" ]` guard (L264)**: irrelevant — the file exists at cleanup time; the guard passes.
- **Trap-after-flock ordering**: irrelevant — R7 is about the OWNER's trap, not the peer's.
- **Kernel-level flock exclusivity**: irrelevant — the peer's flock is on a DIFFERENT inode (I2), not
  the locked inode (I1). flock is per-inode, not per-path.

---

## 4. Existing Test Coverage — Gap Analysis

| Test file | What it covers | What it does NOT cover |
|-----------|----------------|------------------------|
| `tests/pid-path.bats` (6 @test) | `compute_pid_path()` pure string output across 6 scenarios (XDG set/unset, two-user, profile isolation, legacy-negative). All mock `id -u` via function shadow. | Does NOT exercise `flock`. Does NOT exercise the engine's L209-219 flock block. Does NOT exercise multi-peer behavior. |
| `tests/cleanup-session.bats` (6 @test) | `extract_session_error()` pure text extraction from log fixtures. 4 fixture-driven + 1 byte-identical snapshot + 1 coverage meta-test. | Does NOT exercise the cleanup TRAP. Does NOT exercise the `_LOCK_ACQUIRED` check (L264). Does NOT exercise `rm -f "$PID_FILE"`. |
| `tests/harness.bats` (10 @test) | Makefile entry points, CI workflow structure, test-helper isolation, `make smoke` (single instance, `--help` only). | Does NOT exercise multi-instance behavior. `make smoke` short-circuits at `--help` before any flock code runs. |
| `tests/parser.bats`, `tests/hidpi.bats`, `tests/vpn-trim.bats`, `tests/engine-security.bats` | Pure-function unit coverage (`parse_env_safe`, `compute_dpi_flags`, `trim_profile_fields`, parser security). | Out of scope for locking behavior. |

**Coverage gap**: there is **NO bats test** that exercises:
- The flock block (L209-219).
- The `_LOCK_ACQUIRED` invariant.
- The trap ordering invariant (peer exits before trap installed).
- The cleanup unlink behavior.
- **Any multi-peer scenario.**

Under `strict_tdd: true`, the R7 fix MUST be preceded by a failing bats test that reproduces the race
at the unit/integration boundary. See §5 for the test strategy.

---

## 5. Fix Approaches

Only approaches that ELIMINATE the per-path-vs-per-inode window are real fixes. Approaches that merely
shrink the window are insufficient — the orphaned xfreerdp3 keeps the session alive regardless.

| Approach | Mechanism | Eliminates R7? | Tradeoffs | Complexity |
|----------|-----------|----------------|-----------|------------|
| **F-A** "Hold fd 200 open until the very end" | Already the case (fd 200 closes at shell exit, AFTER cleanup). The issue is the unlink WITHIN cleanup, not the fd lifetime. Re-interpretation: don't unlink at all; rely on fd-close to release lock; stale PID file is reclaimed by next start's flock. | **YES** | Loses the "PID file disappears after clean exit" property (currently required by `instance-locking/spec.md:63-68`). REQUIRES a spec amendment. | Low |
| **F-B** `flock -u` to release before unlink | Explicit unlock, then unlink, then exit. | **NO — WORSE** | Opens an unlock→unlink window where the SAME inode is unlocked AND still on disk; a peer's `exec 200>$PID_FILE` opens the SAME inode and `flock -n` succeeds. Breaks the current single-peer scenario. Non-starter. | Low |
| **F-C** Don't unlink in cleanup at all | Identical to F-A's re-interpretation. Remove L264-266 entirely (or gate behind a flag that's always false). Stale PID file persists; kernel releases lock on fd-close; next start reclaims. | **YES** | Same spec-amendment requirement as F-A. Cleanest diff. | Low |
| **F-D** Re-verify lock ownership before unlink (`flock -n 200` again in cleanup) | Misconceived. `flock -n` on an fd we already hold is idempotent (always succeeds). Cannot detect "we lost the lock" because we cannot lose it without closing fd 200. | **NO** | Does not work as described. | — |
| **F-E** Inode-identity check before unlink (`stat -c %i /proc/$$/fd/200` vs `stat -c %i "$PID_FILE"`) | Only unlink if path still points to OUR inode. If a peer already created a new inode (R7 in progress), don't unlink theirs. | **PARTIAL — does NOT eliminate R7.** The peer's flock on the new inode ALREADY SUCCEEDED before we check. We just avoid additionally unlinking their file. The race is lost by the time the check runs. | Preserves "PID file disappears on clean exit" for the common case. Does NOT prevent concurrent xfreerdp3. Linux-specific (`/proc/$$/fd/`). | Medium |
| **F-G** (recommended) **F-C + spec amendment + orphan-kill** | Don't unlink in cleanup (F-C). Amend `instance-locking` spec to drop the "MUST remove" requirement. ADD: on EXIT trap, kill the xfreerdp3 process group so it cannot orphan. | **YES** (eliminates R7 AND the orphan-xfreerdp3 footgun independently) | Largest diff (code + spec + tests). The orphan-kill is independently valuable (a `pkill rdp-connect` today leaves xfreerdp3 alive). | Medium |

### Recommended fix: **F-G** (F-C + spec amendment + orphan-kill)

**Why F-C alone is insufficient in practice**: even with the unlink removed, a `pkill rdp-connect` today
orphans the xfreerdp3 child, which keeps the RDP session alive. Without the unlink, C cannot acquire a
fresh lock (good — no R7), but the user's intent (kill the session) is also not achieved. The orphan-
kill (`kill -- -$PGID` or `pkill -P $$` in the trap) closes both holes:
- C cannot start a second session (no unlink window, but even if it could, the original xfreerdp3 is dead).
- The original xfreerdp3 actually dies when the user kills rdp-connect.

**Why F-E is rejected**: it does not prevent the race, only mitigates a secondary cosmetic issue.

### Strict-TDD test strategy (RED before GREEN)

The challenge: testing real flock behavior requires actual concurrent processes. Approach:

1. **RED test** (`tests/multi-peer-race.bats`, new file): a `@test` that forks a background subshell
   which acquires flock on a sandbox PID file, unlinks the path, holds fd 200 open for 2s, then exits.
   The foreground `@test` body attempts `flock -n` on the same path during the window. **Assert
   `flock -n` FAILS** (current engine behavior: it would SUCCEED because the path was unlinked and a
   new inode is created → test fails → RED). This test exercises the SAME mechanism the engine uses
   (flock-on-fd, path-unlink-while-locked) without needing the full engine.
2. **GREEN**: apply F-G (remove unlink from trap, add orphan-kill, amend spec). Re-run the test — the
   background subshell no longer unlinks, the path still points to the locked inode, foreground `flock -n`
   fails → test passes.
3. **REFACTOR**: clean up `_LOCK_ACQUIRED` comments (now only relevant if the trap moves earlier, which
   is unlikely), update `instance-locking/spec.md` to allow persistence + require orphan-kill.

Additional tests:
- `trap_fires_after_xfreerdp3_on_normal_exit` (golden-path regression — protects against accidentally
  moving cleanup before the pipeline).
- `orphan_xfreerdp3_killed_on_signal_exit` (mock xfreerdp3 as a sleep, send SIGTERM to the engine,
  assert the sleep child is reaped).

---

## 6. Scope Recommendation

### Recommend: **(b) Real race (R7) exists, code change needed — single PR under strict TDD.**

Rationale:

- The original carry-forward race is resolved (§1, all 5 claims TRUE) — close it as resolved-as-described.
- R7 is real and empirically reproduced (§3) — must be fixed.
- The fix is small (F-G: ~20 LOC engine change + ~40 LOC tests + spec amendment). Total well under the
  400-line review budget (forecast: ~120-180 lines including spec delta + tests + comments).
- Single PR is appropriate — no need for chained PRs.
- Strict TDD applies: RED test first (reproduces R7), then GREEN (fix), then REFACTOR (cleanup +
  spec amendment).

### Why NOT (a) "race already fixed, no code change":

The original T1.4 race is fixed, but R7 is a distinct, real, exploitable race. Closing the carry-forward
without code change would leave the instance-locking invariant broken on signal-induced exit. The
project's own `instance-locking/spec.md:57-61` scenario "Live lock from a running peer is honored" is
violated by R7 (when the "running peer" is an orphaned xfreerdp3 whose bash parent is in cleanup).

### Why NOT (c) "multiple issues surfaced":

R2 (cosmetic PID truncation) and R8 (negligible narrow signal window) are not worth separate changes.
R2 is a one-line cosmetic fix (`exec 200>>` instead of `exec 200>` would avoid truncation, but
changes file-offset semantics — not worth it for cosmetic gain). R8 is genuinely negligible. Both can
be noted as "known, not worth fixing" in the proposal.

---

## Findings

### Finding F1: Original T1.4 carry-forward race is RESOLVED

- **Severity**: none (closed).
- **Evidence**: §1 — all five claims (a)-(e) TRUE in current code; trap ordering (L216 < L268) closes
  the peer-branch-triggers-cleanup race; `_LOCK_ACQUIRED` check (L264) is belt-and-suspenders.
- **Recommended action**: close the carry-forward as resolved-as-described in the proposal.

### Finding F2: R7 — owner-cleanup unlink bypass (REAL, MEDIUM)

- **Severity**: MEDIUM. Exploitable on signal-induced exit (SIGTERM/SIGINT to bash); normal exit safe.
- **Evidence**: §2 table, §3 empirical reproduction, §3.3 window analysis. Engine L264-265.
- **Proposed approaches**: F-A, F-C, F-G all eliminate R7. F-B and F-D rejected. F-E insufficient.
- **Recommended**: **F-G** (don't unlink + spec amendment + orphan-kill).

### Finding F3: Orphan-xfreerdp3 footgun (REAL, MEDIUM, independent of R7)

- **Severity**: MEDIUM. A `pkill rdp-connect` today leaves the xfreerdp3 child alive (orphaned to
  PID 1). The user thinks they killed the session; the RDP server keeps the connection open. This is
  the SAME root cause that makes R7 impactful (orphaned xfreerdp3 + bypassed lock = two sessions).
- **Evidence**: §3.2 reproduction — `1088106 sleep 10` was still alive after parent SIGTERM.
- **Recommended**: kill the process group in the trap (`kill -- -$PGID` or `pkill -P $$`). Bundled
  into F-G.

### Finding F4: R2 — peer truncates owner's PID file (cosmetic)

- **Severity**: LOW (cosmetic). Subsequent peers see `pid=?` instead of owner's PID.
- **Evidence**: L209 `exec 200>` uses `O_TRUNC`.
- **Recommended action**: note in proposal as "known, not worth fixing standalone."

### Finding F5: Test coverage gap — no multi-peer tests

- **Severity**: process (strict-TDD compliance). No existing test exercises flock, trap ordering,
  `_LOCK_ACQUIRED`, or multi-peer scenarios.
- **Evidence**: §4.
- **Recommended action**: `tests/multi-peer-race.bats` (new) with the RED test for R7 + regression
  tests for trap ordering and orphan-kill.

---

## Recommended Scope Summary

| Item | Action | Effort |
|------|--------|--------|
| Carry-forward T1.4 (original race) | Close as resolved-as-described | None |
| R7 (owner-unlink bypass) | **Fix with F-G** (don't unlink + spec amendment + orphan-kill) | Medium (~120-180 LOC total) |
| R2 (peer truncation) | Note as known, not worth fixing | None |
| R8 (narrow signal window) | Note as negligible | None |
| Test gap | New `tests/multi-peer-race.bats` under strict TDD | Included in F-G |

**Total forecast**: single PR, ~150 lines, within 400-line review budget. Chained PRs NOT required.

---

## Risks

- **Spec-amendment surface**: F-G modifies `openspec/specs/instance-locking/spec.md` (drops "MUST
  remove lockfile" requirement, adds orphan-kill requirement). This is a normative change to a
  canonical spec — must go through the SDD delta flow (proposal → spec delta → design → tasks → apply
  → verify → archive), not a direct edit. **Mitigation**: this is what the proposal phase is for.
- **Orphan-kill blast radius**: `kill -- -$PGID` could kill unrelated processes if the process group
  is leaky. **Mitigation**: the engine should `setpgid` (or use `setsid`) at startup to isolate its
  process group; the trap kills only that group. Test coverage required.
- **Strict-TDD RED-test timing sensitivity**: the RED test relies on a background subshell holding fd
  200 open for a window. CI runners under load could make the test flaky. **Mitigation**: use a
  sentinel file or `flock -u`-on-demand rather than a fixed sleep; the test asserts the INVARIANT
  (flock on a path-unlinked-but-fd-held inode), not a timing window.
- **Signal-handler complexity**: adding orphan-kill to the trap means the trap now has teeth. Must
  verify the trap does not double-fire (EXIT is fired once, but SIGTERM-with-EXIT-trap has subtle
  ordering). **Mitigation**: bats test for signal-induced exit.
- **Hyprland kill path**: if Hyprland kills the WINDOW (not the process), the engine may receive no
  signal at all — xfreerdp3 dies (it's the window's process) but bash continues waiting on the
  pipeline. This is a DIFFERENT scenario from R7 (bash receives signal). **Mitigation**: out of scope
  for this change; note in proposal as a separate concern.

---

## Affected Areas

- `engine/rdp-connect` — the trap (L222-268), flock block (L198-219), and the xfreerdp3 pipeline
  invocation (L336-364, for process-group isolation).
- `openspec/specs/instance-locking/spec.md` — the "EXIT trap cleans the new path" requirement (L63-68)
  must be amended.
- `tests/multi-peer-race.bats` — NEW file for the strict-TDD RED-GREEN tests.
- `openspec/changes/multi-peer-race/specs/instance-locking/spec.md` — delta spec.

---

## Approaches Summary

1. **F-G (recommended)** — don't unlink + spec amendment + orphan-kill.
   - Pros: eliminates R7, eliminates orphan-xfreerdp3 footgun, preserves user intent on signal-exit,
     aligns spec with reality (kernel releases flock on process death regardless of file existence).
   - Cons: largest diff; normative spec change; new signal-handling surface.
   - Effort: Medium (~150 LOC).

2. **F-C** — don't unlink in cleanup (smallest code change).
   - Pros: 3-line diff; eliminates R7.
   - Cons: leaves orphan-xfreerdp3 footgun open; still requires spec amendment.
   - Effort: Low (~80 LOC with tests).

3. **F-E** — inode-identity check before unlink.
   - Pros: preserves "PID file disappears on clean exit" without spec amendment for the common case.
   - Cons: does NOT eliminate R7 (peer's flock already succeeded); Linux-only; adds complexity for
     no real safety gain.
   - Effort: Medium but ineffective.

4. **F-A** — equivalent to F-C in effect.

---

## Ready for Proposal

**Yes.** The orchestrator should proceed to `sdd-propose` with:

1. **Scope**: F-G (eliminate R7 + orphan-kill + spec amendment). Fallback to F-C if the proposal
   reviewer prefers a smaller diff.
2. **Strict-TDD emphasis**: RED test first (`tests/multi-peer-race.bats`), then GREEN (fix), then
   REFACTOR (spec amendment + cleanup).
3. **Carry-forward closure**: proposal should explicitly note the original T1.4 race is resolved and
   this change addresses a DIFFERENT race (R7) discovered during exploration.
4. **Out of scope**: R2 (cosmetic), R8 (negligible), Hyprland-window-kill scenario.

Tell the user: **the carry-forward text is stale — the original race is fixed — but exploration
uncovered a DIFFERENT real race (R7) that is reproducible and exploitable on signal-induced exit.
Recommendation is a single-PR fix under strict TDD, bundled with an orphan-xfreerdp3 kill in the trap.**

---

## Spec / Code / Test Provenance

- **Engine baseline**: `engine/rdp-connect` @ `main` HEAD (365 lines, sha256 pending).
- **Canonical spec**: `openspec/specs/instance-locking/spec.md` (81 lines).
- **Carry-forward text source**: `openspec/changes/archive/baseline-hardening/apply-progress.md`
  §T1.4 discovery + §T2.2 _LOCK_ACQUIRED discovery (resolution note).
- **Empirical evidence**: §3.2 reproduction script saved at `/tmp/opencode/r7-engine-test/`.
- **Skills loaded**: `sdd-explore`, `_shared`, `go-testing` (review-only — bash, not Go, but the
  strict-TDD discipline and race-condition test patterns translate).
