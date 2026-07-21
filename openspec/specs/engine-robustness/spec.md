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
