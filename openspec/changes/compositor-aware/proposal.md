# Proposal: compositor-aware — Hyprland + Niri backends with degraded fallback

> Change: `compositor-aware` · propose · 2026-08-19 · built on ratified `exploration.md`.
> Mode: YOLO — assumptions pre-ratified (A20 origin contract + exploration); no question round run.

## Intent

The engine is Hyprland-only: 60 inline `hyprctl` sites and unguarded `hyprctl monitors -j` pipes under `set -euo pipefail`. In the user's live niri/uwsm session it dies at monitor detection (hyprctl → rc=1 plain text → pipefail). Per the A20 origin contract: full feature parity on niri (workspace pin, monitors, DPI) + degraded `none` mode when neither compositor answers. Blast radius: deployed script runs as the user with real RDP credentials; the password path is NOT touched.

## Scope

### In Scope
- **Adapter layer in `lib/rdp-common.bash`**: `detect_compositor()` — env hints fast-path only, JSON-validity probe decides (both CLIs rc=1 on wrong compositor); none valid → `COMPOSITOR=none`. `get_monitors_json()` → ONE canonical logical shape `[{id, desc, x, y, w, h, scale, ws_ref}]`. Dispatch wrappers (float/resize/move/fullscreen/focus/move-to-ws): WARN+no-op under `none`.
- **Engine migration per exploration group** (1 preflight, 2 monitors ×11 sites, 3 DPI, 4 ws targeting — niri uses non-standard `--window-id` flag, 5 window poll via `app_id`, 6 focus-restore). Hypr adapter owns the physical→logical `/scale` conversion — the only place it lives; niri passes `logical.*` through.
- **Degraded `none` mode**: one WARN; xfreerdp3 launches `/f` @100% DPI, full security pipeline; no ws pin, geometry dispatch, or pre-connect menu (mirrors existing degradation precedents).
- **Niri expand** gated on apply-time live verification (move-floating-window semantics, coordinate space, XWayland app_id); fail → documented degraded expand (fullscreen per output), never silent breakage.
- **Installer** per-compositor deps; tunables docs gain niri tokens (output names, serial-qualified); i18n es/en pairs for new messages.
- **E2E checklist artifact** (both compositors), executed as done criteria.

### Out of Scope
- Security model (`parse_env_safe`, `/from-stdin:force`, setsid re-exec, lockfile never-unlink, `|| true` perimeter) — untouched; adapters MUST NOT sit between password pipe and xfreerdp3 argv.
- Profile format: same 7 keys; token values gain backend docs only.
- Backends beyond hypr/niri/none; source-split backend files (breaks two-file deployment).

## Capabilities

### New Capabilities
- `compositor-backends`: detection contract, canonical monitor shape, adapter semantics, degraded `none` behavior.

### Modified Capabilities
- `engine-robustness`: `require_cmd` drops unconditional `hyprctl` (detection-conditional); `|| true` policy text generalized from named hyprctl dispatchers to cosmetic dispatch wrappers.
- `hidpi-scaling`: scale extraction reads canonical shape; hypr `.[0].scale` becomes adapter-internal (deterministic pick for niri's object-keyed outputs).
- `installer`: dependency matrix covers niri; hyprctl-missing warning generalized.
- `test-harness`: `niri()` bash-function mock (twin of `hyprctl()` mock); structural invariant — no raw `hyprctl`/`niri msg` in engine outside lib backends.

## Approach

Exploration approach 1: normalized-backend layer inside the existing lib — keeps two-file deployment, contains the 3-compositor × 3-mode test matrix at the adapter boundary, makes `none` a natural third backend. Canvas math written once, on canonical logical values.

**Delivery forecast — 3 chained PRs** (400-line budget applies; formal guard lines owned by tasks phase):

| PR | Slice | Est. lines | Budget risk |
|---|---|---|---|
| 1 | Detection + canonical monitors + DPI + adapter/mock tests | ~380 | Medium — at budget |
| 2 | Workspace/launch/focus dispatch + installer + tunables + i18n | ~340 | Low-Medium |
| 3 | Expand geometry (live-verify gate FIRST) + degraded expand + E2E checklist | ~280 | Low |

Each slice: clear start/finish, green `make ci`, installable, independently revertable.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/rdp-common.bash` | Modified | +~150 lines: detect / canonical monitors / dispatch backends |
| `engine/rdp-connect` | Modified | ~60 hyprctl sites → wrappers (groups 1–6) |
| `install-rdp-framework.sh` | Modified | pkg maps, hyprctl warning text |
| `i18n/{es,en}.env` | Modified | new MSG_* pairs |
| `tests/` | New/Modified | `backends.bats`, `niri-api.bats`, canonical-shape fixture migrations |

## Risks

| Risk | Sev | Mitigation |
|---|---|---|
| Hyprland regression across 60 rewritten sites (physical→logical, sort semantics) | High | Adapter fixture tests vs existing JSONs; `hyprland-api.bats` green; manual Hyprland verify per PR |
| Unverified niri geometry semantics (absolute-vs-delta, coords, XWayland app_id) | High | Live-verify task gated BEFORE expand wiring; documented degraded fallback |
| Strict-mode traps: queries must WARN+degrade, never abort; no `|| true` on jq/file tests | Medium | engine-robustness spec delta + bats strict-mode cases |
| Token drift: MONITOR_ID hypr numeric id vs niri output name | Medium | Canonical per-backend token resolution, documented in tunables block |
| Test-matrix size (3 compositors × 3 modes × ordering) | Medium | Canonical-shape contract + chained slices |

## Rollback Plan

Deployed copy is the current engine; per-PR `git revert` + `make install` restores the byte-identical prior engine (installer idempotent; `make verify-manifest` confirms). Slices revert independently.

## Dependencies

- niri ≥ 26.04 (`niri msg --json`, shapes live-probed); `jq` (already required); uwsm exports `NIRI_SOCKET` to children.

## Success Criteria

- [ ] `make ci` green; zero Hyprland behavior change (existing expectations unmodified)
- [ ] Live niri session: monitors, DPI, PREFERRED_WS pin, expand (or documented degraded expand) working E2E
- [ ] Neither compositor: WARN + xfreerdp3 still launches (`/f`, 100%)
- [ ] E2E checklist executed in BOTH compositors (niri live; Hyprland via session toggle)
- [ ] No raw `hyprctl`/`niri msg` in engine outside lib backend functions
