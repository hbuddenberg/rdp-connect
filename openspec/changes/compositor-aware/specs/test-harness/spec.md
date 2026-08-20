# Delta for test-harness

## ADDED Requirements

### Requirement: Compositor mocks (PATH-shadowed function fakes)

The bats suite MUST mock compositor CLIs as bash functions shadowing PATH —
`hyprctl()` (the established `hidpi.bats` strategy) and its twin `niri()`
emitting fixture JSON (`monitors -j`, `msg --json outputs`,
`msg --json workspaces`, argv capture for actions). A both-missing case MUST
exist. The full compositor matrix (hypr, niri, none) MUST pass in CI without
any real compositor present.

#### Scenario: Backends exercised via function mocks

- GIVEN `backends.bats` and `niri-api.bats` defining PATH-shadowed `hyprctl()`/`niri()` mocks over fixture JSON
- WHEN `bats tests/` runs on a host with no compositor CLIs
- THEN detection, canonical-shape, and dispatch cases for all three backends pass
- AND (@test `backends.bats::*` meta: suite passes with `command -v hyprctl niri` both failing)

#### Scenario: Both-missing case covers the none backend

- GIVEN tests defining neither mock (and no real CLI on PATH)
- WHEN detection-related cases run
- THEN the `none` fallback path is exercised and passes
- AND (@test `backends.bats::detect_none_when_no_valid_json`)

#### Scenario: CI runs the compositor matrix with no compositor

- GIVEN `ubuntu-latest` CI with no hyprland/niri installed
- WHEN `make ci` runs
- THEN every backend case is green (the matrix requires no real compositor)
- AND (@test `harness.bats::ci_workflow_well_formed` unchanged; `make test` green locally with compositor CLIs absent from PATH)

### Requirement: Structural invariant — compositor IPC only in lib backends

The engine (`engine/rdp-connect`) MUST contain no raw `hyprctl` or
`niri msg` invocations outside the lib backend functions. A structural suite
(`hyprland-api.bats` plus its new twin `niri-api.bats`) MUST enforce this by
scanning the engine source.

#### Scenario: Engine source has zero raw compositor IPC sites

- GIVEN the engine after migration
- WHEN the structural scan greps `engine/rdp-connect` for `hyprctl`/`niri msg` call forms
- THEN zero matches exist outside lib-sourced backend functions
- AND (@test `niri-api.bats::no_raw_compositor_ipc_in_engine`)

#### Scenario: niri-api.bats twins hyprland-api.bats

- GIVEN `tests/niri-api.bats` alongside `tests/hyprland-api.bats`
- WHEN the structural assertions run
- THEN niri dispatch forms (`--window-id`, action names) are asserted and eval-style/undocumented call forms are rejected
- AND (@test `niri-api.bats::*`)
