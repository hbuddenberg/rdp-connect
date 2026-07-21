# Delta for engine-robustness

> **HIGH-RISK (F7 — `/from-stdin:force` runtime gate):** the credential pipe is on
> the password path. A silent fallback to a build that does not support
> `/from-stdin:force` would either leak the password to `ps aux` (if the engine
> fell back to `/p:`) or hang forever reading stdin. The feature-gate MUST fail
> loudly at startup, never silently.

## ADDED Requirements

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
