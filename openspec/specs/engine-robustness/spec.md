# engine-robustness Capability Spec

> **HIGH-RISK surface (F7 — `/from-stdin:force` runtime gate):** the credential
> pipe is on the password path. A silent fallback to a build that does not
> support `/from-stdin:force` would either leak the password to `ps aux` (if the
> engine fell back to `/p:`) or hang forever reading stdin. The feature-gate
> MUST fail loudly at startup, never silently.

## Requirements

### Requirement: Strict mode with tactical error suppression

The engine MUST run under `set -euo pipefail` for its entire execution.
`|| true` (or equivalent suppression) MUST be applied ONLY to documented cosmetic
Hyprland IPC calls that do not affect session integrity — specifically
`hyprctl keyword windowrulev2` and `hyprctl dispatch focuswindow`. Suppression
MUST NOT be applied to `xfreerdp3`, `flock`, `jq`, file tests, or any
security-relevant call. A real failure (xfreerdp3 non-zero exit, host unreachable,
flock contention on a live peer) MUST still propagate to the EXIT trap.

#### Scenario: Transient hyprctl blip does not abort a live session

- GIVEN a connected RDP session under `set -euo pipefail`
- WHEN `hyprctl dispatch focuswindow` returns non-zero (e.g. window not yet mapped)
- THEN the engine continues running and the session is unaffected
- AND (manual-verify: start a session; `kill -0` the engine PID after focuswindow noise)

#### Scenario: Real failure still propagates

- GIVEN the engine under `set -euo pipefail`
- WHEN `xfreerdp3` exits non-zero (unreachable host or auth failure)
- THEN the EXIT trap fires with the non-zero `$EXIT_CODE` and the ERROR log line is written
- AND (manual-verify: point a profile at `127.0.0.1:1`; observe ERROR log entry)

### Requirement: require_cmd preflight for every external binary

The engine MUST call a `require_cmd <name>` helper at startup — before any profile
is loaded — for each of: `xfreerdp3`, `hyprctl`, `jq`, `notify-send`, `flock`,
and at least one of `wofi` or `rofi`. A missing binary MUST cause the engine to
exit `127` with a clear message naming the missing command and the package that
provides it. `require_cmd` MUST NOT be skipped on any code path that reaches
profile parsing.

#### Scenario: Missing jq aborts with exit 127

- GIVEN a system where `jq` is not on `PATH`
- WHEN the engine starts
- THEN it exits `127` with a message like `missing required command: jq (install via your package manager)`
- AND (manual-verify: `PATH=/usr/bin:/bin rdp-connect <profile>` with `jq` renamed aside; observe exit code `echo $?`)

#### Scenario: Missing both wofi and rofi aborts

- GIVEN a system where neither `wofi` nor `rofi` is installed
- WHEN the engine starts in selector mode (no profile argument)
- THEN it exits `127` naming the missing launcher pair
- AND (manual-verify: hide both binaries via `PATH`; confirm exit code and message)

#### Scenario: All binaries present proceeds normally

- GIVEN all required binaries on `PATH`
- WHEN the engine starts
- THEN it proceeds past preflight without printing a missing-command message

### Requirement: /from-stdin:force runtime feature gate

The engine MUST probe `xfreerdp3 /help` (or equivalent) at startup and confirm
that `/from-stdin:force` is supported by the installed build. If the build does
NOT support it, the engine MUST exit non-zero with an actionable message naming
the required xfreerdp3 build feature. The engine MUST NOT fall back to passing
the password via a command-line flag (`/p:`).

#### Scenario: Build without /from-stdin:force is rejected

- GIVEN an `xfreerdp3` whose `/help` output does not mention `from-stdin`
- WHEN the engine starts
- THEN it exits non-zero with a message instructing the user to install a FreeRDP build with stdin support
- AND (manual-verify: place a stub `xfreerdp3` printing a `/help` without the flag on `PATH`; observe rejection)

#### Scenario: Build with /from-stdin:force proceeds

- GIVEN an `xfreerdp3` whose `/help` mentions `from-stdin`
- WHEN the engine starts
- THEN it proceeds past the feature gate to profile loading

### Requirement: Flag arrays instead of string interpolation

`MON_FLAGS` and `DPI_FLAGS` MUST be declared as bash arrays and expanded with the
quoted-safe form `"${MON_FLAGS[@]-}"` / `"${DPI_FLAGS[@]-}"`. The engine MUST NOT
build either flag set by string concatenation or unquoted `$VAR` interpolation
into the `xfreerdp3` command line. Empty arrays MUST expand to nothing under
`set -u` without raising "unbound variable".

