# Verification Report: usb-redirect-clipboard-windowrules

> **Change**: `usb-redirect-clipboard-windowrules` · **Project**: `rdp-connect`
> **Date**: 2026-08-12 · **Verifier**: sdd-verify (automated)
> **Attempt token**: `sha256:35275e22aad38f3b534104a0618809222c574f99786a64e9e43a1a0ca9c9f2fb`

## Verdict: PASS WITH WARNINGS

All automated checks pass. One spec-vs-design deviation (clipboard gate severity) with sound design rationale. Pre-existing lint issue is NOT a regression. Manual-verify tasks are out of scope for this phase.

---

## 1. Test Suite

| Command | Result | Details |
|---------|--------|---------|
| `bats tests/peripheral-flags.bats` | ✅ 23/23 | Allowlist + 3 build fns + purity + gate matrix |
| `bats tests/freerdp3-flags.bats` | ✅ 10/10 | Phantom-arg + expansion + build fn calls |
| `bats tests/precheck-menu.bats` | ✅ 14/14 | 3 toggle rows + persist assertions |
| `bats tests/parser.bats` | ✅ 24/24 | parse_env_safe + i18n mode |
| `bats tests/audio-toggle.bats` | ✅ 7/7 | Audio toggle (regression) |
| **Total** | **✅ 78/78** | 5 core files, all green |
| `make lint` | ⚠️ FAIL (pre-existing) | `DYNAMIC_RESOLUTION_OVERRIDE` SC2034 — exists on HEAD before this change, NOT a regression |
| `make ci` | ⚠️ FAIL (pre-existing) | `ci = lint + test`; lint fails on pre-existing warning |

**Lint pre-existing confirmation**: Stashed working tree changes, ran `make lint` on clean HEAD — same `DYNAMIC_RESOLUTION_OVERRIDE` SC2034 failure. This is NOT introduced by this change.

---

## 2. Structural Assertions (Spec Compliance)

### Security Invariants (NEVER regress)

| Assertion | Status | Evidence |
|-----------|--------|----------|
| `/from-stdin:force` password path unchanged | ✅ PASS | L1160 — same position, literal `+clipboard` and `/drive:` replaced by array expansions around it |
| `+clipboard` default ON for legacy profiles | ✅ PASS | `build_clipboard_flags`: `[ "${CLIPBOARD_SYNC:-1}" = "1" ]` → `("+clipboard")` |
| `/drive:compartido` default ON | ✅ PASS | `build_drive_flags`: `[ "${DRIVE_REDIRECT:-1}" = "1" ]` → `("/drive:compartido,${SHARE_DIR:-$HOME/Compartido}")` |
| `/usb:auto` NEVER emitted | ✅ PASS | `grep -rn 'usb:auto' engine/ lib/` → 0 matches |
| `/drive:hotplug,*` NEVER emitted | ✅ PASS | `grep -rn 'drive:hotplug' engine/ lib/` → 0 matches |
| Profiles parsed via allowlist only (never source/eval) | ✅ PASS | `parse_env_safe` uses `printf -v` with allowlist check; no `source`/`eval` of profile content |
| Empty arrays expand `"${ARR[@]}"` (no `-` suffix) | ✅ PASS | `grep -nE '"\$\{(USB\|DRIVE\|CLIPBOARD)_FLAGS\[@\]-\}"' engine/` → 0 matches |

