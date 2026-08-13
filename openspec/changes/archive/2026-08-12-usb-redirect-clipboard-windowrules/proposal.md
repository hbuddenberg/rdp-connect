# Proposal: usb-redirect-clipboard-windowrules

> **Change**: `usb-redirect-clipboard-windowrules` · **Project**: `rdp-connect` (Bash 5.3, xfreerdp3 3.30.0, Wayland/Hyprland) · **Mode**: hybrid (openspec + engram mirror) · **Date**: 2026-08-11
> **Dependency**: Engram `sdd/usb-redirect-clipboard-windowrules/explore` (obs #11) — source of all verified hook points
> **Scope decision**: This change = **F1 + F2-a only**. F3 (window-not-on-top) and F2-b (host SUPER keybinds) are EXPLICITLY OUT (see below).

## Intent

Users need USB-device and local-storage passthrough as a pre-connect menu option, plus clipboard parity/visibility. Today `/drive:compartido,$HOME/Compartido` is **hardcoded ON** (engine L1108), `+clipboard` is **ON but neither toggleable nor visible** (L1105), and USB/device redirect is **entirely absent**. This change makes all three togglable through the established menu + profile allowlist + FLAGS-array pattern, **defaulting to current behavior so no existing user regresses**.

**Blast radius (config.yaml rule):** the deployed script runs as the user and handles real RDP credentials. Drive/USB redirect lets the **remote host touch local files** — therefore USB is opt-in per profile (never default), drive stays default-on (preserve), and `/usb:auto` / `/drive:hotplug,*` are **never** defaults.

## Scope

### In Scope
- **F1 USB** — `/usb:id:<vid>:<pid>` explicit per-device redirect; opt-in per profile; default OFF
- **F1 Drive** — drive-redirect toggle; **default ON** (preserve L1108); togglable OFF; `SHARE_DIR` configurable (default `$HOME/Compartido`)
- **F2-a Clipboard** — menu toggle only (`CLIPBOARD_SYNC`; default ON keeps `+clipboard`, `CLIPBOARD_SYNC=0` omits it). Direction control is deferred to a follow-up change (requires `direction-to:`/`direction-from:` sub-args of `/clipboard:`, out of scope for slice 1)
- Pre-connect menu entries extending the audio-toggle template (engine L436-437, L489-490)
- Profile allowlist extension (`_PROFILE_KEYS`, lib L33-48) + pre-init (engine L360-361)
- Capability-gate extension (engine L131) probing `/usb:`, `/drive:`, `/clipboard` before emitting
- New `USB_FLAGS` / `DRIVE_FLAGS` / `CLIPBOARD_FLAGS` arrays (SOUND_FLAGS pattern L911-921)
- Optional CLI parity: `--usb`, `--no-drive` (engine L49-63)
- i18n keys (`i18n/{es,en}.env`) + tunables doc (lib L491-516, `template/template.env` L9-19)

### Out of Scope
- **F3 window-not-on-top** → separate change `window-no-top` (independent hyprctl-dispatch + single-mode fullscreen L1013 + canvas-math surface; different regression profile)
- **F2-b host SUPER+X/C/V keybinds** → omarchy `~/.config/hypr/` config; documented as a **follow-up note**, NOT an engine SDD change (out-of-engine coordination)
- `/usb:auto` **as a default** (attack surface — arbitrary device redirect)
- `/drive:hotplug,*` (auto-shares ALL hotplugged drives — prohibited)
- `wl-clipboard` dependency (not needed; `+clipboard` does virtual-channel sync, independent of wl-clipboard)
- Any change to `/from-stdin:force` password path, `setsid --wait` re-exec, or PID lockfile semantics

## Capabilities

> Verified against `openspec/specs/`: `engine-robustness`, `engine-security`, `hidpi-scaling`, `installer`, `instance-locking`, `test-harness`. No `peripheral-redirect` spec exists yet.

### New Capabilities
- `peripheral-redirect`: USB/drive/clipboard toggle semantics — opt-in defaults (USB off, drive on, clipboard on), per-profile persistence, capability gating, FLAGS-array construction, device-id validation. Becomes `openspec/specs/peripheral-redirect/spec.md`.

### Modified Capabilities
- `engine-robustness`: the xfreerdp3 argv-assembly site (L1090-1113) gains `USB_FLAGS`/`DRIVE_FLAGS`/`CLIPBOARD_FLAGS` expansion; the startup capability gate (L131) extends to probe peripheral-flag support before emit.
- `engine-security`: the `_PROFILE_KEYS` allowlist (lib L33-48) extends to accept the new toggle keys (parsed by `parse_env_safe`, never sourced); a new requirement documents the drive/USB blast-radius posture (remote host can touch local files → USB opt-in, drive preserved, hotplug/auto prohibited as defaults).

## Approach

1. **Allowlist + pre-init** — add `USB_REDIRECT USB_DEVICE_IDS DRIVE_REDIRECT SHARE_DIR CLIPBOARD_SYNC` to `_PROFILE_KEYS` (lib L33-48); pre-init all to empty/current at engine L360-361 so `set -u` never aborts.
2. **Pure flag-build fns in lib** — `build_usb_flags`, `build_drive_flags`, `build_clipboard_flags` (mirrors `compute_dpi_flags` / `build_mon_flags`), each returning a bash array. USB device-id validated as `<vid>:<pid>` hex (`#`-separated for multi) before emit.
3. **FLAGS arrays** — built alongside `SOUND_FLAGS` (L911-921); expanded at L1103-1108 as `"${USB_FLAGS[@]}"` / `"${DRIVE_FLAGS[@]}"` / `"${CLIPBOARD_FLAGS[@]}"`. **MUST use `"${ARR[@]}"` — NO `-` suffix** (phantom-empty-arg invariant, `tests/freerdp3-flags.bats`).
4. **Menu toggles** — extend the L436-490 audio-toggle block (`_pm_amark`/`_pm_aline` build, `set_profile_key` persist) with USB/drive/clipboard rows; default marks preserve current behavior.
5. **Capability gate** — extend L131 (`xfreerdp3 /help | grep`) to probe `/usb:` + `/drive:` + `/clipboard`. Silent-skip acceptable for opt-in USB on a build lacking `/usb:`; never hang or reject the session over an optional flag.
6. **Strict-TDD** — red-green-refactor on the lib pure fns (flag construction, device-id validation); engine integration (menu render, xfreerdp3 launch) stays manual-verify per the `engine-robustness` spec footer and `rules.apply.manual_check`.

## Affected Areas

| Area | Impact | Change |
|---|---|---|
| `engine/rdp-connect` L49-63, L360-361, L436-490, L911-921, L1090-1113, L131 | Modified | CLI flags, pre-init, menu toggles, FLAGS arrays, capability gate |
| `lib/rdp-common.bash` L33-48, L473-489, L491-516 | Modified | allowlist keys, `set_profile_key` consumers, tunables doc + 3 new pure fns |
| `i18n/{es,en}.env` | Modified | new `MSG_USB_REDIRECT`, `MSG_DRIVE_REDIRECT`, `MSG_CLIPBOARD_SYNC` keys |
| `template/template.env` L9-19 | Modified | new tunables doc lines |
| `tests/peripheral-flags.bats` (+ harness) | New | USB/drive/clipboard flag construction + device-id validation |

## Risks

| ID | Risk | L | Mitigation |
|---|---|---|---|
| R1 | drive/USB lets remote host touch local files | **High** | USB opt-in default OFF; drive default ON (preserve); `/usb:auto` + `/drive:hotplug,*` NEVER defaults; documented in `engine-security` delta |
| R2 | phantom-empty-arg regression (DPI/SOUND history) | Med | FLAGS arrays expanded `"${ARR[@]}"` no `-` suffix; extend `tests/freerdp3-flags.bats` parity assertion |
| R3 | capability-gate probing fragile / version skew | Med | extend L131 `/help \| grep` pattern; silent-skip for opt-in USB; hard-fail only if a DEFAULT-on flag (`/drive:`) is unsupported |
| R4 | regression adjacent to `/from-stdin` path (L1090) | Med | argv block structurally untouched; new flags are additive, inserted between existing expansions; `/from-stdin:force` line unmoved |
| R5 | strict-TDD on engine integration paths | Med | extract all flag logic as pure lib fns (unit-tested); engine render/launch paths stay manual-verify |
| R6 | `USB_DEVICE_IDS` parsing injection (malformed profile) | Med | validate `<vid>:<pid>` hex via regex in lib; reject non-conformant values loudly (abort, never reach xfreerdp3) |

## Rollback Plan

Flags are **additive**; all toggles default to current behavior (`DRIVE_REDIRECT=1`, `USB_REDIRECT=""`, `CLIPBOARD_SYNC=1`). `git revert` the change restores engine/lib; the installer is **idempotent** — re-running it redeploys the prior files. No data migration: existing profiles simply gain new optional keys (absent ⟹ current behavior). Deployed users are unaffected at every step.

## Dependencies

- xfreerdp3 3.30.0 already installed; `/help` confirms `/usb:`, `/drive:`, `/clipboard` (+ `direction-to:`/`direction-from:`), `/from-stdin` (verified, obs #11)
- Engram obs #11 `sdd/usb-redirect-clipboard-windowrules/explore` — verified hook points

## Open Questions (for spec/design phases)
1. **`/usb:auto` escape hatch** — include as explicit opt-in (`USB_REDIRECT=auto` with security warning) or omit entirely? Recommend: include only if it adds zero new code path beyond the `id:` branch.
2. **`USB_DEVICE_IDS` serialization** — single `vid:pid`, multi as `vid:pid#vid:pid` (xfreerdp3 `#` separator)? Confirm against `/help` grammar.
3. **Capability-gate failure semantics per flag** — hard-fail vs silent-skip matrix (drive default-on may warrant hard-fail; USB opt-in warrants silent-skip).
4. **CLI parity scope** — full `--usb`/`--no-drive` flags, or menu-only for the first slice? (Direction control is deferred — see F2-a note.)
5. **i18n key set** — finalize `MSG_*` keys + es/en strings for the three new menu rows.

## Success Criteria
- [ ] Existing profiles (no new keys) connect **identically**: drive ON, clipboard ON, no USB — zero regression
- [ ] `USB_REDIRECT=1` + `USB_DEVICE_IDS=0781:5580` emits `/usb:id:0781:5580` in the xfreerdp3 argv
- [ ] `DRIVE_REDIRECT=0` omits the `/drive:` line; default profile emits it (preserve)
- [ ] `CLIPBOARD_SYNC=0` would remove `+clipboard`; default keeps it (parity only — toggle is the deliverable, removal is opt-out)
- [ ] `make ci` green; new bats cases cover flag construction + `<vid>:<pid>` validation + phantom-empty-arg parity
- [ ] Capability gate skips the USB flag gracefully on a build lacking `/usb:` (no hang, no reject)
- [ ] No spec-level change to `/from-stdin:force`, `setsid --wait`, or PID lockfile behavior
