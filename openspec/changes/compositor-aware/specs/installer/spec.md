# Delta for installer

## MODIFIED Requirements

### Requirement: Declared dependency list with missing-dep install

The installer MUST declare a single dependency list mapping each package to
its name on each supported manager (e.g. `freerdp` on Arch → `freerdp3-x11` on
Debian → `freerdp` on Fedora). Before deploying engine files, the installer
MUST check each dependency and install any missing one via the detected
package manager. The declared set is: FreeRDP3 (with `/from-stdin:force`),
`jq`, `util-linux` (provides `flock`), `libnotify` (provides `notify-send`),
`wofi` OR `rofi`, a compositor CLI — `hyprland` OR `niri` — and `shellcheck`.
`bc` and `python3` MUST NOT be in the dependency list (the hidpi-scaling
capability removed them).

The compositor dependency is satisfied when EITHER compositor CLI is installed
or installable. On hosts where a compositor package is unavailable from the
detected manager's archives (e.g. `hyprland` not in Debian main, `niri`
unavailable), the installer MUST warn loudly but MUST NOT fail the install for
that package. When NEITHER compositor CLI can be provided, the installer MUST
still complete with a warning naming the degraded none mode (headless fallback
parity) — the engine degrades at runtime per compositor-backends rather than
failing preflight.

(Previously: `hyprland` was a hard single-package entry with a
Debian-specific warning; the dependency is now an OR-pair with a generalized
warning and an install-anyway headless fallback.)

#### Scenario: Missing jq is installed before engine deploy

- GIVEN a clean host where `jq` is not installed
- WHEN the installer runs
- THEN it installs `jq` via the detected package manager BEFORE writing `~/.local/bin/rdp-connect`
- AND (manual-verify: `command -v jq` succeeds after a clean run on a throwaway container)

#### Scenario: wofi or rofi satisfies the launcher dependency

- GIVEN a host with `rofi` installed but not `wofi`
- WHEN the installer runs
- THEN it does NOT attempt to install `wofi` (the OR is satisfied) and proceeds

#### Scenario: Niri-only host satisfies the compositor dependency

- GIVEN a host with `niri` installed and `hyprland` absent
- WHEN the installer runs
- THEN it does NOT attempt to install `hyprland` (the compositor OR is satisfied by `niri`) and proceeds to deploy
- AND (@test `installer-backends.bats::niri_only_satisfies_compositor_dep` — spy on the package manager; assert no hyprland install attempt)

#### Scenario: Neither compositor CLI still installs with a warning

- GIVEN a host where neither `hyprland` nor `niri` is installed or installable
- WHEN the installer runs
- THEN the install completes (engine deployed, smoke test runs, manifest written) AND a warning naming the degraded none mode is printed
- AND (@test `installer-backends.bats::no_compositor_installs_with_warn`)