#### Scenario: Multi-monitor builds an array

- GIVEN Hyprland reports two or more monitors
- WHEN the engine builds `MON_FLAGS`
- THEN `MON_FLAGS` is an array whose expansion yields `/multimon /monitors:<ids>`
- AND (manual-verify: `declare -p MON_FLAGS` shows `declare -a` with the expected elements)

#### Scenario: Single-monitor builds /f array

- GIVEN Hyprland reports exactly one monitor
- WHEN the engine builds `MON_FLAGS`
- THEN `MON_FLAGS` expands to `/f`

#### Scenario: Empty DPI_FLAGS under set -u

- GIVEN a monitor with scale `1` (no HiDPI)
- WHEN the engine expands `"${DPI_FLAGS[@]-}"` under `set -u`
- THEN the expansion yields nothing and the engine does NOT abort with "unbound variable"
- AND (manual-verify: run with scale=1; confirm `set -e` engine still launches xfreerdp3)

### Requirement: cleanup log access guard

The `cleanup()` EXIT trap MUST guard every read of `$LOG_FILE` with
`[ -f "$LOG_FILE" ]` (or equivalent) before `tail`, `grep`, or any other access.
If the log file does not exist, `cleanup()` MUST skip the error-extraction branch
and still emit the non-zero-exit notification (without the parsed `LAST_ERROR`).

#### Scenario: EXIT before log file exists does not crash

- GIVEN the engine exits very early (e.g. `require_cmd` failure) before any log line is written
- WHEN the EXIT trap fires
- THEN `cleanup()` completes without a "No such file" error and the user sees a critical notification
- AND (manual-verify: trigger an early exit by hiding `jq`; confirm no `tail` stderr on console)

### Requirement: Cleanup error diagnostic scoped to the current session

When the `cleanup()` EXIT trap extracts an error line from the profile's LOG_FILE
to surface to the user (via `notify-send` and the log), it MUST only consider
log lines written by the CURRENT engine process — not stale ERROR lines from
prior sessions in the same per-profile log file. Concurrent sessions on the same
profile (impossible under `flock` but defensive against future refactors) MUST
NOT cross-pollinate.

