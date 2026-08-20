# Delta for hidpi-scaling

## MODIFIED Requirements

### Requirement: Pure-bash HiDPI math (no bc, no python3)

The engine MUST compute the desktop scale percentage WITHOUT invoking `bc` or
`python3`. Scale extraction MUST read the backend-reported logical `scale`
from the canonical monitor model (see compositor-backends); backend-specific
reads (hypr `monitors -j .[0].scale`; niri `logical.scale` of the
canonically-first output) are adapter-internal and MUST use `jq` (already a
required dependency). Conversion from the float `scale` to an integer
percentage MUST be performed via bash arithmetic on integer-stripped values
(e.g. strip the dot from `1.5` to compare `150` against `100`), or via `jq`
integer math. The engine MUST NOT spawn `bc` or `python3` on any code path.

(Previously: scale was extracted directly from `hyprctl monitors -j`
`.[0].scale`; the source is now the backend-neutral canonical shape.)

#### Scenario: HiDPI monitor receives /scale-desktop on bc-less box

- GIVEN a canonical monitor with logical `scale: 2` produced by the hypr adapter (physical fixture) AND `bc` and `python3` are not installed
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is an array containing `/scale-desktop:200` and `/smart-sizing`
- AND neither `bc` nor `python3` was invoked
- AND (@test `hidpi.bats::hidpi_scale_200_via_canonical` with PATH-shadowed `hyprctl()` mock)

#### Scenario: Niri logical.scale drives the same flags

- GIVEN a canonical monitor with logical `scale: 2` produced by the niri adapter (`logical.scale: 2`, configured `scale: null`, three outputs so ordering matters)
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` contains `/scale-desktop:200` — identical output to the hypr case
- AND (@test `hidpi.bats::niri_logical_scale_same_flags` with PATH-shadowed `niri()` mock)

#### Scenario: Fractional scale rounds to integer percent

- GIVEN a canonical monitor reporting `scale: 1.5`
- WHEN the engine computes the percentage
- THEN `DPI_FLAGS` contains `/scale-desktop:150` (or the documented rounding rule applied)
- AND (@test `hidpi.bats::fractional_scale_150`)

#### Scenario: Scale of 1 emits no DPI flags

- GIVEN a canonical monitor reporting `scale: 1` (or `1.0`) from either backend
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is an empty array and no `/scale-desktop` flag is passed to xfreerdp3
- AND (@test `hidpi.bats::scale_one_no_flags`)

### Requirement: Safe fallback when scale cannot be determined

If the scale cannot be parsed from the canonical monitor model (missing field,
`null`, non-numeric, or `jq` returns empty), the engine MUST default to `100%`
(i.e. no `/scale-desktop` flag) and MUST log a `WARN`-level entry naming the
unparsable value. The engine MUST NOT abort the session on a scale-parse
failure. Under `COMPOSITOR=none` there is no backend-reported scale; the same
`100%` default with one WARN MUST apply.

(Previously: fallback text named `hyprctl monitors -j` as the parse source;
now generalized to the canonical model plus the none backend.)

#### Scenario: null scale falls back with warning

- GIVEN a canonical monitor object with `scale: null` (e.g. a niri adapter fixture where `logical.scale` is missing)
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is empty (treated as 100%)
- AND a `WARN` log line is written naming `null` as the unparsable scale
- AND the session proceeds to launch xfreerdp3
- AND (@test `hidpi.bats::null_scale_fallback`)

#### Scenario: Non-numeric scale falls back with warning

- GIVEN a canonical monitor with `"scale": "auto"`
- WHEN the engine computes DPI flags
- THEN the engine falls back to 100% with a `WARN` log line and does NOT abort
- AND (@test `hidpi.bats::non_numeric_scale_fallback`)

#### Scenario: none backend defaults to 100%

- GIVEN `COMPOSITOR=none` (no backend-reported scale exists)
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is empty (100% default) with exactly one WARN
- AND the launch path proceeds (per the none-backend requirement in compositor-backends)
- AND (@test `backends.bats::none_mode_f_100pct`)
