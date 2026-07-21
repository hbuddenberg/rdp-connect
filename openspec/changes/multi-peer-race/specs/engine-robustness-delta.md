# Delta for engine-robustness

> **Change**: `multi-peer-race` · **Capability**: `engine-robustness` (ADDITIVE)
> **Orphan-kill footgun**: today, `pkill rdp-connect` (or Hyprland killing the
> engine process, or Ctrl-C in a terminal) leaves the `xfreerdp3` child alive —
> orphaned to PID 1, still holding the RDP session open. The user thinks they
> killed the session; the server keeps the connection. This delta adds a
> process-group-isolation requirement so the EXIT trap can reliably reap the
> xfreerdp3 child on signal-induced exit. It PAIRS with the MODIFIED
> `instance-locking` "EXIT trap preserves the lockfile path" requirement:
> together they guarantee that a signal-induced exit reaps the child AND
> preserves the lockfile path, closing both R7 and the orphan-kill footgun.

## ADDED Requirements

### Requirement: Process-group isolation and signal-induced cleanup

The engine MUST isolate itself and its children into a dedicated POSIX process
group at startup so the EXIT trap can reap any orphaned child (notably
`xfreerdp3`) on signal-induced exit. Specifically:

1. The engine MUST call `setpgid` (or `setsid`) at startup so it becomes the
   process-group leader of a fresh group whose PGID equals the engine's PID.
2. This call MUST happen BEFORE the `xfreerdp3` pipeline is launched so the
   child inherits the engine's process group.
3. The EXIT trap MUST issue `kill -- -$$` (equivalently `kill -- -$PGID` where
   `$PGID == $$`) before exit, terminating every process in the engine's group.
4. The process-group kill MUST be scoped to the engine's OWN group only — the
   kill target MUST be a negative PID with a leading `-` (the PGID), never the
   engine's positive PID alone, and never a broader scope (e.g. PID `0`, `-1`,
   or a foreign PGID).

This requirement is paired with the MODIFIED `instance-locking` "EXIT trap
preserves the lockfile path" requirement: together they guarantee that a
signal-induced exit reaps the xfreerdp3 child AND preserves the lockfile path
so a contender cannot bypass the lock during cleanup. If the trap fails to fire
(e.g. `SIGKILL`), the orphan persists — acceptable because that is the status
quo today; this change strictly improves on it.

#### Scenario: Engine calls setpgid (or setsid) at startup

- GIVEN a freshly started engine process with PID `$$`
- WHEN the engine reaches the line immediately after its `setpgid` (or `setsid`) call
- THEN the engine's PGID equals its own PID (`ps -o pgid= -p $$` yields `$$`)
- AND the engine is the process-group leader of that group (no other process was the leader before it)
- AND (@test `multi-peer-race.bats::engine_calls_setpgid_at_startup`)

#### Scenario: EXIT trap fires kill on the engine's process group

- GIVEN a running engine whose PGID equals its PID and whose xfreerdp3 child is alive in the same group
- WHEN the engine receives SIGTERM and the EXIT trap fires
- THEN the trap issues a `kill` whose first argument begins with `-` (negative-PID / PGID form)
- AND the kill target equals the engine's own PGID, not a broader scope (not `0`, not `-1`, not the engine's positive PID alone)
- AND (@test `multi-peer-race.bats::exit_trap_fires_kill_on_process_group`)

#### Scenario: Orphaned xfreerdp3 (simulated via background sleep) is killed when the trap fires

- GIVEN a running engine that launched a child process simulating xfreerdp3 (e.g. `sleep 60 &`) in the engine's process group
- WHEN the engine receives SIGTERM and the EXIT trap fires `kill -- -$$`
- THEN the simulated-xfreerdp3 child process is TERMINATED by the trap's process-group kill
- AND no `sleep` child whose PGID equals the engine's PID survives the trap
- AND (@test `multi-peer-race.bats::orphan_xfreerdp3_killed_on_signal_exit`)

#### Scenario: Process-group kill does NOT affect processes outside the engine's group

- GIVEN an engine running in PGID `$$` AND an unrelated process running in a DIFFERENT process group (e.g. a `sleep` started by the test harness in its own group, NOT inherited by the engine)
- WHEN the engine's EXIT trap fires `kill -- -$$`
- THEN the unrelated process in the other group is NOT terminated
- AND ONLY processes whose PGID equals the engine's PID are signalled
- AND (@test `multi-peer-race.bats::process_group_kill_is_scoped_to_engine_group_only`)

#### Scenario: Single-instance PID-file behavior is unchanged (regression)

- GIVEN the existing single-instance test suites at `tests/pid-path.bats`, `tests/cleanup-session.bats`, and `tests/harness.bats` (which cover the flock block, PID-path computation, and cleanup-trap log guards)
- WHEN `make ci` runs the full bats suite with the new `setpgid` + trap-kill changes applied
- THEN every pre-existing `@test` continues to pass (single-instance acquisition, peer-branch `MSG_ALREADY_ACTIVE`, and cleanup log-guard paths are NOT regressed)
- AND (@test `multi-peer-race.bats::single_instance_behavior_unchanged_regression`)
