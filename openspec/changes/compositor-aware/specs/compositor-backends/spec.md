# compositor-backends Capability Spec

> NEW capability from `compositor-aware`. A detection step plus a backend layer
> in `lib/rdp-common.bash` expose ONE canonical monitor model and dispatch
> wrappers for hyprland and niri, with a degraded `none` backend when neither
> compositor answers. Hyprland observable behavior MUST remain unchanged.
> Password path is out of scope: nothing here MAY interpose between the
> password pipe and the `xfreerdp3` argv (engine-security: no delta).

## Requirements

### Requirement: Compositor detection (probe-decided, env-hinted)

The engine MUST set `COMPOSITOR` ∈ {`hypr`, `niri`, `none`} before any monitor
query. Detection MUST order candidate probes using environment hints
(`HYPRLAND_INSTANCE_SIGNATURE`, `NIRI_SOCKET`, `XDG_CURRENT_DESKTOP`) but MUST
decide ONLY on a connectivity + JSON-validity probe (`hyprctl monitors -j` /
`niri msg --json outputs`, each piped through `jq -e .`). Exit code alone MUST
NOT decide — both CLIs return rc=1 with plain text on the wrong compositor. If
no probe yields valid JSON, the engine MUST set `COMPOSITOR=none`, log exactly
one WARN naming the mode, and continue. Detection MUST NOT abort the engine.

#### Scenario: Niri session detected via JSON probe

- GIVEN a PATH-shadowed `niri()` mock emitting valid outputs JSON and a `hyprctl()` mock emitting rc=1 plain text
- WHEN detection runs
- THEN `COMPOSITOR=niri`
- AND (@test `backends.bats::detect_niri_via_json_probe`)

#### Scenario: Hyprland session detected via JSON probe

- GIVEN a `hyprctl()` mock emitting valid monitors JSON and a `niri()` mock failing rc=1
- WHEN detection runs
- THEN `COMPOSITOR=hypr`
- AND (@test `backends.bats::detect_hypr_via_json_probe`)

#### Scenario: Both CLIs present, neither compositor answering

- GIVEN both mocks return rc=1 plain text (wrong-compositor responses)
- WHEN detection runs under `set -euo pipefail`
- THEN no jq parse crash occurs, `COMPOSITOR=none`, one WARN is logged, engine continues
- AND (@test `backends.bats::detect_none_when_no_valid_json`)

#### Scenario: Env hint never decides alone

- GIVEN `XDG_CURRENT_DESKTOP=niri` but the niri probe yields invalid JSON
- WHEN detection runs
- THEN niri is rejected on probe evidence and the result is `hypr` or `none` per the probes
- AND (@test `backends.bats::env_hint_does_not_decide`)

### Requirement: Canonical monitor model (logical coordinates)

The lib MUST expose `get_monitors_json()` emitting ONE canonical array
`[{id, desc, x, y, w, h, scale, ws_ref}]` in LOGICAL coordinates for every
backend. `id` is the backend's stable selection token; `ws_ref` is the output's
active workspace reference. Array ordering MUST be deterministic and MUST
preserve the engine's established ordering semantics for hypr; for niri's
object-keyed outputs the adapter MUST impose a documented deterministic order
(sort by logical `x`, then `y`).

#### Scenario: Hypr physical fixture converts to logical

- GIVEN a hypr `monitors -j` fixture with width 3840, height 2160, scale 2
- WHEN the hypr adapter emits canonical output
- THEN `w=1920`, `h=1080`, `scale=2` (physical→logical division applied once, inside the adapter)
- AND (@test `backends.bats::hypr_fixture_to_canonical_logical`)

#### Scenario: Niri object-keyed outputs parsed to canonical

- GIVEN a `niri msg --json outputs` fixture keyed by output name with `logical.{x,y,width,height,scale}`
- WHEN the niri adapter emits canonical output
- THEN logical values pass through unconverted, `id` equals the output name, ordering is by logical x then y
- AND (@test `backends.bats::niri_fixture_to_canonical`)

