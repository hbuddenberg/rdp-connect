# Delta for engine-robustness

> Pairs with the NEW `peripheral-redirect` spec. Two changes: (1) the argv-
> assembly "Flag arrays instead of string interpolation" requirement is MODIFIED
> to cover the three peripheral arrays and to harden the no-suffix expansion
> invariant; (2) a new ADDED requirement covers the startup capability-probe
> mechanism for peripheral flags. The `/from-stdin:force` runtime gate and the
> password path are structurally untouched (R4 — additive only).

## MODIFIED Requirements

### Requirement: Flag arrays instead of string interpolation

`MON_FLAGS`, `DPI_FLAGS`, `USB_FLAGS`, `DRIVE_FLAGS`, and `CLIPBOARD_FLAGS`
MUST be declared as bash arrays and expanded with the quoted-safe form
`"${MON_FLAGS[@]}"` / `"${DPI_FLAGS[@]}"` / `"${USB_FLAGS[@]}"` /
`"${DRIVE_FLAGS[@]}"` / `"${CLIPBOARD_FLAGS[@]}"` — NO `-` suffix on any
expansion. The suffix form `"${ARR[@]-}"` injects a phantom empty-string
argument that `xfreerdp3` rejects; it MUST NOT be used on any flag array.
The engine MUST NOT build any flag set by string concatenation or unquoted
`$VAR` interpolation into the `xfreerdp3` command line. Empty arrays MUST
expand to nothing under `set -u` without raising "unbound variable". The
three peripheral arrays MUST be built by the pure lib functions named in the
`peripheral-redirect` spec and inserted additively at the argv-assembly site;
the `/from-stdin:force` line MUST remain structurally unmoved (R4 regression
guard — new expansions are inserted between existing expansions, never
displacing the credential-pipe line).

(Previously: covered `MON_FLAGS` and `DPI_FLAGS` only; named the `"${ARR[@]-}"`
suffix form as the quoted-safe expansion; peripheral arrays were not in scope.
This delta corrects the suffix form to the no-suffix `"${ARR[@]}"` invariant
documented in CLAUDE.md and enforced by `tests/freerdp3-flags.bats`, and
extends the array set to include the three peripheral arrays.)

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
- WHEN the engine expands `"${DPI_FLAGS[@]}"` under `set -u`
- THEN the expansion yields nothing and the engine does NOT abort with "unbound variable"
- AND (manual-verify: run with scale=1; confirm `set -e` engine still launches xfreerdp3)

#### Scenario: Peripheral arrays expand with no phantom empty arg

- GIVEN USB/drive/clipboard arrays built by the lib fns (any combination empty)
- WHEN the argv site expands `"${USB_FLAGS[@]}"`, `"${DRIVE_FLAGS[@]}"`, `"${CLIPBOARD_FLAGS[@]}"` under `set -u`
- THEN no empty-string element is injected into the argv
- AND the `/from-stdin:force` line remains at its established position in the argv (R4)
- AND (@test `peripheral-flags.bats::empty_peripheral_arrays_no_phantom_arg`)

## ADDED Requirements

### Requirement: Peripheral-flag capability probing at startup

The engine's startup capability probe (which already verifies `/from-stdin:force`
support per the dedicated high-risk gate) MUST additionally probe
`xfreerdp3 /help` for `/usb:`, `/drive:`, and `/clipboard` support BEFORE any
peripheral flag is emitted. The probe results MUST feed the per-flag decision
matrix defined in the `peripheral-redirect` spec (USB opt-in ⟹ silent-skip;
drive default-on ⟹ hard-fail; clipboard default-on ⟹ hard-fail). The peripheral probe
MUST NOT alter the `/from-stdin:force` gate's hard-fail-on-missing semantics —
the password-path gate stays primary and unchanged; peripheral probing MUST
never weaken the credential gate. A missing `/from-stdin:force` MUST still
hard-fail the engine regardless of peripheral-flag support.

#### Scenario: Probe extends to peripheral flags

- GIVEN a build whose `/help` mentions `/from-stdin`, `/usb:`, `/drive:`, `/clipboard`
- WHEN the engine starts
- THEN all four probes pass and the engine proceeds to emit configured peripheral flags
- AND (manual-verify: `rules.apply.manual_check` on xfreerdp3 3.30.0)

#### Scenario: Password-path gate stays primary over peripheral probing

- GIVEN a build whose `/help` lacks `/from-stdin:force` (even if `/usb:` etc. are present)
- WHEN the engine starts
- THEN the engine hard-fails on the password-path gate BEFORE evaluating any peripheral flag
- AND (@test `engine-robustness.bats::from_stdin_gate_primary_over_peripheral`)

#### Scenario: Peripheral probe failure follows the decision matrix

- GIVEN a build lacking `/usb:` only, with `USB_REDIRECT=1`
- WHEN the engine starts and reaches the peripheral probe
- THEN USB is silently skipped per the matrix (opt-in ⟹ skip) and the session proceeds without the `/usb:` token
- AND (@test `peripheral-flags.bats::gate_usb_unsupported_silent_skip`)