### Spec Requirements (peripheral-redirect)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| USB opt-in default OFF | ✅ PASS | `build_usb_flags`: `[ "${USB_REDIRECT:-0}" = "1" ] || return 0` — empty array when unset |
| USB vid:pid regex validation | ✅ PASS | Regex `^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}))*$` at lib L374 |
| Drive default ON | ✅ PASS | `build_drive_flags`: default `DRIVE_REDIRECT:-1` → emits flag |
| Drive togglable OFF | ✅ PASS | `DRIVE_REDIRECT=0` → `DRIVE_FLAGS=()` (test `drive_off_emits_no_flag`) |
| Clipboard default ON | ✅ PASS | `build_clipboard_flags`: default `CLIPBOARD_SYNC:-1` → `("+clipboard")` |
| Clipboard togglable OFF | ✅ PASS | `CLIPBOARD_SYNC=0` → `CLIPBOARD_FLAGS=()` (test `clipboard_off_omits_flag`) |
| Allowlist extended (5 keys) | ✅ PASS | `_PROFILE_KEYS` lines 48-52: `USB_REDIRECT`, `USB_DEVICE_IDS`, `DRIVE_REDIRECT`, `SHARE_DIR`, `CLIPBOARD_SYNC` |
| Pre-init at engine | ✅ PASS | L388: `USB_REDIRECT="" USB_DEVICE_IDS="" DRIVE_REDIRECT="" SHARE_DIR="" CLIPBOARD_SYNC=""` |
| Capability gate: probes | ✅ PASS | L143-160: probes `/drive:`, `clipboard`, `/usb:` via `xfreerdp3 /help` |
| Gate matrix: drive → hard-fail | ✅ PASS | L148-149: `exit 1` with actionable message |
| Gate matrix: USB → silent-skip | ✅ PASS | L158-159: no else/exit, just sets `_HAS_USB=1` if present; `build_usb_flags` logs WARN + returns empty |
| FLAGS arrays alongside SOUND_FLAGS | ✅ PASS | L978-983: `build_usb_flags`, `build_drive_flags`, `build_clipboard_flags` called after SOUND_FLAGS |
| argv site expands arrays | ✅ PASS | L1171-1175: `"${CLIPBOARD_FLAGS[@]}"`, `"${DRIVE_FLAGS[@]}"`, `"${USB_FLAGS[@]}"` |
| `/from-stdin:force` unmoved | ✅ PASS | L1160 — same position relative to `/sec:nla` (L1162) |
| Menu rows added | ✅ PASS | L472-483: USB (`_pm_umark`/`_pm_uline`), drive (`_pm_dmark`/`_pm_dline`), clipboard (`_pm_cmark`/`_pm_cline`) |
| i18n keys (es + en) | ✅ PASS | `MSG_USB_REDIRECT`, `MSG_DRIVE_REDIRECT`, `MSG_CLIPBOARD_SYNC` in both `i18n/es.env` and `i18n/en.env` |
| template.env documents 5 tunables | ✅ PASS | L20-24: all 5 keys documented with comments |

### Design Compliance

| Decision | Status | Evidence |
|----------|--------|----------|
| `/usb:auto` escape hatch OMIT | ✅ PASS | No `usb:auto` in codebase |
| `USB_DEVICE_IDS` serialization `vid:pid#vid:pid` | ✅ PASS | Regex + test `usb_multi_vid_pid_hash_separator` |
| CLI parity → menu-only | ✅ PASS | No `--usb`/`--no-drive` CLI flags added |
| 3 pure fns in lib | ✅ PASS | `build_usb_flags` L364, `build_drive_flags` L383, `build_clipboard_flags` L393 |
| Migrate `+clipboard`/`/drive:` literals → arrays | ✅ PASS | Literals removed from argv; replaced by `"${CLIPBOARD_FLAGS[@]}"` / `"${DRIVE_FLAGS[@]}"` |

---

## 3. Spec-vs-Design Deviation

| Item | Spec | Design | Implementation | Severity |
|------|------|--------|----------------|----------|
| Clipboard gate when unsupported | silent-skip | hard-fail | hard-fail (L152-153) | **WARNING** |

**Analysis**: The `peripheral-redirect` spec table says `+clipboard` unsupported → "silent-skip; session proceeds." The design says hard-fail with rationale: "default-on; current engine already hard-emits it; removing silently changes clipboard behavior." The implementation follows the design.

