# Tasks: usb-redirect-clipboard-windowrules

> TDD-ordered (red→green), `strict_tdd: true`. Engine integration paths are manual-verify per `rules.apply.manual_check`. Anchors verified against engine (1120 L) + lib (517 L).
>
> **Archive final state (2026-08-12):** 12/17 automated tasks complete ✅. 5 manual-verify tasks pending 🔲 (by design — require real xfreerdp3 session). 78/78 tests pass. `size:exception` accepted (~690 lines).

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 270–330 (midpoint ~300) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending (single PR) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Per-task line estimates

| Task | Focus | Files | Δ lines |
|------|-------|-------|---------|
| 1.1–1.2 | allowlist + pre-init | lib L33-48, engine L360-361, tests | ~26 |
| 2.1–2.6 | 3 pure fns (red+green) | lib post-L338, peripheral-flags.bats | ~128 |
| 3.1–3.2 | argv FLAGS wiring (red+green) | engine L911-921, L1090-1113, freerdp3-flags.bats | ~33 |
| 3.3 | capability-gate extension | engine L131, peripheral-flags.bats | ~40 |
| 3.4 | menu rows + i18n + template | engine L436-490, i18n/{es,en}.env, template.env, precheck-menu.bats | ~60 |
| 4.1 | manual-verify checklist | (no code diff) | 0 |

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Phases 1+2 (allowlist + 3 pure lib fns) — fully unit-tested, no engine behavior change | single PR | `bats tests/peripheral-flags.bats tests/parser.bats` | N/A — pure-fn, no xfreerdp3/hyprctl | revert lib + test file only; engine untouched |
| 2 | Phase 3+4 (engine wiring, gate, menu, i18n) — additive, defaults preserve behavior | same PR | `make ci` | `make smoke` + `HOME=$(mktemp -d)` throwaway profile | `git revert` change; installer idempotent re-deploys prior files |

## Phase 1: Foundation — allowlist + pre-init

- [x] 1.1 RED — extend `tests/parser.bats` (or seed `tests/peripheral-flags.bats`) with: `parse_env_safe` accepts the 5 peripheral keys; non-allowlisted key still rejected; legacy profile (no new keys) pre-init under `set -u` does not abort. AC maps to `engine-security`: "Peripheral keys accepted; non-peripheral key still rejected" + `peripheral-redirect`: "Profile omitting the keys connects without abort".
- [x] 1.2 GREEN — add `USB_REDIRECT USB_DEVICE_IDS DRIVE_REDIRECT SHARE_DIR CLIPBOARD_SYNC` to `_PROFILE_KEYS` (lib L33-48); add pre-init `USB_REDIRECT="" USB_DEVICE_IDS="" DRIVE_REDIRECT="" SHARE_DIR="" CLIPBOARD_SYNC=""` at engine L360-361. Test command: `bats tests/parser.bats`. `[ ]` manual-verify: `make smoke`, throwaway profile parses.
- [ ] 1.3 [ ] manual-verify — run installer in throwaway HOME; confirm a legacy profile loads without "unbound variable".

## Phase 2: Pure flag-build fns (red-green per fn)

- [x] 2.1 RED — `tests/peripheral-flags.bats::usb_*`: default-off emits no flag; single `0781:5580` → `/usb:id:0781:5580`; multi `0781:5580#046d:c52b` validates; invalid `0781:558` (3-hex pid) returns non-zero naming value. AC: `peripheral-redirect` USB requirement.
- [x] 2.2 GREEN — implement `build_usb_flags` (lib post-L338) per design L87-100; regex `^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}))*$`; loud reject on malformed (R6); `USB_FLAGS=()` always initialized.
- [x] 2.3 RED — `peripheral-flags.bats::drive_*`: default-on yields `/drive:compartido,<SHARE_DIR>`; `DRIVE_REDIRECT=0` → empty; `SHARE_DIR=/data/shared` honored. AC: `peripheral-redirect` drive requirement.
- [x] 2.4 GREEN — implement `build_drive_flags` (design L105-109); default `$HOME/Compartido`.
- [x] 2.5 RED — `peripheral-flags.bats::clipboard_*`: default yields `("+clipboard")`; `CLIPBOARD_SYNC=0` → empty. AC: `peripheral-redirect` clipboard requirement.
- [x] 2.6 GREEN — implement `build_clipboard_flags` (design L114-118). Also add `peripheral-flags.bats::empty_peripheral_arrays_no_phantom_arg` + `::build_fns_are_pure` (AC: `peripheral-redirect` FLAGS-array contract). Test command: `bats tests/peripheral-flags.bats`.
- [ ] 2.7 [ ] manual-verify — source lib in a REPL; confirm each fn returns the expected array with no engine globals set.

