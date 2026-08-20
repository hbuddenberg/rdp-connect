# Design: compositor-aware — Hyprland + Niri backends, degraded `none`

## Technical Approach

Exploration approach 1: adapter layer inside `lib/rdp-common.bash` (two-file deploy intact). `detect_compositor()` once at preflight → `COMPOSITOR` ∈ {hypr, niri, none}; `get_monitors_json()` → ONE canonical logical array; dispatch wrappers own all compositor mutation. Engine keeps precedence/canvas math/settle retries — rewritten once, over canonical logical values. Password pipe (engine:1217–1243), setsid re-exec (:27–29), lockfile never-unlink, `parse_env_safe`, `"${ARR[@]}"` rule: byte-identical, adapters never interpose. Assumes niri ≥ 26.04 (`niri msg --json`, `--window-id`), Hyprland classic dispatch forms (live-verified 0.56.1), `NIRI_SOCKET` inherited via uwsm (glob-socket fallback out of scope).

## Architecture Decisions

| # | Decision | Choice (rejected → why) |
|---|---|---|
| D1 | Layout | One lib section: public `detect_compositor`, `get_monitors_json`, `compositor_find_window`, 6 `dispatch_*` wrappers; private `_monitors_{hypr,niri,none}`, `_hypr_dispatch/_niri_dispatch`. (Source-split files: breaks two-file manifest; inline if/else per site: 2× logic, matrix doubles.) |
| D2 | Canonical shape | `jq -c '[{id,desc,x,y,w,h,scale,ws_ref}]'`, logical px. hypr: `sort_by(.x)` verbatim, `id=.id`, `desc=.description`, `x/.y` passthrough (already logical), `w=(.width/.scale\|round)`, `h=(.height/.scale\|round)`, `ws_ref=.activeWorkspace.id`. niri: `to_entries \| sort_by(.value.logical.x,.value.logical.y)`, `id=.key` (output NAME), `desc=make+" "+model+" "+serial`, `logical.*` passthrough, `scale=.logical.scale` (never configured top-level `scale`), `ws_ref` from `niri msg --json workspaces` (`.output==$key and (.is_active // .is_focused) → .name`). none: `[]`. |
| D3 | jq filters | Inline single-quoted jq inside backend fns (heredocs rejected: extra fds, no gain — `compute_dpi_flags` precedent). Compositor-controlled strings enter only via `--arg`; no `eval`; token match `select((.id\|tostring)==$tok)` — hypr numeric ids and niri names both work. `/scale` exists ONLY in `_monitors_hypr` (structural test). |
| D4 | Detection | Candidates hint-ordered, probe-decided: `[ -n NIRI_SOCKET ]→niri first`, `[ -n HYPRLAND_INSTANCE_SIGNATURE ]→hypr first`, `XDG_CURRENT_DESKTOP` hint, then both appended (deduped, order kept). Probe (in `if` — explicit rc capture, pipefail-safe, no `|| true`): `out=$(timeout 2 hyprctl monitors -j 2>/dev/null | jq -e . 2>/dev/null)` / `timeout 2 niri msg --json outputs`. rc alone never decides (both rc=1 plain-text on wrong compositor); `command -v` guard skips missing CLIs. No valid JSON → `COMPOSITOR=none` + exactly one WARN `MSG_COMPOSITOR_NONE` (es: "Ningún compositor respondió (Hyprland/Niri). Modo degradado: /f, DPI 100%, sin workspace ni menú." / en mirror). Per-invocation cache: winning probe JSON in `_PROBE_JSON_*`; canonical lazily in `_CANON_MONITORS` — ≤1 IPC per query type per run. |
| D5 | DPI source | `get_dpi_scale()`: hypr → `.[0].scale` of cached RAW monitors JSON (detection order — byte-identical to today); niri → canonical `.[0].scale` (leftmost, per spec); none/unparsable → empty → existing 100% WARN path. `compute_dpi_flags` changes only its source call. |
| D6 | Dispatch contract | LOGICAL-geometry wrappers: `dispatch_move_to_ws <ws_ref>`, `dispatch_focus`, `dispatch_float`, `dispatch_fullscreen`, `dispatch_resize <w> <h>`, `dispatch_move <x> <y>`. hypr emits today's argv verbatim with `&>/dev/null \|\| true` (documented cosmetic): `dispatch movetoworkspacesilent "<ws>,class:$WM_CLASS"`, `focuswindow`, `setfloating`, `fullscreen "0"`, `resizewindowpixel "exact <w> <h>,class:…"`, `movewindowpixel "exact <x> <y>,class:…"`. niri: `move-window-to-workspace <ref> --window-id <id>` + `focus-workspace <ref>`, `focus-window --id`, `move-window-to-floating --id`, `fullscreen-window --id`, `set-window-width`/`set-window-height --id`, `move-floating-window --id -x -y` (gated, D8). none: WARN `MSG_DISPATCH_NOOP`, no IPC, rc 0. Window token: `compositor_find_window <class>` — hypr `clients -j \| any(.class==$c)` (poll byte-identical); niri `windows --json` → `.id` where `.app_id==$c` (XWayland mapping gated D8). |
| D7 | require_cmd | Engine :125 unconditional `require_cmd hyprctl` deleted; after the fixed binary list, `detect_compositor`; then `COMPOSITOR=hypr → require_cmd hyprctl hyprland`; `niri → require_cmd niri niri`; none → nothing (WARN already names the mode). |
| D8 | Niri expand gate | PR3 task 1 = live verification of (a) `move-floating-window` abs-vs-delta, (b) global-vs-output-local coords, (c) XWayland `app_id`↔`/wm-class` — recorded in checklist BEFORE wiring. Any fail/no-run → degraded expand: `fullscreen-window --id <token>` on selected output + WARN `MSG_EXPAND_DEGRADED`. Never silent breakage. |
| D9 | none shape | canonical `[]` → `MON_COUNT=0→1` → `build_mon_flags` → `/f`; pre-connect menu guarded `[ "$COMPOSITOR" != none ]` (twin of no-wofi skip); ws pin/geometry no-op via wrappers; DPI 100% WARN; `--expand` fails at find-window ("no active session", existing message). xfreerdp3 pipeline untouched. |

