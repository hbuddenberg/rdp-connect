# instance-locking Capability Spec

> **HIGH-RISK surface (F5 — credential-adjacent PID path):** the per-profile
> lock gates the RDP credential session. The legacy `/tmp/rdp-<profile>.pid`
> path was world-writable and shared across users — a symlink/DoS vector that
> could either block a legitimate session or trick the user into sending
> credentials to a spoofed window. The new path MUST be uid-private and live
> under `XDG_RUNTIME_DIR` (which is `0700` and per-user by definition on systemd
> distros). This capability PAIRS with the engine-robustness `cleanup` log
> access guard AND the `engine-robustness` "Process-group isolation and
> signal-induced cleanup" requirement: the EXIT trap MUST NOT unlink the new
> path (the R7 race — see "EXIT trap preserves the lockfile path" below — is
> closed by path persistence + kernel fd-close flock release + the trap's
> process-group kill reaping the xfreerdp3 child before it can outlive the
> owner). Archived by `multi-peer-race` (2026-07-21); previously the trap
> unlinked the path, which created an anonymous inode and let a contender
> bypass the lock during the cleanup window.

## Requirements

### Requirement: uid-private PID path under XDG_RUNTIME_DIR

The PID lockfile path MUST be `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-$(id -u).pid`.
When `XDG_RUNTIME_DIR` is set (the common case on systemd-based distros), the
lockfile MUST resolve under `/run/user/<uid>/`. The filename MUST include the
numeric uid so two users on the same host cannot collide or interfere with each
other's locks. The fallback to `/tmp` is permitted ONLY when `XDG_RUNTIME_DIR`
is unset; even under the fallback the uid suffix MUST be present.

#### Scenario: XDG_RUNTIME_DIR set resolves under /run/user

- GIVEN a host where `XDG_RUNTIME_DIR=/run/user/1000`
- WHEN the engine computes the PID path for profile `partner`
- THEN the path equals `/run/user/1000/rdp-partner-1000.pid`
- AND (manual-verify: `echo "$XDG_RUNTIME_DIR"` + `rdp-connect partner`; check `ls /run/user/$(id -u)/rdp-partner-*.pid`)

#### Scenario: XDG_RUNTIME_DIR unset falls back to /tmp with uid suffix

- GIVEN a host where `XDG_RUNTIME_DIR` is unset
- WHEN the engine computes the PID path for profile `partner` as uid 1000
- THEN the path equals `/tmp/rdp-partner-1000.pid` (uid-suffixed, never the legacy `/tmp/rdp-partner.pid`)

#### Scenario: Two users on the same host do not collide

- GIVEN uids 1000 and 1001 both running profile `partner`
- WHEN each engine instance computes its PID path
- THEN the two paths differ in the uid suffix and neither flock blocks the other

### Requirement: Stale lockfile reclamation

If the lockfile exists but the PID recorded inside it is no longer alive (process
exited, host rebooted, crash), the engine MUST reclaim the lock automatically —
overwrite the lockfile with its own PID and proceed — instead of refusing to
start. Reclamation MUST be atomic with respect to other contenders via the
existing `flock -n` advisory lock.

#### Scenario: Stale lock from a crashed prior instance is reclaimed

- GIVEN a leftover lockfile at the new path whose recorded PID is not a live process
- WHEN the engine starts for the same profile
- THEN `flock -n` succeeds, the engine overwrites the lockfile with its own PID, and the session proceeds normally
- AND (manual-verify: `echo 99999 > "$XDG_RUNTIME_DIR/rdp-partner-$(id -u).pid"`; run `rdp-connect partner`; confirm it starts)

#### Scenario: Live lock from a running peer is honored

- GIVEN a lockfile whose recorded PID IS a live, running `rdp-connect` for the same profile
- WHEN a second engine instance starts for the same profile
- THEN `flock -n` fails, the second instance emits `MSG_ALREADY_ACTIVE`, focuses the existing window, and exits `0`

### Requirement: EXIT trap preserves the lockfile path (pairs with engine-robustness cleanup guard)

> **Amended by `multi-peer-race` (2026-07-21).** Previously "EXIT trap cleans
> the new path" — REQUIRED `rm -f "$PID_FILE"` on every exit. That created the
> R7 owner-unlink bypass window: unlinking the path while fd 200 still held the
> inode flock created an anonymous inode; a contender's `exec 200>"$PID_FILE"`
> materialized a NEW inode at the same path and `flock -n` succeeded on it —
> two concurrent xfreerdp3 sessions during cleanup. The requirement is
> INVERTED — path persistence is the new contract; cleanup is delegated to the
> kernel's fd-close flock release.

The engine's EXIT trap MUST NOT `rm -f` (or otherwise unlink) the lockfile at
the NEW uid-private path on any exit path — success, error, or signal-induced.
The trap MUST leave `$PID_FILE` on disk so the inode held by fd 200 remains
reachable by path for the lifetime of the lock. The trap MUST NOT reference the
legacy `/tmp/rdp-<profile>.pid` path. If the lockfile was never created (early
exit before `flock`), the trap MUST tolerate the missing file without error.

