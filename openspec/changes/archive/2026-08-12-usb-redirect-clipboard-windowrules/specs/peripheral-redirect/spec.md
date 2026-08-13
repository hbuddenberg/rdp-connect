# Delta for peripheral-redirect

> **New capability** (no prior spec under `openspec/specs/`). At archive, the
> `## ADDED Requirements` below seed `openspec/specs/peripheral-redirect/spec.md`.
> Scope: F1 USB + drive redirect toggles, F2-a clipboard parity toggle — per
> proposal `usb-redirect-clipboard-windowrules`. Pairs with the MODIFIED deltas
> in `engine-robustness` (argv + probe mechanism) and `engine-security`
> (allowlist + blast-radius posture).

## ADDED Requirements

### Requirement: USB redirect is opt-in and per-device

USB device redirect MUST be opt-in per profile and MUST default to OFF (no
`/usb:` token emitted for a profile that omits `USB_REDIRECT`). When enabled,
the engine MUST emit only the explicit per-device form `/usb:id:<vid>:<pid>`.
The `/usb:auto` form MUST NOT be emitted — neither as a default nor as an
opt-in within this change (deferred to a separate security-reviewed change).
Multiple devices MUST be accepted in `USB_DEVICE_IDS` using `#` as the device
separator, and each device id MUST match `<hex4>:<hex4>` (exactly four hex
digits per segment). Non-conformant values MUST be rejected loudly (non-zero
exit, message naming the offending value) and MUST NEVER reach the `xfreerdp3`
argv.

#### Scenario: Default profile emits no USB flag

- GIVEN a profile with no `USB_REDIRECT` key (or `USB_REDIRECT=""`)
- WHEN `build_usb_flags` constructs the USB flag array
- THEN the array is empty and the xfreerdp3 argv contains no `/usb:` token
- AND (@test `peripheral-flags.bats::usb_default_off_emits_no_flag`)

#### Scenario: Valid single device emits /usb:id:<vid>:<pid>

- GIVEN `USB_REDIRECT=1` and `USB_DEVICE_IDS=0781:5580`
- WHEN `build_usb_flags` runs
- THEN the array yields `/usb:id:0781:5580`
- AND (@test `peripheral-flags.bats::usb_single_device_valid`)

#### Scenario: Invalid device id is rejected before xfreerdp3

- GIVEN `USB_REDIRECT=1` and `USB_DEVICE_IDS=0781:558` (3-hex-digit pid)
- WHEN `build_usb_flags` validates the id
- THEN the function returns non-zero naming `0781:558` as malformed
- AND no `/usb:` token is appended to the argv
- AND (@test `peripheral-flags.bats::usb_invalid_device_id_rejected`)

#### Scenario: Multi-device value passes validation

- GIVEN `USB_REDIRECT=1` and `USB_DEVICE_IDS=0781:5580#046d:c52b`
- WHEN `build_usb_flags` validates the id against `^([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}))*$`
- THEN validation passes (both pairs are well-formed) and the function proceeds to render
- AND the rendered multi-device flag string conforms to the xfreerdp3 3.30.0 `/help` grammar (exact per-segment form pinned in design)
- AND (@test `peripheral-flags.bats::usb_multi_device_validates`)

### Requirement: Drive redirect default-on and togglable

Drive redirect MUST default to ON, preserving the current `/drive:compartido,$SHARE_DIR`
behavior so existing profiles connect identically (zero regression).
`DRIVE_REDIRECT=0` MUST omit the `/drive:` token entirely. `SHARE_DIR` MUST
default to `$HOME/Compartido` and MUST be overridable per profile. The
`/drive:hotplug,*` form MUST NOT be emitted (see blast-radius requirement in
`engine-security`).

#### Scenario: Default profile preserves the drive flag

- GIVEN a profile with no `DRIVE_REDIRECT` key
- WHEN `build_drive_flags` runs
- THEN the array yields `/drive:compartido,<SHARE_DIR>` with `SHARE_DIR` resolving to `$HOME/Compartido`
- AND (@test `peripheral-flags.bats::drive_default_on_preserved`)

#### Scenario: DRIVE_REDIRECT=0 omits the drive token

- GIVEN `DRIVE_REDIRECT=0`
- WHEN `build_drive_flags` runs
- THEN the array is empty and the argv contains no `/drive:` token
- AND (@test `peripheral-flags.bats::drive_off_omits_flag`)

#### Scenario: Custom SHARE_DIR is honored

- GIVEN `DRIVE_REDIRECT=1` and `SHARE_DIR=/data/shared`
- WHEN `build_drive_flags` runs
- THEN the array yields `/drive:compartido,/data/shared`
- AND (@test `peripheral-flags.bats::drive_custom_share_dir`)

### Requirement: Clipboard toggle

The `+clipboard` flag MUST stay ON by default (parity with current behavior;
this change's deliverable is toggleability and visibility, not a default
change). `CLIPBOARD_SYNC=0` MUST remove `+clipboard` from the argv (explicit
opt-out). Clipboard *direction* control is out of scope for this slice and is
deferred to a follow-up change (it requires the `direction-to:`/`direction-from:`
sub-args of `/clipboard:`, not a standalone flag).

#### Scenario: Default keeps +clipboard

- GIVEN a profile with no `CLIPBOARD_SYNC` key
- WHEN `build_clipboard_flags` runs
- THEN the array yields `+clipboard`
- AND (@test `peripheral-flags.bats::clipboard_default_on`)

