# Delta for engine-robustness

## MODIFIED Requirements

### Requirement: Strict mode with tactical error suppression

The engine MUST run under `set -euo pipefail` for its entire execution.
`|| true` (or equivalent suppression) MUST be applied ONLY to documented
cosmetic compositor dispatch calls that do not affect session integrity — the
lib dispatch wrappers for window-rule registration, focus restore, and window
geometry (see compositor-backends dispatch contract). Compositor QUERIES
(detection probes, monitor/workspace reads) MUST be guarded by explicit
return-code capture that degrades with a WARN — never an abort, and never
`|| true` on their `jq` pipelines. Suppression MUST NOT be applied to
`xfreerdp3`, `flock`, `jq`, file tests, or any security-relevant call. A real
failure (xfreerdp3 non-zero exit, host unreachable, flock contention on a live
peer) MUST still propagate to the EXIT trap.

(Previously: suppression was enumerated as `hyprctl keyword windowrulev2` and
`hyprctl dispatch focuswindow`; compositor queries were unguarded inline
hyprctl pipes.)

#### Scenario: Transient dispatch blip does not abort a live session

- GIVEN a connected RDP session under `set -euo pipefail`
- WHEN a compositor dispatch wrapper (e.g. focus restore) returns non-zero (e.g. window not yet mapped)
- THEN the engine continues running and the session is unaffected
- AND (@test `backends.bats::dispatch_failure_does_not_abort`; manual-verify: `kill -0` the engine PID after focus noise)

#### Scenario: Real failure still propagates

- GIVEN the engine under `set -euo pipefail`
- WHEN `xfreerdp3` exits non-zero (unreachable host or auth failure)
- THEN the EXIT trap fires with the non-zero `$EXIT_CODE` and the ERROR log line is written
- AND (manual-verify: point a profile at `127.0.0.1:1`; observe ERROR log entry)

#### Scenario: Wrong-compositor CLI present degrades without abort

- GIVEN `hyprctl` on PATH but the session is niri (hyprctl answers rc=1 plain text) — and the inverse: `niri` on PATH under Hyprland
- WHEN the engine runs detection and monitor queries under `set -euo pipefail`
- THEN no `jq` parse crash occurs, the failing probe is skipped, and the engine WARNs and degrades per detection (correct backend, or none)
- AND (@test `backends.bats::wrong_compositor_cli_warn_degrade_no_abort`)

### Requirement: require_cmd preflight for every external binary

The engine MUST call a `require_cmd <name>` helper at startup — before any
profile is loaded — for each of: `xfreerdp3`, `jq`, `notify-send`, `flock`,
and at least one of `wofi` or `rofi`. The compositor CLI is
detection-conditional: after compositor detection, `require_cmd` for the
compositor binary MUST run only for the detected backend (`hyprctl` when
`COMPOSITOR=hypr`; `niri` when `COMPOSITOR=niri`); under `COMPOSITOR=none` no
compositor `require_cmd` runs (the detection WARN already names the mode). A
missing required binary MUST cause the engine to exit `127` with a clear
message naming the missing command and the package that provides it.
`require_cmd` MUST NOT be skipped on any code path that reaches profile
parsing.

(Previously: `hyprctl` was in the unconditional preflight list; now the
compositor binary requirement is decided by detection.)

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

- GIVEN all required binaries on `PATH` (including the detected compositor's CLI)
- WHEN the engine starts
- THEN it proceeds past preflight without printing a missing-command message

#### Scenario: No compositor CLI present no longer aborts at preflight

- GIVEN a host with neither `hyprctl` nor `niri` on `PATH`
- WHEN the engine starts and detection sets `COMPOSITOR=none`
- THEN preflight does NOT exit `127` for a compositor binary; the engine proceeds in none mode
- AND (@test `backends.bats::none_mode_skips_compositor_require_cmd`)