## Phase 3: Engine integration

- [x] 3.1 RED — extend `tests/freerdp3-flags.bats`: assert `"${USB_FLAGS[@]-}"`/`"${DRIVE_FLAGS[@]-}"`/`"${CLIPBOARD_FLAGS[@]-}"` absent from engine code; `/from-stdin:force` + `/sec:nla` still present (R4); `"${USB_FLAGS[@]}"`/`"${DRIVE_FLAGS[@]}"`/`"${CLIPBOARD_FLAGS[@]}"` present. AC: `engine-robustness` MODIFIED "Flag arrays" + "Peripheral arrays expand with no phantom empty arg".
- [x] 3.2 GREEN — call `build_usb_flags`/`build_drive_flags`/`build_clipboard_flags` alongside `SOUND_FLAGS` (engine L911-921); at argv site (L1090-1113) replace literal `+clipboard` (L1105) → `"${CLIPBOARD_FLAGS[@]}"`, replace `/drive:compartido,"$SHARE_DIR"` (L1108) → `"${DRIVE_FLAGS[@]}"`, add `"${USB_FLAGS[@]}"` (additive); `/from-stdin:force` (L1094) unmoved; NO `-` suffix. Test: `bats tests/freerdp3-flags.bats`.
- [ ] 3.3 [ ] manual-verify — `make smoke`; on real host, inspect `ps`/log argv: `/usb:`/`/drive:`/`+clipboard` present when enabled, absent when off.
- [x] 3.4 Capability-gate extension — engine L131: add `xfreerdp3 /help` probes setting `_HAS_USB`/`_HAS_DRIVE`/`_HAS_CLIPBOARD`; apply decision matrix (drive default-on → hard-fail exit 1; clipboard → silent-skip; USB opt-in → silent-skip + `log_event WARN`). `/from-stdin:force` gate stays primary, unchanged. Test: `peripheral-flags.bats::gate_usb_unsupported_silent_skip` + `::gate_drive_unsupported_hard_fail` (stub `xfreerdp3 /help` output); structural grep asserts the 3 probes exist. AC: `peripheral-redirect` gate matrix + `engine-robustness` ADDED probe requirement.
- [ ] 3.5 [ ] manual-verify — on a `/usb:`-less build stub, confirm gate skips gracefully (no hang, no reject); on full xfreerdp3 3.30.0 confirm all flags emit.
- [x] 3.6 Pre-connect menu rows — engine L436-490: extend audio-toggle template with USB (`_pm_umark`/`_pm_uline`), drive (`_pm_dmark`/`_pm_dline`), clipboard (`_pm_cmark`/`_pm_cline`) rows; add toggle branches + `set_profile_key` persist; default marks preserve current behavior (USB off, drive on, clipboard on). Add `MSG_USB_REDIRECT`/`MSG_DRIVE_REDIRECT`/`MSG_CLIPBOARD_SYNC` to `i18n/es.env` AND `i18n/en.env` ATOMICALLY (design L150-153 strings); document 5 tunables in `template/template.env` L9-19. Test: extend `tests/precheck-menu.bats` (3 new mark/line + `set_profile_key` structural assertions). `[ ]` manual-verify: toggle each in menu, relaunch, confirm mark + argv reflect.

## Phase 4: Manual verification

- [ ] 4.1 [ ] manual-verify checklist — `make ci` green; `make smoke` clean; real xfreerdp3 session: confirm `/usb:id:`/`/drive:`/`+clipboard` in argv per profile; **legacy profile zero-regression** (drive ON, clipboard ON, no USB); gate skips gracefully on `/usb:`-less build; `/from-stdin:force` line unmoved (R4); no `"${ARR[@]-}"` form anywhere (R2).