## Data Flow

    preflight ─→ detect_compositor ─→ COMPOSITOR (+_PROBE_JSON_* cache)
    get_monitors_json ─→ _monitors_<backend> ─→ _CANON_MONITORS (logical)
    engine canvas math + compute_dpi_flags(get_dpi_scale) ── logical only
    compositor_find_window ─→ _WIN_TOKEN ─→ dispatch_* ─→ hyprctl | niri msg | none-WARN

## Engine Call-Site Migration (census → adapter)

| Group | Engine sites | Replacement |
|---|---|---|
| 1 preflight | :125 | D7 sequence |
| 2 monitors | :233,:238,:245,:462,:802–803,:850,:914,:927,:976,:1004 | `get_monitors_json` (cached); `resolve_monitor_order` re-pointed `.description`→`.desc`, id-match per D3 |
| 3 DPI | lib:294 | `get_dpi_scale` (D5) |
| 4 ws pin | :828,:865,:1112,:1153 | canonical `ws_ref` → `dispatch_move_to_ws`; sequence/retries verbatim |
| 5 poll+geom | :223,:1094,:265–267,:1125–1196 | `compositor_find_window` + float/resize/move/fullscreen wrappers; ORDER preserved (move last; settle retries) |
| 6 focus | :1115 | `dispatch_focus` |
| 7 docs | installer:60–119,242–248; lib:602–613 | compositor OR-pair, generalized warning, niri tokens in tunables text |

## File Changes