#### Scenario: ws_ref derived from niri workspaces

- GIVEN outputs fixture plus a `niri msg --json workspaces` fixture where the focused workspace is on output `DP-1`
- WHEN canonical output is built
- THEN the `DP-1` entry's `ws_ref` names that workspace
- AND (@test `backends.bats::niri_ws_ref_from_workspaces`)

### Requirement: Backend dispatch contract

Every compositor mutation (float, resize, move, fullscreen, focus restore,
move-to-workspace) MUST go through lib dispatch wrappers taking a window
reference plus LOGICAL geometry. Under `COMPOSITOR=none` each wrapper MUST log
WARN and no-op — never abort. Wrappers MUST NOT gain `|| true` around `jq`,
file tests, or security-relevant calls. The adapter layer MUST NOT interpose
between the password pipe and the `xfreerdp3` argv.

#### Scenario: Dispatch no-ops with WARN under none

- GIVEN `COMPOSITOR=none`
- WHEN any dispatch wrapper is invoked
- THEN it logs WARN, performs no IPC, returns success to the caller, and the engine continues
- AND (@test `backends.bats::dispatch_noop_warn_under_none`)

#### Scenario: Hypr dispatch forms unchanged (regression)

- GIVEN `COMPOSITOR=hypr` with a `hyprctl()` argv-capturing mock
- WHEN wrappers dispatch float/resize/move/fullscreen/focus/move-to-ws
- THEN emitted argv match the pre-change hyprctl forms exactly
- AND (@test `hyprland-api.bats` regression suite stays green)

### Requirement: Hypr adapter owns physical→logical conversion

The physical→logical `/scale` conversion MUST exist ONLY inside the hypr
adapter. The engine and all canvas math MUST operate exclusively on canonical
logical values. Hypr selection semantics (numeric detection-order ids in
`MONITOR_ID`/`MONITOR_ORDER`) MUST survive verbatim.

#### Scenario: /scale monitor conversion appears only in the hypr adapter

- GIVEN the deployed engine and lib
- WHEN structural tests scan for monitor-geometry scale division
- THEN no `/scale` conversion exists outside the lib hypr backend functions
- AND (@test `niri-api.bats::scale_conversion_only_in_hypr_adapter` — structural)

#### Scenario: Existing hypr monitor suites stay green on canonical shape

- GIVEN the pre-existing monitor suites (monitor-config, monitor-mode, monitor-order-by-description, multi-position, span-mode, expand-mode) migrated to canonical fixtures
- WHEN `make ci` runs
- THEN every pre-existing expectation passes unmodified (zero Hyprland behavior change)
- AND (@test `harness.bats::make_ci_green`)

### Requirement: Niri adapter contract

The niri adapter MUST parse the object-keyed `outputs` JSON, pass `logical.*`
through (already logical), and read DPI scale from `logical.scale` (effective) —
NEVER the top-level configured `scale`, which MAY be `null`. The selection
token is the output NAME (e.g. `DP-2`); `desc` MUST be `make model serial`,
disambiguating identical models by serial. Workspace moves MUST use
`move-window-to-workspace <ref> --window-id <id>` (the flag is `--window-id`,
NOT `--id`). Numeric `PREFERRED_WS` values pass through as references; named
workspaces are documented as the niri-idiomatic value.

#### Scenario: Configured scale null, logical.scale wins

- GIVEN an outputs fixture with top-level `scale: null` and `logical.scale: 2`
- WHEN canonical output is built
- THEN `scale=2`
- AND (@test `backends.bats::niri_logical_scale_not_configured`)

#### Scenario: Identical models disambiguated by serial

- GIVEN an outputs fixture with two identical make/model monitors differing only by serial
- WHEN canonical output is built
- THEN their `desc` values are distinct (serial-qualified)
- AND (@test `backends.bats::niri_serial_disambiguation`)

