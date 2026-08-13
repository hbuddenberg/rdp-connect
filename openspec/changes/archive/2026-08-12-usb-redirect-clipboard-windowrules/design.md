# Design: usb-redirect-clipboard-windowrules

> **Change**: `usb-redirect-clipboard-windowrules` · **Project**: `rdp-connect` (Bash 5.3, xfreerdp3 3.30.0, Wayland/Hyprland) · **Mode**: hybrid
> **Proposal**: `proposal.md` (authoritative) · **Engram**: `sdd/usb-redirect-clipboard-windowrules/proposal` (obs #14)
> **Scope**: F1 (USB opt-in + drive toggle) + F2-a (clipboard parity). F3 / F2-b OUT.
> **Hook points**: all verified verbatim against `/home/hbuddenberg/Projects/rdp-connect` (engine 1120 L, lib 517 L).

## Technical Approach

Extend the established **menu → allowlist → pure-fn → FLAGS-array → argv** pipeline with three new togglable peripherals, each following the `SOUND_FLAGS` pattern (engine L911-921). All flag-construction logic is extracted as pure lib fns (bats-unit-testable per `strict_tdd: true`); engine integration (menu render, capability gate, xfreerdp3 launch) stays manual-verify. Defaults preserve current behavior: drive ON, clipboard ON, USB OFF — **zero regression** for existing profiles.

## Architecture / Data Flow

```
 profile .env                engine pre-init (L360)         parse_env_safe (lib L92)
 (5 new keys)        ──►     USB_REDIRECT="" etc    ──►     allowlist assignment
                                                                    │
                                                                    ▼
                                                          build_usb_flags()      ┐
                                                          build_drive_flags()    ├── lib pure fns
                                                          build_clipboard_flags()┘
                                                                    │
                                                    sets globals: USB_FLAGS=()
                                                    DRIVE_FLAGS=() CLIPBOARD_FLAGS=()
                                                                    │
 capability gate (L131 extension) ◄── xfreerdp3 /help grep          ▼
 _HAS_USB / _HAS_DRIVE / _HAS_CLIPBOARD ──►   argv assembly (L1090-1113)
                                              "${USB_FLAGS[@]}"         (new, additive)
                                              "${DRIVE_FLAGS[@]}"       (replaces literal /drive: L1108)
                                              "${CLIPBOARD_FLAGS[@]}"   (replaces literal +clipboard L1105)
                                                          │
                                                          ▼
                                                   xfreerdp3 + /from-stdin:force (UNMOVED)
```

## Architecture Decisions

### Decision: `/usb:auto` escape hatch → OMIT

| Option | Tradeoff | Decision |
|---|---|---|
| Include `USB_REDIRECT=auto` | New code branch + printed security warning; arbitrary-device redirect (attack surface) | ✗ rejected |
| **OMIT for slice 1** | Zero new code path; clean blast-radius posture | **chosen** |

**Rationale**: Proposal's own gate ("include only if zero new code path") fails — `auto` requires either a new branch in `build_usb_flags` or a warning emit. `/usb:auto` redirects ALL USB devices (different security class than explicit `id:`). Defer to a future slice if demand appears. Keeps `/usb:auto` + `/drive:hotplug,*` in the "NEVER defaults" posture.

### Decision: `USB_DEVICE_IDS` serialization → `vid:pid` + `#` multi-separator

**Format**: single = `0781:5580`; multi = `0781:5580#046d:c52b` (xfreerdp3 `#` device-list separator).
**Validation regex** (per full value, case-insensitive hex):
```
^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}))*$
```
Reject non-conformant values **loudly** (fn returns non-zero → engine aborts before xfreerdp3). Emits `/usb:id:<value>` verbatim.

### Decision: capability-gate failure matrix

| Flag | Default | Probe | Unsupported behavior | Justification |
|---|---|---|---|---|
| `/drive:` | ON | `grep -qE '/drive:'` | **hard-fail** (exit 1) | default-on → users expect it; silent loss surprises; matches `/from-stdin:force` precedent (L131) |
| `+clipboard` | ON | `grep -q clipboard` | **hard-fail** (exit 1) | default-on; current engine already hard-emits it; removing silently changes clipboard behavior |
| `/usb:` | OFF (opt-in) | `grep -qE '/usb:'` | **silent-skip** (log WARN, omit flag) | optional; user opted-in but session should still connect; degrade, never hang/reject |

### Decision: CLI parity → menu-only for slice 1

| Option | Tradeoff | Decision |
|---|---|---|
| Full `--usb`/`--no-drive` | +parsing (L49-63) +help text +structural tests; blows `review_budget_lines: 400` | ✗ deferred |
| **Menu + profile key only** | Full functionality via menu + `.env`; CLI flags = convenience, later slice | **chosen** |

**Rationale**: matches `AUDIO_REDIRECT` shipping history (menu+key first, `--no-audio` override later). Profile key + menu = complete control surface. CLI flags are a clean follow-up.

### Decision: migrate `+clipboard` / `/drive:` literals into pure fns

The current `+clipboard` (L1105) and `/drive:compartido,...` (L1108) are **hardcoded literals**. Toggling requires they move INTO `build_clipboard_flags` / `build_drive_flags`; the argv gains `"${CLIPBOARD_FLAGS[@]}"` / `"${DRIVE_FLAGS[@]}"` **in their place**. Only `"${USB_FLAGS[@]}"` is purely additive. `/from-stdin:force` (L1094) and the surrounding argv structure are unmoved (R4).

## Pure Lib Functions

All three live in `lib/rdp-common.bash` after `build_mon_flags` (post L338). Shape mirrors `compute_dpi_flags` (no args, read profile globals set by `parse_env_safe`, set a global FLAGS array). Arrays are **always initialized** (never unset) so `"${ARR[@]}"` expands cleanly under `set -u`.

```bash
# build_usb_flags — lee USB_REDIRECT, USB_DEVICE_IDS; setea USB_FLAGS=()
# OFF (default)            → USB_FLAGS=()
# ON + ids válidos         → USB_FLAGS=("/usb:id:<vid:pid>#<vid:pid>")
# ON + ids inválidos       → return 1 (aborta antes de xfreerdp3, R6)
# ON + build sin /usb:     → USB_FLAGS=() + log WARN (silent-skip)
build_usb_flags() {
  USB_FLAGS=()
  [ "${USB_REDIRECT:-0}" = "1" ] || return 0
  if [ "${_HAS_USB:-0}" != "1" ]; then
    log_event "WARN" "USB redirect solicitado pero xfreerdp3 carece de /usb: (omitido)"
    return 0
  fi
  local val="${USB_DEVICE_IDS:-}"
  if ! [[ "$val" =~ ^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}))*$ ]]; then
    log_event "ERROR" "USB_DEVICE_IDS inválido: '$val' (esperado vid:pid[#vid:pid])"
    return 1
  fi
  USB_FLAGS=("/usb:id:$val")
}

# build_drive_flags — lee DRIVE_REDIRECT (default 1), SHARE_DIR (default $HOME/Compartido)
# ON (default)  → DRIVE_FLAGS=("/drive:compartido,<SHARE_DIR>")
# OFF           → DRIVE_FLAGS=()   (preserve L1108 default-on behavior)
build_drive_flags() {
  DRIVE_FLAGS=()
  [ "${DRIVE_REDIRECT:-1}" = "1" ] || return 0
  DRIVE_FLAGS=("/drive:compartido,${SHARE_DIR:-$HOME/Compartido}")
}

# build_clipboard_flags — lee CLIPBOARD_SYNC (default 1)
# ON  → CLIPBOARD_FLAGS=("+clipboard")            (preserve L1105)
# OFF → CLIPBOARD_FLAGS=()
build_clipboard_flags() {
  CLIPBOARD_FLAGS=()
  [ "${CLIPBOARD_SYNC:-1}" = "1" ] || return 0
  CLIPBOARD_FLAGS=("+clipboard")
}
```

**Unit-test sourcing pattern**: `tests/test_helper.bash` already `source "${LIB_FILE}"` (L92) — every bats `@test` calls the fns directly in-process. No new harness wiring needed.

## File Changes

| File | Action | Description |
|---|---|---|
| `lib/rdp-common.bash` L33-48 | Modify | add 5 keys to `_PROFILE_KEYS`: `USB_REDIRECT USB_DEVICE_IDS DRIVE_REDIRECT SHARE_DIR CLIPBOARD_SYNC` |
| `lib/rdp-common.bash` post-L338 | Modify | add `build_usb_flags` / `build_drive_flags` / `build_clipboard_flags` |
| `lib/rdp-common.bash` L491-516 | Modify | extend `append_tunables_block` tunables doc with the 5 new keys |
| `engine/rdp-connect` L360-361 | Modify | pre-init `USB_REDIRECT="" USB_DEVICE_IDS="" DRIVE_REDIRECT="" SHARE_DIR="" CLIPBOARD_SYNC=""` |
| `engine/rdp-connect` L131-135 | Modify | extend gate: probe `/drive:` `/clipboard` `/usb:`, set `_HAS_*` globals, hard-fail default-on, silent-skip USB |
| `engine/rdp-connect` L911-921 | Modify | call the 3 build fns alongside `SOUND_FLAGS` build |
| `engine/rdp-connect` L436-490 | Modify | add 3 menu rows (`_pm_umark`/`_pm_uline`, `_pm_dmark`/`_pm_dline`, `_pm_cmark`/`_pmcline`) + `set_profile_key` persist; default marks preserve behavior |
| `engine/rdp-connect` L1090-1113 | Modify | replace literal `+clipboard` (L1105) → `"${CLIPBOARD_FLAGS[@]}"`; replace `/drive:...` (L1108) → `"${DRIVE_FLAGS[@]}"`; add `"${USB_FLAGS[@]}"` (additive); `/from-stdin:force` unmoved |
| `i18n/{es,en}.env` | Modify | add `MSG_USB_REDIRECT` / `MSG_DRIVE_REDIRECT` / `MSG_CLIPBOARD_SYNC` |
| `template/template.env` L9-19 | Modify | document the 5 new tunables |
| `tests/peripheral-flags.bats` | Create | pure-fn behavior + vid:pid validation + multi-device `#` + allowlist |

## Interfaces / Contracts

**Profile keys** (all optional, parsed by `parse_env_safe`, never sourced):
- `USB_REDIRECT` — `0`|`1` (default `0` = OFF, opt-in)
- `USB_DEVICE_IDS` — `vid:pid[#vid:pid]` hex (required when `USB_REDIRECT=1`)
- `DRIVE_REDIRECT` — `0`|`1` (default `1` = ON, preserve)
- `SHARE_DIR` — path (default `$HOME/Compartido`)
- `CLIPBOARD_SYNC` — `0`|`1` (default `1` = ON, preserve)

**i18n keys**:
| Key | es | en |
|---|---|---|
| `MSG_USB_REDIRECT` | `Dispositivo USB (redirección)` | `USB device (redirect)` |
| `MSG_DRIVE_REDIRECT` | `Disco compartido (local→remoto)` | `Shared drive (local→remote)` |
| `MSG_CLIPBOARD_SYNC` | `Portapapeles (sincronización)` | `Clipboard (sync)` |

## Testing Strategy (Strict TDD: red-green-refactor)

| Layer | What | Approach |
|---|---|---|
| Unit (lib) | `build_usb_flags` ON/OFF/invalid/silent-skip; `build_drive_flags` ON/OFF/custom `SHARE_DIR`; `build_clipboard_flags` ON/OFF; vid:pid regex (single + multi `#` + malformed reject) | NEW `tests/peripheral-flags.bats`, source lib directly |
| Unit (lib) | `parse_env_safe` accepts the 5 new keys (profile mode); rejects non-allowlisted | extend `tests/peripheral-flags.bats` |
| Structural (engine) | phantom-empty-arg parity: `"${USB_FLAGS[@]-}"` / `"${DRIVE_FLAGS[@]-}"` / `"${CLIPBOARD_FLAGS[@]-}"` absent from code; `/usb:id:` / `/drive:` / `+clipboard` present (and `+clipboard` absent when `CLIPBOARD_SYNC=0`) | extend `tests/freerdp3-flags.bats` |
| Integration | menu renders 3 rows; capability gate probes; xfreerdp3 argv shape | manual-verify (`make smoke` + throwaway HOME) per `rules.apply.manual_check` |

**Red-green order**:
1. RED — `tests/peripheral-flags.bats` fails (fns absent)
2. GREEN — implement 3 pure fns in lib
3. RED — extend `tests/freerdp3-flags.bats` phantom-empty-arg parity for 3 new arrays
4. GREEN — engine argv uses `"${...[@]}"` form
5. Engine integration (menu, gate, argv migration) — manual-verify checkbox per task

## Threat Matrix

The subprocess boundary (xfreerdp3 argv) is engaged, so the matrix applies as a section. All five adversarial rows are **N/A** — none concern xfreerdp3:

| Boundary | Applicability | Reason |
|---|---|---|
| Documentation-like paths | N/A | no requirements.txt/CMakeLists/executable MDX touched |
| Git repository selection | N/A | no `git -C`/cwd authority change |
| Commit state | N/A | no index/worktree semantics |
| Push state | N/A | no refspec/tracking change |
| PR commands | N/A | no `--head`/composition |

**Actual subprocess threat** (malicious `USB_DEVICE_IDS` reaching argv) is mitigated by: (1) `parse_env_safe` allowlist (never `source`/`eval`), (2) `build_usb_flags` regex validation + non-zero return → engine aborts before xfreerdp3. RED test: `peripheral-flags.bats` rejects malformed `vid:pid`.

## Security

- **Defaults**: USB OFF (opt-in), drive ON (preserve), clipboard ON (preserve). Existing profiles with absent keys behave identically.
- **NEVER**: `/usb:auto`, `/drive:hotplug,*` as defaults (arbitrary/all-device redirect).
- **Allowlist**: 5 new keys flow through `parse_env_safe` — no `source`/`eval` regression.
- **Validation**: `USB_DEVICE_IDS` regex rejects malformed values loudly (R6); never reaches xfreerdp3.
- **Untouched**: `/from-stdin:force` (L1094), `setsid --wait`, PID lockfile, `parse_env_safe` internals.
- **Array expansion**: `"${ARR[@]}"` (no `-` suffix) — phantom-empty-arg invariant enforced + structurally tested.

## Risks / Tradeoffs (design-level)

| ID | Risk | Mitigation |
|---|---|---|
| D1 | bash-array purity — build fns set globals, not return arrays (bash can't return arrays) | mirrors `compute_dpi_flags`/`build_mon_flags` convention; documented `# shellcheck disable=SC2034` where needed |
| D2 | i18n loading timing — `MSG_*` keys loaded at L152, before menu (L436) ✓; ensure new keys exist in BOTH es.env + en.env or `set -u` aborts | load order verified (L142-152 precedes L436); both files must ship the 3 keys atomically |
| D3 | menu size growth — 3 new rows push `_pm_h` height (L440-442 clamps 200-800) | existing clamp absorbs the delta; no logic change |
| D4 | migrating `+clipboard`/`/drive:` literals → arrays is a behavior-neutral refactor but touches the security-critical argv block (L1090) | structural test asserts `/from-stdin:force` + `/sec:nla` intact; manual-verify `make smoke`; argv diff is additive except for the 2 migrated lines |
| D5 | capability gate does 3 extra `xfreerdp3 /help` calls | local subprocess, cheap, matches existing one-grep-per-feature idiom (L131); capturing once is a later refactor |

## Migration / Rollback

No data migration. Flags are additive; defaults preserve behavior. `git revert` restores engine/lib; installer is idempotent (re-run redeploys prior files). Existing profiles gain optional keys (absent ⟹ current behavior).

## Open Questions

All five proposal open questions **resolved in this design** (see Architecture Decisions):
1. `/usb:auto` → OMIT ✓
2. `USB_DEVICE_IDS` serialization → `vid:pid#vid:pid`, regex specified ✓
3. capability-gate matrix → hard-fail drive/clipboard, silent-skip USB ✓
4. CLI parity → menu-only for slice 1, CLI flags deferred ✓
5. i18n keys → 3 keys finalized with es/en strings ✓

**Deferred to a follow-up change:** clipboard *direction* control — verified grammar is `direction-to:[all|local|remote|off]` / `direction-from:` sub-args of `/clipboard:`, not a standalone flag. Out of scope for slice 1 (toggle-only `CLIPBOARD_SYNC` ships here).

**No blocking forks.** Ready for spec + tasks.