The engine MUST write a `SESSION_START` marker (tagged with the engine's PID) as
the FIRST log line of every session (immediately after the EXIT trap is
registered, before any other `log_event` call). The cleanup trap's error-line
extractor MUST scan forward from the current PID's `SESSION_START` marker and
ignore every preceding line. PID matching MUST be prefix-safe: the marker
pattern MUST NOT match a PID that is a prefix of the current PID (e.g. `pid=2222`
MUST NOT match a marker for `pid=22222`).

If the LOG_FILE has no `SESSION_START` marker for the current PID (e.g. a legacy
log file written by a pre-marker engine build), the extractor MUST return empty
and `cleanup()` MUST fall back to a generic "see log" notification. Surfacing
NOTHING is correct; surfacing a stale cause from a prior session is a bug.

#### Scenario: Cleanup diagnostic scoped to current session by PID

- GIVEN a per-profile LOG_FILE containing ERROR lines from a PRIOR session (Session A) followed by a SESSION_START marker for the current PID and the current session's own ERROR line (Session B)
- WHEN the current session's `cleanup()` EXIT trap fires with a non-zero exit code
- THEN the surfaced `LAST_ERROR` is Session B's ERROR line (the current session)
- AND Session A's stale ERROR line is NOT surfaced
- AND (manual-verify: write a synthetic LOG_FILE with two sessions' lines; pipe through the cleanup awk extractor with the current PID; assert the Session B line is returned)

#### Scenario: PID prefix safety

- GIVEN a SESSION_START marker containing `pid=22222` and a current engine PID of `2222`
- WHEN the cleanup extractor scans for the current PID's marker
- THEN the marker for `pid=22222` is NOT matched (2222 is a prefix of 22222 but not equal)
- AND the extractor returns empty (no marker for our exact PID)

#### Scenario: Current session with no ERROR line returns empty

- GIVEN a SESSION_START marker for the current PID followed by INFO/WARN lines but no ERROR
- WHEN the cleanup extractor runs
- THEN it returns empty and `cleanup()` falls back to the generic "see log" notification
- AND no stale ERROR line from any prior session is surfaced

#### Scenario: Legacy log file without SESSION_START marker degrades gracefully

- GIVEN a LOG_FILE written by a pre-marker engine build (no SESSION_START line for any PID)
- WHEN the cleanup extractor scans for the current PID's marker
- THEN it returns empty (no marker found) and `cleanup()` falls back to the generic "see log" notification

### Requirement: Preflight input normalization (trim whitespace from profile fields)

After `parse_env_safe` parses the profile and BEFORE any preflight check
(TCP probe, VPN reachability, host probe), the engine MUST trim leading and
trailing whitespace from these fields: `HOST`, `VPN_CHECK`, `DOMAIN`,
`PREFERRED_WS`, `LANG_OVERRIDE`. An all-whitespace value (e.g. `VPN_CHECK=" "`)
MUST normalize to the empty string and MUST be treated as "not set" by every
downstream preflight guard.

The engine MUST NOT trim `PASS_RDP` or `USER_RDP`. Passwords and user
identifiers MAY legally contain surrounding whitespace; silently altering them
would corrupt credentials.

This requirement exists because profile values copied from chat applications,
editors with trailing-whitespace highlighting disabled, or Windows-edited files
frequently contain invisible trailing bytes — and the original bug report
("VPN required when empty" plus a confusing "unterminated quote" on the same
profile) traced to a `VPN_CHECK=" "` value that passed the `-n` non-empty test
but produced a useless "VPN requerida ( )" message and never reached the host.

#### Scenario: VPN_CHECK with whitespace trimmed before preflight

- GIVEN a profile containing `VPN_CHECK="  "` (only whitespace)
- WHEN the engine parses the profile and reaches the VPN preflight guard
- THEN the trimmed `VPN_CHECK` equals the empty string
- AND the VPN preflight is SKIPPED (treated as "no VPN configured")
- AND no "VPN requerida" notification is shown for the whitespace-only value
- AND (manual-verify: write a profile with `VPN_CHECK="  "` and `HOST="unreachable"`; run engine; observe the engine skips VPN preflight and proceeds to host preflight, exit 1 on host unreachable with NO "VPN requerida" line)

#### Scenario: HOST with surrounding whitespace is trimmed before TCP probe

- GIVEN a profile containing `HOST="  server.example.com  "` (surrounding whitespace)
- WHEN the engine trims profile fields and reaches the host TCP probe
- THEN the probe target is `server.example.com` (trimmed), not the whitespace-bearing literal
- AND the TCP socket probe resolves and connects to the trimmed host

#### Scenario: PASS_RDP and USER_RDP are NOT trimmed

- GIVEN a profile containing `PASS_RDP="  secret  "` and `USER_RDP="  user  "` (surrounding whitespace)
- WHEN the engine trims profile fields
- THEN `PASS_RDP` and `USER_RDP` retain their literal whitespace (the trim block skips them)
- AND the credentials sent to xfreerdp3 are exactly the literal values from the profile
- AND (manual-verify: write a profile with deliberately padded PASS_RDP/USER_RDP; confirm via `bash -x` that the values reach xfreerdp3 verbatim)

### Requirement: Scenario-to-test parity for robustness scenarios

> **Origin**: promoted from `strict-tdd-enable` delta (`engine-robustness-delta.md`)
> at archive. Additive — layers a testability contract onto the two requirements
> above ("Preflight input normalization" and "Cleanup error diagnostic scoped to
> the current session"). No existing requirement text changed.

Every scenario under "Preflight input normalization" and "Cleanup error
diagnostic scoped to the current session" in this spec MUST have a
corresponding `@test` block in `tests/vpn-trim.bats` (trim cases) or
`tests/cleanup-session.bats` (session-isolation cases) that exercises the SAME
Given/When/Then. Manual-verify footers stay (integration-level); the `@test`
covers the unit-level contract via extracted lib functions. This is what
`strict_tdd: true` enforces on this capability.

#### Scenario: All 7 robustness scenarios have @test parity

- GIVEN the 3 preflight-trim scenarios (whitespace-only `VPN_CHECK`,
  surrounding-whitespace `HOST`, padded `PASS_RDP`/`USER_RDP`) and the 4
  cleanup-session-isolation scenarios (stale prior-session ERROR, PID prefix
  collision `2222` vs `22222`, current-session no-ERROR, legacy
  no-SESSION_START)
- WHEN `bats tests/` runs
- THEN each of the 7 scenarios has a corresponding `@test` block
- AND every `@test` passes on a fresh clone (post-F3 extraction)

### Requirement: `trim_profile_fields()` extraction preserves byte-identical behavior

> **Origin**: promoted from `strict-tdd-enable` delta at archive.

`trim_profile_fields()` MUST live in `lib/rdp-common.bash` (not inlined in
`engine/rdp-connect`). For any profile fixture, the extracted function MUST
produce byte-identical output to the current inline parameter-expansion idiom
for: `HOST`, `VPN_CHECK`, `DOMAIN`, `PREFERRED_WS`, `LANG_OVERRIDE`. The
function MUST NOT trim `PASS_RDP` or `USER_RDP` (reinforces the existing
"Preflight input normalization" requirement; security-side framing in
`engine-security/spec.md`).

#### Scenario: 8 vpn-trim fixtures pass byte-identical pre/post extraction

- GIVEN the 8 fixtures under `tests/fixtures/vpn-trim/` (whitespace-only,
  surrounding-whitespace, quoted-with-inline-comment, padded
  `PASS_RDP`/`USER_RDP` — R4 mitigation)
- WHEN `trim_profile_fields()` runs on each fixture
- THEN output matches the approval-test snapshot taken before extraction
- AND `PASS_RDP`/`USER_RDP` retain literal surrounding whitespace on every fixture
- AND (@test `vpn-trim.bats::trim_profile_fields_byte_identical_on_fixtures`: assert each fixture equals its snapshot under `tests/fixtures/vpn-trim/__snapshots__/`)

#### Scenario: @test coverage for `trim_profile_fields()`

- GIVEN `tests/vpn-trim.bats` sources `test_helper.bash` and exercises
  `trim_profile_fields` on the 8 fixtures
- WHEN `bats tests/vpn-trim.bats` runs
- THEN every `@test` passes (the "approval test exercises a copy, not
  production code" smell is killed because the function now lives in lib)
- AND (@test `vpn-trim.bats::trim_profile_fields_has_unit_coverage`: meta-assertion of ≥ 8 cases targeting the function)

### Requirement: `extract_session_error()` extraction preserves behavior

> **Origin**: promoted from `strict-tdd-enable` delta at archive.

`extract_session_error()` MUST live in `lib/rdp-common.bash`. For any
`LOG_FILE` fixture, it MUST produce the SAME `LAST_ERROR` string as the
current inline `awk` extractor in the engine's cleanup trap. PID-scoping
semantics (prefix safety, empty fallback on no marker, generic "see log" on
legacy logs) MUST be preserved exactly — see the existing "Cleanup error
diagnostic scoped to the current session" requirement.

#### Scenario: Multi-session `LOG_FILE` fixtures match pre-extraction output

- GIVEN fixtures under `tests/fixtures/cleanup-session/` (prior-session-stale-
  ERROR, PID prefix collision, current-session-no-ERROR, legacy-no-
  SESSION_START)
- WHEN `extract_session_error()` runs on each fixture with the current PID injected
- THEN the returned `LAST_ERROR` matches the pre-extraction snapshot
- AND the empty-string fallback is preserved verbatim
- AND (@test `cleanup-session.bats::extract_session_error_byte_identical_on_fixtures`: assert each fixture's `LAST_ERROR` equals its snapshot)

#### Scenario: @test coverage for `extract_session_error()`

- GIVEN `tests/cleanup-session.bats` sources `test_helper.bash` and exercises
  `extract_session_error` on the 4 multi-session fixtures
- WHEN `bats tests/cleanup-session.bats` runs
- THEN all 4 session-isolation scenarios from this spec are covered by `@test`
  blocks and pass
- AND (@test `cleanup-session.bats::extract_session_error_has_unit_coverage`: meta-assertion of ≥ 4 cases targeting the function)

### Requirement: Process-group isolation and signal-induced cleanup

> **Added by `multi-peer-race` (2026-07-21).** Closes the orphan-kill footgun:
> pre-fix, `pkill rdp-connect` (or Hyprland killing the engine process, or
> Ctrl-C in a terminal) left the `xfreerdp3` child alive — orphaned to PID 1,
> still holding the RDP session open. The user thought they killed the
> session; the server kept the connection. This requirement isolates the
> engine and its children into a dedicated POSIX process group at startup so
> the EXIT trap can reliably reap the `xfreerdp3` child on signal-induced
> exit. It PAIRS with the MODIFIED `instance-locking` "EXIT trap preserves the
> lockfile path" requirement: together they guarantee that a signal-induced
> exit reaps the child AND preserves the lockfile path, closing both R7 and
> the orphan-kill footgun in one diff.

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
