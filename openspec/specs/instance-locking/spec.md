# instance-locking Capability Spec

> **HIGH-RISK surface (F5 — credential-adjacent PID path):** the per-profile
> lock gates the RDP credential session. The legacy `/tmp/rdp-<profile>.pid`
> path was world-writable and shared across users — a symlink/DoS vector that
> could either block a legitimate session or trick the user into sending
> credentials to a spoofed window. The new path MUST be uid-private and live
> under `XDG_RUNTIME_DIR` (which is `0700` and per-user by definition on systemd
> distros). This capability PAIRS with the engine-robustness `cleanup` log
> access guard: the EXIT trap MUST clean the new path.

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

### Requirement: EXIT trap cleans the new path (pairs with engine-robustness cleanup guard)

The engine's EXIT trap MUST remove the lockfile at the NEW uid-private path on
every exit (success, error, signal). The trap MUST NOT reference the legacy
`/tmp/rdp-<profile>.pid` path. If the lockfile was never created (early exit
before `flock`), the trap MUST tolerate the missing file without error.

#### Scenario: Normal session exit cleans up

- GIVEN a completed RDP session that wrote the new lockfile
- WHEN the engine exits `0`
- THEN the lockfile at the new path no longer exists
- AND (manual-verify: run a session to completion; `ls /run/user/$(id -u)/rdp-*.pid` returns empty)

#### Scenario: Early-exit before flock does not error

- GIVEN an engine exit before the `flock` block ran (e.g. `require_cmd` failure)
- WHEN the EXIT trap fires
- THEN the trap completes without a "No such file" error (the `[ -f ]` guard from the engine-robustness cleanup requirement covers this)
