# Delta for hidpi-scaling

## ADDED Requirements

### Requirement: Pure-bash HiDPI math (no bc, no python3)

The engine MUST compute the desktop scale percentage WITHOUT invoking `bc` or
`python3`. Scale extraction from `hyprctl monitors -j` MUST use `jq` (already a
required dependency). Conversion from the float `scale` to an integer percentage
MUST be performed via bash arithmetic on integer-stripped values (e.g. strip the
dot from `1.5` to compare `150` against `100`), or via `jq` integer math. The
engine MUST NOT spawn `bc` or `python3` on any code path.

#### Scenario: HiDPI monitor receives /scale-desktop on bc-less box

- GIVEN a monitor whose `hyprctl monitors -j` reports `scale: 2` AND `bc` is not installed AND `python3` is not installed
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is an array containing `/scale-desktop:200` and `/smart-sizing`
- AND neither `bc` nor `python3` was invoked (verify via `strace -f -e execve`)
- AND (manual-verify: `PATH` with `bc`/`python3` removed; run engine; check log line `Aplicando /scale-desktop:200`)

#### Scenario: Fractional scale rounds to integer percent

- GIVEN a monitor reporting `scale: 1.5`
- WHEN the engine computes the percentage
- THEN `DPI_FLAGS` contains `/scale-desktop:150` (or the documented rounding rule applied)
- AND (manual-verify: temporarily set scale 1.5 in Hyprland; observe the emitted flag)

#### Scenario: Scale of 1 emits no DPI flags

- GIVEN a monitor reporting `scale: 1` (or `1.0`)
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is an empty array and no `/scale-desktop` flag is passed to xfreerdp3

### Requirement: Safe fallback when scale cannot be determined

If the scale cannot be parsed from `hyprctl monitors -j` (missing field, `null`,
non-numeric, or `jq` returns empty), the engine MUST default to `100%` (i.e. no
`/scale-desktop` flag) and MUST log a `WARN`-level entry naming the unparsable
value. The engine MUST NOT abort the session on a scale-parse failure.

#### Scenario: null scale falls back with warning

- GIVEN `hyprctl monitors -j` returns a monitor object with `scale: null`
- WHEN the engine computes DPI flags
- THEN `DPI_FLAGS` is empty (treated as 100%)
- AND a `WARN` log line is written naming `null` as the unparsable scale
- AND the session proceeds to launch xfreerdp3
- AND (manual-verify: pipe a stub `hyprctl` returning `scale: null`; check log for WARN and confirm session launch)

#### Scenario: Non-numeric scale falls back with warning

- GIVEN `hyprctl monitors -j` returns `"scale": "auto"`
- WHEN the engine computes DPI flags
- THEN the engine falls back to 100% with a `WARN` log line and does NOT abort
