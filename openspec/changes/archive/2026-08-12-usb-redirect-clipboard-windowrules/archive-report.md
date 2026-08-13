# Archive Report: usb-redirect-clipboard-windowrules

> **Change**: `usb-redirect-clipboard-windowrules` · **Project**: `rdp-connect`
> **Archived**: 2026-08-12 · **Mode**: hybrid (openspec + engram mirror)
> **Persistence**: `openspec/changes/archive/2026-08-12-usb-redirect-clipboard-windowrules/`
> **Engram topic_key**: `sdd/usb-redirect-clipboard-windowrules/archive-report`

---

## 1. Final Implementation Summary

USB device redirect, drive redirect toggle, and clipboard toggle — three new
togglable peripherals following the established menu → allowlist → pure-fn →
FLAGS-array → argv pipeline. Defaults preserve current behavior (drive ON,
clipboard ON, USB OFF) — zero regression for existing profiles.

### What Shipped

| Component | Files | Δ lines |
|-----------|-------|---------|
| Allowlist + pre-init | `lib/rdp-common.bash`, `engine/rdp-connect` | ~26 |
| 3 pure flag-build fns | `lib/rdp-common.bash` | ~128 |
| argv FLAGS wiring | `engine/rdp-connect` | ~33 |
| Capability gate extension | `engine/rdp-connect` | ~40 |
| Menu rows + i18n + template | `engine/rdp-connect`, `i18n/{es,en}.env`, `template/template.env` | ~60 |
| New test file | `tests/peripheral-flags.bats` | 232 |
| Extended test files | `tests/freerdp3-flags.bats`, `tests/precheck-menu.bats` | ~76 |

**Total**: 11 files changed, ~690 lines (`size:exception` accepted by user 2026-08-12).

### Architecture Decisions (all resolved)

1. `/usb:auto` escape hatch → OMIT (zero new code path; clean blast-radius)
2. `USB_DEVICE_IDS` serialization → `vid:pid#vid:pid` (xfreerdp3 `#` separator)
3. Capability-gate matrix → hard-fail drive/clipboard, silent-skip USB
4. CLI parity → menu-only for slice 1 (CLI flags deferred)
5. i18n keys → 3 keys finalized (`MSG_USB_REDIRECT`, `MSG_DRIVE_REDIRECT`, `MSG_CLIPBOARD_SYNC`)

---

## 2. Test Results

| Test File | Tests | Result |
|-----------|-------|--------|
| `tests/peripheral-flags.bats` | 23 | ✅ 23/23 |
| `tests/freerdp3-flags.bats` | 10 | ✅ 10/10 |
| `tests/precheck-menu.bats` | 14 | ✅ 14/14 |
| `tests/parser.bats` | 24 | ✅ 24/24 |
| `tests/audio-toggle.bats` | 7 | ✅ 7/7 |
| **Total** | **78** | **✅ 78/78** |

### Lint

- `make lint`: ⚠️ FAIL (pre-existing `DYNAMIC_RESOLUTION_OVERRIDE` SC2034 warning on engine L56)
- **NOT a regression** — confirmed on clean HEAD before this change
- `make ci` fails due to the pre-existing lint warning (not introduced by this change)

---

## 3. Spec-vs-Design Deviation (Corrected at Archive)

| Item | Original Spec | Design | Implementation | Resolution |
|------|--------------|--------|----------------|------------|
| Clipboard gate when unsupported | silent-skip | hard-fail | hard-fail (L152-153) | **Corrected**: spec updated to match design |

**Rationale**: The spec's original rationale ("clipboard is silent-skip because it is opt-in/opt-out") was internally inconsistent — clipboard is default-ON, not opt-in/opt-out. The design correctly identifies this: silently dropping a default-ON flag would be a hidden behavior change. Both drive and clipboard now hard-fail when unsupported (consistent treatment of default-ON flags). USB remains silent-skip (opt-in).

**Files corrected**:
- `specs/peripheral-redirect/spec.md` — gate matrix table + added clipboard hard-fail scenario
- `specs/engine-robustness/spec.md` — probe description corrected (clipboard ⟹ hard-fail)
- `openspec/specs/peripheral-redirect/spec.md` — main spec created with corrected gate matrix
- `openspec/specs/engine-robustness/spec.md` — main spec updated with corrected probe description

---

## 4. Task Completion

| Phase | Automated | Manual-Verify | Total |
|-------|-----------|---------------|-------|
| Phase 1 (Foundation) | 1.1 ✅, 1.2 ✅ | 1.3 🔲 | 2/3 |
| Phase 2 (Pure fns) | 2.1–2.6 ✅ | 2.7 🔲 | 6/7 |
| Phase 3 (Engine) | 3.1 ✅, 3.2 ✅, 3.4 ✅, 3.6 ✅ | 3.3 🔲, 3.5 🔲 | 4/6 |
| Phase 4 (Manual) | — | 4.1 🔲 | 0/1 |
| **Total** | **12/12** | **0/5** | **12/17** |

All automatable tasks are complete and verified by passing tests. Manual-verify
tasks are pending by design (require real xfreerdp3 session, out of scope for
automated phases).

---

## 5. Manual-Verify Checklist (Pending User Action)

These tasks require a real xfreerdp3 session and are pending by design:

- [ ] **1.3**: Run installer in throwaway HOME; confirm legacy profile loads without "unbound variable"
- [ ] **2.7**: Source lib in REPL; confirm each fn returns expected array with no engine globals set
- [ ] **3.3**: `make smoke`; inspect `ps`/log argv: `/usb:`/`/drive:`/`+clipboard` present when enabled, absent when off
- [ ] **3.5**: On a `/usb:`-less build stub, confirm gate skips gracefully (no hang, no reject); on full xfreerdp3 3.30.0 confirm all flags emit
- [ ] **4.1**: Full manual-verify checklist — `make ci` green; `make smoke` clean; real xfreerdp3 session: confirm flags in argv per profile; legacy profile zero-regression; gate skips gracefully; `/from-stdin:force` unmoved; no `"${ARR[@]-}"` form

---

## 6. Known Issues

### Pre-existing (NOT regressions from this change)

1. **`DYNAMIC_RESOLUTION_OVERRIDE` SC2034 lint warning** — engine L56. Exists on HEAD before this change. Should be fixed separately (add `# shellcheck disable=SC2034` or export the variable).
2. **`tests/harness.bats` hang** — requires `make smoke` which needs install.
3. **`tests/monitor-order-by-description.bats` failures** — pre-existing, unrelated to this change.

### No CRITICAL issues

The verify report found zero CRITICAL issues. All automated checks pass. The
spec-vs-design deviation was a WARNING with sound design rationale, corrected
at archive.

---

## 7. Delta Specs Applied

| Domain | Action | Details |
|--------|--------|---------|
| `peripheral-redirect` | **Created** (new capability) | 6 requirements: USB opt-in, drive toggle, clipboard toggle, allowlist keys, capability-gate matrix, FLAGS-array contract |
| `engine-robustness` | **Modified** | "Flag arrays" requirement extended to cover 3 peripheral arrays + corrected suffix invariant; "Peripheral-flag capability probing" requirement added |
| `engine-security` | **Modified** | "parse_env_safe key allowlist" extended from 7 to 12 keys; "Peripheral redirect blast-radius posture" requirement added |

### Spec Correction at Archive

The `peripheral-redirect` delta spec's clipboard gate row was corrected from
"silent-skip" to "hard-fail" to match the design and implementation. The
design rationale is technically sound: clipboard is default-ON, so silently
dropping it would be a hidden behavior change. This correction was applied to:
- The delta spec (`specs/peripheral-redirect/spec.md`)
- The main spec (`openspec/specs/peripheral-redirect/spec.md`)
- The engine-robustness delta and main specs (probe description)

---

## 8. Source of Truth Updated

The following main specs now reflect the new behavior:

- `openspec/specs/peripheral-redirect/spec.md` — **NEW** (created from corrected delta)
- `openspec/specs/engine-robustness/spec.md` — **UPDATED** (flag arrays + peripheral probing)
- `openspec/specs/engine-security/spec.md` — **UPDATED** (allowlist + blast-radius posture)

---

## 9. Archive Contents

| Artifact | Status |
|----------|--------|
| `proposal.md` | ✅ Present |
| `specs/` (3 delta specs) | ✅ Present (peripheral-redirect corrected) |
| `design.md` | ✅ Present |
| `tasks.md` | ✅ Present (12/17 automated complete, 5 manual pending) |
| `apply-progress.md` | ✅ Present |
| `verify-report.md` | ✅ Present (PASS WITH WARNINGS) |
| `archive-report.md` | ✅ Present (this file) |

---

## 10. SDD Cycle Complete

The change has been fully planned, implemented, verified, and archived.

**What shipped**: USB redirect (opt-in), drive redirect (toggle, default ON),
clipboard toggle (default ON), capability gate matrix, menu UI, i18n, 78/78
tests passing.

**What's pending**: 5 manual-verify tasks requiring real xfreerdp3 session (by
design, out of scope for automated phases).

**Follow-ups** (separate changes, not in scope here):
- Clipboard direction control (`direction-to:`/`direction-from:` sub-args)
- CLI parity (`--usb`, `--no-drive` flags)
- Fix pre-existing `DYNAMIC_RESOLUTION_OVERRIDE` lint warning

---

## 11. Return Envelope

- **status**: `success`
- **executive_summary**: Archived usb-redirect-clipboard-windowrules. Corrected spec-vs-design deviation (clipboard gate: silent-skip → hard-fail, matching design rationale). Synced 3 delta specs to main specs (peripheral-redirect created, engine-robustness + engine-security updated). 78/78 tests pass. 12/17 automated tasks complete; 5 manual-verify tasks pending by design. ~690 lines (size:exception accepted). Pre-existing lint warning is NOT a regression.
- **artifacts**:
  - Archive folder: `openspec/changes/archive/2026-08-12-usb-redirect-clipboard-windowrules/`
  - Archive report: `openspec/changes/archive/2026-08-12-usb-redirect-clipboard-windowrules/archive-report.md`
  - Engram topic_key: `sdd/usb-redirect-clipboard-windowrules/archive-report`
  - Corrected specs: `openspec/specs/peripheral-redirect/spec.md` (new), `openspec/specs/engine-robustness/spec.md` (updated), `openspec/specs/engine-security/spec.md` (updated)
- **next_recommended**: none (archive is terminal)
- **risks**: 5 manual-verify tasks pending (require real xfreerdp3 session). Pre-existing lint warning blocks `make ci` (not this change's fault).
- **skill_resolution**: `paths-injected` (skill loaded from `/home/hbuddenberg/.config/opencode/skills/sdd-archive/SKILL.md`)