Rationale: the Linux kernel releases the advisory flock on fd 200 automatically
when the engine process dies (fd close, including SIGKILL). Path persistence is
therefore benign — the next start's `flock -n` either fails (live owner still
holding the lock) or succeeds (stale path, kernel-released lock). Unlinking the
path while fd 200 still holds the lock creates an anonymous inode; a
contender's `exec 200>"$PID_FILE"` then materializes a NEW inode at the same
path and acquires a fresh lock on it — the R7 race.

#### Scenario: Normal session exit leaves the lockfile on disk

- GIVEN a completed RDP session that wrote the lockfile at the new uid-private path
- WHEN the engine exits `0`
- THEN the lockfile at the new path STILL EXISTS on disk (path persists)
- AND the inode's advisory flock is released by the kernel on fd-200 close (no lingering lock)
- AND (@test `multi-peer-race.bats::clean_exit_leaves_pid_file_on_disk`)

#### Scenario: Signal-induced EXIT trap does NOT unlink the lockfile

- GIVEN a running engine that acquired flock on `$PID_FILE` and started its xfreerdp3 pipeline
- WHEN the engine receives SIGTERM (or SIGINT) and the EXIT trap fires while fd 200 is still open
- THEN the trap MUST NOT execute `rm -f "$PID_FILE"` (the path persists through the trap)
- AND a contender that runs `exec 200>"$PID_FILE" ; flock -n 200` against the same path within the trap window FAILS to acquire the lock (fd 200 still holds it on the SAME inode)
- AND (@test `multi-peer-race.bats::sigterm_exit_trap_does_not_unlink_pid_file`)

#### Scenario: Early-exit before flock does not error

- GIVEN an engine exit before the `flock` block ran (e.g. `require_cmd` failure on a missing binary)
- WHEN the EXIT trap fires
- THEN the trap completes without a "No such file" error (the `[ -f ]` guard from the engine-robustness cleanup requirement covers this; the new no-unlink contract changes nothing for this path)
- AND (@test `multi-peer-race.bats::early_exit_before_flock_does_not_error`)

### Requirement: Path-persistence reclamation by next start

> **Added by `multi-peer-race` (2026-07-21).** Extends the existing "Stale
> lockfile reclamation" requirement (which already covers crashed predecessors)
> by making the reclamation contract EXPLICIT for the post-fix world, where
> EVERY clean exit also leaves a lockfile on disk. The mechanism is identical
> (`exec 200>"$PID_FILE"` + `flock -n 200`); this requirement exists so the
> persistent-path behavior is independently testable and so the contract is
> named in the spec.

When the engine starts and the lockfile at `$PID_FILE` already exists from a
prior instance — whether that prior instance exited cleanly (path persists per
the "EXIT trap preserves the lockfile path" requirement above), crashed, or was
killed by SIGKILL — the engine MUST reclaim the lockfile via the existing
`exec 200>"$PID_FILE"` + `flock -n 200` sequence WITHOUT user intervention and
WITHOUT special-casing the predecessor's exit type. Reclamation correctness
rests on a single kernel guarantee: a dead process holds no flock, regardless
of whether its lockfile path was removed.

#### Scenario: Next start after a CLEAN exit reclaims via flock -n

- GIVEN a lockfile at `$PID_FILE` left by a prior instance that exited `0` cleanly (path persists per the "EXIT trap preserves the lockfile path" requirement)
- WHEN the next engine instance runs `exec 200>"$PID_FILE"` and `flock -n 200`
- THEN `flock -n` SUCCEEDS (the prior owner's fd 200 was closed at process exit, releasing the lock on the same inode)
- AND the new engine overwrites the file with its own PID and proceeds normally
- AND (@test `multi-peer-race.bats::next_start_reclaims_after_clean_exit`)

#### Scenario: Next start after a CRASHED predecessor reclaims via flock -n

- GIVEN a lockfile at `$PID_FILE` left by a prior instance that was killed with SIGKILL (or host reboot, or any unclean exit)
- WHEN the next engine instance runs `exec 200>"$PID_FILE"` and `flock -n 200`
- THEN `flock -n` SUCCEEDS (the kernel released the advisory lock when the dead owner's fds were reaped)
- AND the new engine overwrites the file with its own PID and proceeds normally
- AND (@test `multi-peer-race.bats::next_start_reclaims_after_crashed_predecessor`)

#### Scenario: Two concurrent starts against the same profile serialize

- GIVEN two engine processes A and B starting near-simultaneously against the same profile, where A is in its EXIT-trap window (signal-induced exit, fd 200 still open, path NOT unlinked)
- WHEN B runs `exec 200>"$PID_FILE"` and `flock -n 200` against the same path during A's trap window
- THEN B's `flock -n` FAILS (A's fd 200 still holds the lock on the SAME inode — the path was NOT unlinked, so B opened the same inode, not a fresh one)
- AND B emits `MSG_ALREADY_ACTIVE`, focuses the existing window, and exits `0`
- AND (@test `multi-peer-race.bats::two_concurrent_starts_serialize_via_flock`)