#### Scenario: CLIPBOARD_SYNC=0 removes +clipboard

- GIVEN `CLIPBOARD_SYNC=0`
- WHEN `build_clipboard_flags` runs
- THEN the array is empty and the argv contains no `+clipboard` token
- AND (@test `peripheral-flags.bats::clipboard_off_omits_flag`)

### Requirement: Peripheral allowlist keys and pre-init

The five peripheral keys — `USB_REDIRECT`, `USB_DEVICE_IDS`, `DRIVE_REDIRECT`,
`SHARE_DIR`, `CLIPBOARD_SYNC` — MUST be accepted by the
profile allowlist (see MODIFIED requirement in `engine-security`) and MUST be
pre-initialized to their default/empty values at engine startup BEFORE any read,
so `set -u` never aborts on a profile that omits them. Persistence of toggled
values MUST go through `set_profile_key` (the established audio-toggle pattern
at engine L489-490).

#### Scenario: Profile omitting the keys connects without abort

- GIVEN a legacy profile written before this change (none of the five keys present)
- WHEN the engine starts under `set -euo pipefail`
- THEN pre-init fills the five keys to defaults and the engine proceeds (no "unbound variable")
- AND (@test `peripheral-flags.bats::legacy_profile_pre_init_no_abort`)

#### Scenario: Menu toggle persists across launches

- GIVEN a profile where the user toggled USB redirect ON via the pre-connect menu
- WHEN the engine persists via `set_profile_key USB_REDIRECT 1` and is relaunched
- THEN the next launch reads `USB_REDIRECT=1` and the menu mark reflects ON
- AND (manual-verify: `rules.apply.manual_check` — toggle in menu, relaunch, confirm mark)

### Requirement: Peripheral capability-gate decision matrix

The startup capability probe (see ADDED requirement in `engine-robustness` for
the mechanism) MUST apply this per-flag decision matrix when the installed
`xfreerdp3` build lacks support for a peripheral flag:

| Flag | Default | If unsupported by the build |
|---|---|---|
| `/usb:` | OFF (opt-in) | silent-skip; session proceeds; NOTICE logged |
| `/drive:` | ON | HARD-FAIL with actionable message |
| `+clipboard` | ON | HARD-FAIL with actionable message |

Drive and clipboard both hard-fail because they are default-ON: silently
dropping either would be a hidden behavior change on every existing profile.
USB is silent-skip because it is opt-in (absent ⟹ current behavior).

#### Scenario: Build without /usb: silently skips USB

- GIVEN a build whose `/help` omits `/usb:` AND `USB_REDIRECT=1`
- WHEN the engine reaches the gate
- THEN the `/usb:` token is dropped, a NOTICE is logged, and the session proceeds
- AND (@test `peripheral-flags.bats::gate_usb_unsupported_silent_skip`)

#### Scenario: Build without /drive: hard-fails

- GIVEN a build whose `/help` omits `/drive:` (drive is default-on)
- WHEN the engine reaches the gate
- THEN the engine exits non-zero with a message naming `/drive:` as required for the default configuration
- AND (@test `peripheral-flags.bats::gate_drive_unsupported_hard_fail`)

#### Scenario: Build without clipboard hard-fails

- GIVEN a build whose `/help` omits `clipboard` (clipboard is default-on)
- WHEN the engine reaches the gate
- THEN the engine exits non-zero with a message naming `+clipboard` as required for the default configuration
- AND (@test `peripheral-flags.bats::gate_clipboard_unsupported_hard_fail`)

#### Scenario: Build with all three proceeds with configured flags

- GIVEN a build whose `/help` mentions `/usb:`, `/drive:`, and `/clipboard`
- WHEN the engine reaches the gate
- THEN every configured peripheral flag is emitted (no silent drop)
- AND (manual-verify: `rules.apply.manual_check` against xfreerdp3 3.30.0)

### Requirement: Peripheral FLAGS-array construction contract

`USB_FLAGS`, `DRIVE_FLAGS`, and `CLIPBOARD_FLAGS` MUST be bash arrays built by
pure lib functions (`build_usb_flags`, `build_drive_flags`, `build_clipboard_flags`
— mirroring `compute_dpi_flags` / `build_mon_flags`, unit-testable in isolation)
and expanded at the argv-assembly site as `"${USB_FLAGS[@]}"`,
`"${DRIVE_FLAGS[@]}"`, `"${CLIPBOARD_FLAGS[@]}"` with NO `-` suffix on any
expansion. Empty arrays MUST expand to nothing under `set -u` without injecting
a phantom empty-string argument (the historical `DPI_FLAGS`/`SOUND_FLAGS`/
`MON_FLAGS` gotcha — see `tests/freerdp3-flags.bats`).

#### Scenario: Empty peripheral arrays add no phantom arg

- GIVEN USB off, drive off, clipboard off (all three arrays empty)
- WHEN the argv site expands the three arrays under `set -u`
- THEN the expansion yields nothing and the argv contains no empty-string element
- AND (@test `peripheral-flags.bats::empty_peripheral_arrays_no_phantom_arg`)

#### Scenario: Flag-build functions are pure and unit-testable

- GIVEN `lib/rdp-common.bash` sourced in a bats fixture (no engine globals, no `xfreerdp3`/`hyprctl`)
- WHEN each `build_*_flags` function is called with fixture profile values
- THEN it returns a bash array deterministically with no side effects on the engine environment
- AND (@test `peripheral-flags.bats::build_fns_are_pure`)