The spec's own rationale ("USB and clipboard are silent-skip because they are opt-in/opt-out") is internally inconsistent — clipboard is default-ON, not opt-in/opt-out. The design correctly identifies this and overrides. The hard-fail behavior is technically more correct (silently dropping a default-ON flag would be a hidden behavior change).

**Resolution**: Implementation matches design. Spec should be corrected at archive time to match design's hard-fail for clipboard.

---

## 4. Task Completion

| Phase | Tasks | Status |
|-------|-------|--------|
| Phase 1 (Foundation) | 1.1 ✅, 1.2 ✅, 1.3 🔲 (manual) | 2/3 |
| Phase 2 (Pure fns) | 2.1–2.6 ✅, 2.7 🔲 (manual) | 6/7 |
| Phase 3 (Engine) | 3.1 ✅, 3.2 ✅, 3.3 🔲 (manual), 3.4 ✅, 3.5 🔲 (manual), 3.6 ✅ | 4/6 |
| Phase 4 (Manual) | 4.1 🔲 (manual) | 0/1 |
| **Total** | **12/16 non-manual ✅** | **5 manual-verify out of scope** |

All automatable tasks are complete and verified by passing tests.

---

## 5. Budget / Line Count

| Metric | Value |
|--------|-------|
| Tracked file changes | 511 insertions + 10 deletions = 521 lines |
| New test files | 232 (peripheral-flags.bats) + 148 (precheck-menu.bats) = 380 lines |
| **Total changed lines** | **~690** |
| 400-line budget | Exceeded |
| `size:exception` | Accepted by user (2026-08-12) |

---

## 6. Issues

### CRITICAL
None.

### WARNING
1. **Clipboard gate spec-vs-design deviation** — Spec says silent-skip, design says hard-fail, implementation follows design. Design rationale is technically sound. Spec should be corrected at archive.
2. **Pre-existing `DYNAMIC_RESOLUTION_OVERRIDE` lint warning** — SC2034 on engine L56. NOT introduced by this change (confirmed on HEAD). Should be fixed separately (add `# shellcheck disable=SC2034` or export the variable).
3. **`make ci` fails** — Due to pre-existing lint warning above. Not a regression from this change.

### SUGGESTION
1. Consider adding `# shellcheck disable=SC2034` to `DYNAMIC_RESOLUTION_OVERRIDE` to unblock `make ci` (separate change, not in scope here).
2. At archive, correct the `peripheral-redirect` spec's clipboard gate row from "silent-skip" to "hard-fail" to match design and implementation.

---

## 7. Pending (Out of Scope for Automated Verify)

- [ ] 1.3: Real xfreerdp3 session with legacy profile (no unbound variable)
- [ ] 2.7: REPL source of lib fns
- [ ] 3.3: Real xfreerdp3 session argv inspection
- [ ] 3.5: Capability gate on `/usb:`-less build
- [ ] 4.1: Full manual-verify checklist

---

## 8. Return Envelope

- **status**: `partial` (all automated checks pass; pre-existing lint issue blocks `make ci`; manual-verify pending)
- **executive_summary**: 78/78 tests green. All structural assertions pass. One spec-vs-design deviation (clipboard gate: spec says silent-skip, design+impl say hard-fail — design rationale is sound). `make lint`/`make ci` fail on pre-existing `DYNAMIC_RESOLUTION_OVERRIDE` warning (NOT a regression). 5 manual-verify tasks pending (out of scope).
- **artifacts**: This report at `openspec/changes/usb-redirect-clipboard-windowrules/verify-report.md`
- **next_recommended**: `archive` (all automated checks pass; manual-verify is out-of-scope by design; pre-existing lint issue is not a regression)
- **risks**: Pre-existing lint warning blocks `make ci` (not this change's fault). Clipboard gate spec-vs-design inconsistency should be resolved at archive. Manual-verify tasks require real xfreerdp3 session.
- **skill_resolution**: `paths-injected` (skill loaded from `/home/hbuddenberg/.config/opencode/skills/sdd-verify/SKILL.md`)