#### Scenario: move-to-workspace uses the --window-id flag

- GIVEN a matched window id `42` and workspace ref under `COMPOSITOR=niri`
- WHEN the move-to-ws wrapper dispatches
- THEN the `niri()` mock receives `msg action move-window-to-workspace <ref> --window-id 42`
- AND (@test `niri-api.bats::move_window_to_workspace_uses_window_id_flag`)

### Requirement: Degraded none backend

Under `COMPOSITOR=none` the engine MUST: skip workspace pinning, geometry
dispatch, and the pre-connect monitor menu (mirroring the no-wofi skip); treat
monitor count as 1 (`/f`); default DPI to the existing 100% WARN path; and
still launch `xfreerdp3` with the full security pipeline (`/from-stdin:force`
gate, lockfile, setsid re-exec). Expand mode MUST be documented as disabled
under none.

#### Scenario: none mode builds /f at 100% DPI

- GIVEN `COMPOSITOR=none`
- WHEN monitor and DPI flags are built
- THEN `MON_FLAGS` expands to `/f` and `DPI_FLAGS` is empty with one WARN (100%)
- AND (@test `backends.bats::none_mode_f_100pct`)

#### Scenario: none mode skips menu and pinning without abort

- GIVEN `COMPOSITOR=none` and a profile with `PREFERRED_WS=3`
- WHEN the engine runs to launch
- THEN no pre-connect menu is attempted, no ws dispatch fires, and the launch path is reached
- AND (@test `backends.bats::none_mode_skips_menu_and_pin`)

#### Scenario: LIVE — neither compositor, real launch and cleanup

- GIVEN a live session with neither compositor answering
- WHEN a real profile connects
- THEN xfreerdp3 launches fullscreen and exit leaves no orphaned process
- AND (LIVE checklist artifact: none-mode item)

### Requirement: Niri expand-mode live-verification gate

Niri expand positioning MUST NOT ship on unverified semantics. Before expand
dispatch to niri is wired, a live verification on a real niri session MUST
confirm: (a) `move-floating-window` absolute-vs-delta `-x/-y` semantics,
(b) global-logical vs output-local coordinate space, (c) the XWayland
`app_id` ↔ `/wm-class` mapping. If any check fails or cannot run, expand MUST
use the documented degraded mode (fullscreen on the selected output) with a
WARN — never silent breakage.

#### Scenario: LIVE — gate executed before niri expand wiring

- GIVEN a live niri session
- WHEN the apply-time verification runs the three probes
- THEN the observed semantics are recorded and expand is wired to them OR degraded expand is selected explicitly
- AND (LIVE checklist artifact: expand-gate item; task order enforces gate BEFORE wiring)

#### Scenario: Degraded expand is the explicit fallback

- GIVEN verification shows positioning is unreliable
- WHEN a profile requests expand under niri
- THEN the window launches fullscreen on the selected output with a WARN naming degraded expand
- AND (@test `backends.bats::niri_degraded_expand_fallback`)

### Requirement: Live E2E checklist artifact (both compositors)

The change MUST ship a live checklist artifact, executed as done criteria,
covering BOTH compositors: (1) profile connect from the user's real log
(`ti-partner`, `DISABLE_DPI=1` path), (2) monitor canvas per mode, (3)
`PREFERRED_WS` pinning, (4) DPI flags, (5) expand or documented degraded
expand, (6) cleanup leaves no orphaned `xfreerdp3` on exit.

#### Scenario: LIVE — checklist executed on niri

- GIVEN the user's live niri/uwsm session
- WHEN the checklist runs end to end
- THEN all six items pass on niri and results are recorded in the artifact
- AND (LIVE checklist artifact: niri column)

#### Scenario: LIVE — checklist executed on Hyprland

- GIVEN a Hyprland session (via session toggle)
- WHEN the checklist runs end to end
- THEN all six items pass with zero behavior change versus pre-change engine
- AND (LIVE checklist artifact: hyprland column)