| File | Action | Description |
|---|---|---|
| `lib/rdp-common.bash` | Modify | +D1–D6 fns (~+170 lines); `resolve_monitor_order` desc field; tunables text |
| `engine/rdp-connect` | Modify | ~25 logical sites → wrappers; D7; D9 guards |
| `i18n/{es,en}.env` | Modify | +`MSG_COMPOSITOR_NONE`, `MSG_DISPATCH_NOOP`, `MSG_EXPAND_DEGRADED` |
| `install-rdp-framework.sh` | Modify | hyprland-OR-niri dep pair; generalized missing-compositor warning (none-mode name) |
| `tests/backends.bats`, `tests/niri-api.bats`, `tests/installer-backends.bats` | Create | see Testing |
| `tests/fixtures/compositor/{hypr-monitors,hypr-clients,niri-outputs,niri-workspaces,niri-windows}.json` | Create | live-probed shapes (twin Dells, `scale:null`+`logical.scale:2`) |
| `tests/{hyprland-api,hidpi,monitor-mode,span-mode,multi-position,expand-mode,precheck-menu,monitor-order-by-description}.bats` | Modify | argv-capture regression; canonical-fixture migration; niri variants |
| `openspec/changes/compositor-aware/checklist.md`, `README.md`, `CLAUDE.md` | Create/Modify (PR3) | E2E checklist (6 items × both compositors); docs |

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit | detect×4 (niri-probe, hypr-probe, none, env-hint-no-decide), canonical×3 (3840×2160@2→1920×1080; niri to_entries ordering; ws_ref), `logical.scale`≠configured, serial disambiguation, none `/f`+100%, dispatch noop WARN, wrong-CLI degrade, dispatch-failure no-abort, none skips compositor require_cmd (structural) | `backends.bats`: PATH-shadowed `hyprctl()`/`niri()` fn mocks over fixtures (hidpi.bats pattern; `log_event` stub asserts WARN) |
| Structural | zero raw `hyprctl`/`niri msg` in engine code; `/scale` only in `_monitors_hypr`; `--window-id` form; hypr classic forms + golden argv capture under `COMPOSITOR=hypr` | `niri-api.bats` (new) + `hyprland-api.bats` retargeted engine→lib backend fns |
| Matrix | hidpi (canonical-hypr + niri logical.scale), monitor-mode/span/multi/expand/precheck: raw-JSON `hyprctl()` mocks keep working (lib converts raw→canonical); order-by-description migrated to canonical fixtures — expectations unmodified | existing suites, backend-matrix variants |
| Installer | niri-only satisfies OR (pkg-manager spy); neither → completes with none-mode warning | `installer-backends.bats` |
| E2E | 6 checklist items × {niri live, Hyprland via session toggle} — expand or documented degraded expand | manual, checklist artifact |

## Threat Matrix

| Boundary | Applicability |
|---|---|
| Doc-like paths / git -C / commit / push / PR commands | N/A — no VCS/doc/PR automation in this change |
| Compositor subprocess/IPC (adapted) | Applicable: wrong-compositor rc=1 plain-text; missing CLI; hung socket; malformed/hostile JSON; token injection via monitor names → probe-decided detection + `timeout 2` + `jq -e` validity (D4), WARN+degrade never abort, `--arg`-only jq, no eval. RED: `detect_none_when_no_valid_json`, `wrong_compositor_cli_warn_degrade_no_abort`, `dispatch_failure_does_not_abort`, malformed-JSON canonical cases |

Parser/escape edges (rules.design): jq programs are quoted literals; compositor strings only via `--arg`; string-compare ids; niri ws names (may contain spaces) travel as single quoted argv tokens; desc containing tab breaks the menu `\t` separator — pre-existing ambiguity class, noted, unchanged.

## Migration / Rollout (3 chained PRs)

| PR | Slice | Verify gate | Rollback |
|---|---|---|---|
| 1 (~380) | lib adapters (D1–D6, inert to engine except DPI source parity) + backends/niri-api bats + fixtures. Engine file untouched | `make ci`; `make smoke`; live Hyprland: DPI output byte-identical | `git revert` — engine file unchanged |
| 2 (~340) | engine groups 1–6 launch path (incl. dispatcher subshell; `--expand` stays hypr-raw, untouched), D7, i18n, installer OR-pair, tunables text, matrix migrations | `make ci`; live niri: monitors+DPI+ws-pin; live Hyprland: full manual regression (checklist items 1–4, 6) | `git revert` + `make install` (`make verify-manifest`) |
| 3 (~280) | expand gate FIRST (D8) → wire per recorded semantics OR degraded expand; checklist artifact; README/CLAUDE | `make ci`; live niri expand/degraded-expand; Hyprland `--expand` unchanged; checklist both columns executed | `git revert` + `make install` |

## Open Questions

- [ ] niri 26.04 workspaces JSON: confirm per-output `is_active` field exists (else non-focused outputs get `ws_ref=null` → PREFERRED_WS passthrough degradation — acceptable, must be documented). Resolve at PR2 fixture freeze.
- [ ] Detection probes run before `load_language` (preflight order): none-mode WARN must not depend on MSG_* being loaded — emit via `log_event`/stderr literal or move detection after `load_language`; tasks to pick (spec silent on ordering).
