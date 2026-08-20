# Exploration: compositor-aware — hyprland vs niri detection + dual backend, degraded fallback

`compositor-aware` | explore | 2026-08-19 | Chained follow-up A20 of `niri-omarchy`. Fresh-context investigation; live probes run against niri 26.04 (8ed0da4) in the user's active uwsm session.

## Current State

### Failure mode under niri (confirmed live, installed engine = repo HEAD `4c1e9d8`)

Installed `~/.local/bin/rdp-connect` is **byte-identical** to `engine/rdp-connect` at HEAD (diff verified; the Aug 13 mtime is the install date, engine last committed 2026-08-13). Under niri the engine dies in two places, both reproduced from the user's log:

1. `engine/rdp-connect:125` — `require_cmd hyprctl hyprland` → exit 127 when hyprctl is absent; when hyprctl IS installed (this machine), it passes but…
2. `engine/rdp-connect:802-803` — `_MON_IDS=$(hyprctl monitors -j | jq …)` and `MON_COUNT=$(hyprctl monitors -j | jq '. | length')` are **unguarded under `set -euo pipefail`**. Under niri, `hyprctl monitors -j` prints plain text `HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)` and exits **rc=1** (probed live) → pipefail kills the engine right after the DISABLE_DPI log line. This is the exact death in the user's log (monitor detection).

The engine has 60 `hyprctl` occurrences; `lib/rdp-common.bash` has 1 IPC call (`compute_dpi_flags`).

### Call-site census (A) — functional groups

All line numbers refer to `engine/rdp-connect` (installed = repo, verified identical). "S" marks security-relevant (must not gain `|| true`); "C" marks documented-cosmetic (`|| true` already applied per engine-robustness spec).

| # | Group | Sites (engine:) | Hyprland input consumed | Output produced | Niri equivalent needed |
|---|---|---|---|---|---|
| 1 | **Preflight** | `:125` `require_cmd hyprctl hyprland` (S) | binary on PATH | exit 127 on missing | replace with compositor detection; `niri` binary required only when niri detected |
| 2 | **Monitor detection / ordering** | `:233` `:238` `:245` (expand); `:462` (pre-connect menu); `:802-803` (`_MON_IDS`, `MON_COUNT`); `:850` (single+MONITOR_ID); `:914` `:927` (span); `:976` `:1004` (multi) | `monitors -j`: `.id` (detection-order numeric), `.description`, `.x/.y` (PHYSICAL layout origin), `.width/.height` (PHYSICAL px), `.scale`, `.activeWorkspace.id` | `_MON_IDS`, `MON_COUNT`, `_pm_json`, `_SINGLE_X/_SINGLE_Y`, `_SPAN_W/_SPAN_H/_SPAN_X/_SPAN_Y`, `_MULTI_X/_MULTI_Y`, `_EFF_WS` (via activeWorkspace) | `niri msg --json outputs` — **object keyed by name**, values `{name, make, model, serial, logical:{x,y,width,height,scale,transform}, scale}`. Mapping: hypr `.id` ↔ niri `name` (stable token for selection); `.description` ↔ `make+" "+model+" "+serial`; `.x/.y` ↔ `logical.x/.y` (**already logical**); `.width/.height/scale` ↔ `logical.width/.height` (**already logical — NO `/scale` division needed**, unlike hypr's physical×scale); `.activeWorkspace.id` ↔ derived from `niri msg --json workspaces` (`{id, name, output, is_focused}` → active ws of that output; engine reads ws id OR name) |
| 3 | **DPI/scale** | lib `compute_dpi_flags` (lib:294, called engine:781) (S — lib's ONLY IPC call) | `.[0].scale` of first monitor | `DPI_FLAGS[]`, `IS_HIDPI`, `SCALE_PCT`; null/garbage → WARN + 100% | niri: `logical.scale` (effective; always present, probed `1.0` on all 3) — but outputs JSON is an **object**, so `.[0]` becomes "first after sort/keys" — must pick deterministically (suggest sort by `logical.x`, or `focused-output`). Top-level `scale` is the *configured* scale and is `null` today — use `logical.scale`, not `scale` |
| 4 | **Workspace targeting** | `:828` `_EFF_WS=PREFERRED_WS`; `:865` override from target monitor's activeWorkspace; `:1112` `:1153` `dispatch movetoworkspacesilent "$_EFF_WS,class:$WM_CLASS"` (C) | numeric hypr workspace id | window lands on ws | `niri msg action move-window-to-workspace <ref> --window-id <id>` (**flag is `--window-id`, NOT `--id` — verified live**). Reference = index-or-name; PREFERRED_WS numeric values map to niri *per-output* indexes ambiguously — pass through as reference, document that names are the niri-idiomatic value (user already runs named workspaces from niri-omarchy: mensajeria/ai/terminal…) |
| 5 | **Window poll + expand geometry** | `:223` `:1094` `clients -j` poll by `.class`; `:265-267` (expand) and `:1125-1196` (dispatcher: setfloating / resizewindowpixel / movewindowpixel / fullscreen "0", settle retries) (all C) | `clients -j` `.class == "rdp-$PROFILE"` (`WM_CLASS="rdp-${PROFILE}"`, engine:596); dispatch in **logical** px | window floated, resized exact, moved exact, fullscreened | `niri msg --json windows` — array of `{id, app_id, title, pid, is_floating, is_focused, workspace_id, layout}`. Match by `app_id == WM_CLASS` (**live-verify XWayland app_id↔/wm-class mapping — NOT yet confirmed**; `title` fallback exists). Geometry actions probed live: `move-window-to-floating --id`, `toggle-window-floating --id`, `move-floating-window --id -x <X> -y <Y>` (CHANGE syntax, default `+0` = delta), `set-window-width/set-window-height --id <CHANGE>`, `fullscreen-window --id`, `focus-window --id`. **No single set-window-geometry** → niri expand needs 3 calls (w, h, move) vs hypr's 2; and whether `move-floating-window -x 100` (no `+`) sets ABSOLUTE vs relative, and whether coords are global-logical or output-local, is **unverified — actions mutate the live session, so NOT probed under research-only mandate; must be verified at apply time** |
| 6 | **Cleanup/focus-restore** | `:1115` `dispatch focuswindow "class:$WM_CLASS"` (C) — the only focus-restore call; EXIT trap is pure process-group kill (no hyprctl) | focused window | window focused | `focus-window --id <id>` |
| 7 | **Installer/docs** | `install-rdp-framework.sh:60,71,82` (pkg maps), `:109-119` (Debian hyprctl warning), `:242-248` (docs); `append_tunables_block` comments (lib:602-610) mention hyprctl ids | — | installed deps + user docs | installer must install/require per detected-or-both compositors; tunables block comments must document niri tokens (output names) |

Also affected specs (deltas needed): `engine-robustness` (require_cmd list names hyprctl; `|| true` policy text names specific hyprctl dispatchers), `hidpi-scaling` (scale extraction tied to `hyprctl monitors -j .[0].scale`), `installer` (dependency list includes `hyprland`), `test-harness` (mock strategy), plus new capability for compositor abstraction (or extend engine-robustness).

### Degradation today (precedent for "neither present")

The engine already degrades gracefully in adjacent paths — this is the pattern A20's fallback mode should follow:
- span canvas math fails → `WARN` + `build_mon_flags "$MON_COUNT" "$_MON_IDS"` fallback (engine:953-955);
- MONITOR_ORDER unresolvable → WARN + auto-detection (engine:914-917, 976-979);
- scale unparsable → WARN + 100% (lib compute_dpi_flags);
- no wofi/walker → pre-connect menu silently skipped (engine:461).

## Repo architecture fit (B)

- **Two-file split**: `engine/rdp-connect` (1249 lines, orchestration + all hyprctl IPC inline) sources `lib/rdp-common.bash` (624 lines, pure functions). Bats sources the lib directly; the engine is never executed in tests.
- **Established extraction pattern** (per CLAUDE.md / strict-tdd history): new logic → pure function in lib with dedicated bats file. `hidpi.bats` already mocks `hyprctl` as a **bash function** shadowing PATH (`hyprctl() { printf '%s' "$json"; }`) before calling `compute_dpi_flags` — the exact same mock strategy works for `niri() { … }`, zero harness changes needed.
- `tests/hyprland-api.bats` is **structural**: greps the engine source for classic dispatch forms and asserts absence of `hl.dsp.*`/`hyprctl eval`. A niri twin (`niri-api.bats`) plus a generalized invariant ("engine contains no raw `hyprctl`/`niri msg` outside the lib backend functions") fits this convention.
- Other suites touching hyprctl behavior: `monitor-config` (7 hypr refs), `monitor-mode`, `monitor-order-by-description`, `multi-position`, `span-mode`, `expand-mode`, `precheck-menu`, `hidpi` — most construct monitor JSON inline. **Test-matrix containment strategy**: normalize at the lib boundary (backends emit ONE canonical monitors shape) so engine-level tests run against the canonical shape only; per-backend adapter tests are small and additive (fixture JSON in → canonical out).

## Detection strategy (C) — probed live

| Probe | Under niri (live) | Under hyprland (from history) |
|---|---|---|
| `HYPRLAND_INSTANCE_SIGNATURE` | unset | set |
| `NIRI_SOCKET` | set (`/run/user/1000/niri.wayland-1.1437.sock`, uwsm-finalized: `UWSM_FINALIZE_VARNAMES=NIRI_SOCKET …` — inherited by all children incl. keybind-launched rdp-connect) | unset |
| `XDG_CURRENT_DESKTOP` | `niri` | `Hyprland` (cheap hint only) |
| `hyprctl monitors -j` | rc=1, plain text `HYPRLAND_INSTANCE_SIGNATURE not set!` | rc=0, JSON |
| `niri msg version` | rc=0 (also returns compositor build) | rc=1 `error connecting to the niri socket` |
| `niri msg` w/o `NIRI_SOCKET` | rc=1 same error — env var is the discovery mechanism; glob fallback `/run/user/$UID/niri*.sock` works (path embeds wayland display + PID; multiple stale sockets possible → probe each or take newest) | — |

**Recommended detection**: order candidates by hints (env vars first), then **connectivity+JSON-validity probe** (`hyprctl monitors -j | jq -e .` / `niri msg --json outputs | jq -e .`) — rc alone is insufficient (both fail rc=1 on the wrong compositor). First backend whose probe yields valid JSON wins; none → `COMPOSITOR=none` degraded mode.

**Degraded (`none`) semantics** (mirrors existing fallbacks): no workspace pin, no float/fullscreen/geometry dispatch, no pre-connect monitor menu (skip like the no-wofi path), `MON_COUNT=1` → `build_mon_flags 1` → `/f`, DPI → existing 100% WARN path, **xfreerdp3 still launches** with full security pipeline. Log one WARN naming the mode. `require_cmd` for the compositor binary becomes conditional on detection result instead of unconditional hyprctl.

## Approaches

1. **Normalized-backend layer in lib (adapter pattern)** — lib gains: `detect_compositor()` (probes, sets `COMPOSITOR`), `get_monitors_json()` (per-backend query → emits ONE canonical shape: `[{id, desc, x, y, w, h, scale, ws_ref}]`, logical coords, stable id token), `compositor_dispatch_*` thin wrappers (float/resize/move/fullscreen/focus/move-to-ws) taking window ref + logical geometry, each internally no-op-with-WARN when `COMPOSITOR=none`. Engine call sites swap `hyprctl …` for the wrapper; canvas math stays in engine but operates on canonical logical values (hypr adapter does the `/scale` conversion; niri adapter passes `logical.*` through).
   - Pros: engine logic (precedence, canvas math, settle retries) written ONCE; test matrix stays ~1× per behavior + small adapter tests; matches the established lib-extraction pattern; `none` falls out naturally as a no-op backend; hyprland-api.bats structural tests generalize cleanly.
   - Cons: biggest single change (~60 sites touched, even if mechanically); canonical shape is a new contract to spec; hypr behavior must be proven unchanged (regression risk on the currently-working path).
   - Effort: **High** (but the only approach that avoids 2× everything).

2. **Inline if/else per call site** (`if [ "$COMPOSITOR" = niri ]; then niri msg …; else hyprctl …; fi` at each of the ~25 logical sites).
   - Pros: no new abstraction; each site is locally obvious.
   - Cons: 2× logic in the engine; canvas math subtly duplicated (physical-vs-logical division in one branch only); test matrix doubles per mode; violates the repo's own lib-extraction pattern; drift between branches guaranteed over time.
   - Effort: Medium per site, High aggregate, poor maintainability.

3. **Source-separated backend files** (`lib/rdp-backends/hyprland.bash`, `niri.bash`, `none.bash`; engine sources one after detection).
   - Pros: cleanest separation; none.bash tiny.
   - Cons: breaks the deployed **two-file** model (installer ships exactly `engine/rdp-connect` + `lib/rdp-common.bash`; manifest/sha256/tamper-check + smoke test all assume it); installer + specs churn beyond the engine change.
   - Effort: Medium-High + installer rework.

## Recommendation

**Approach 1** (normalized-backend layer inside the existing `lib/rdp-common.bash`). It is the only option that keeps the two-file deployment intact, matches the strict-TDD lib-extraction pattern, contains the test-matrix explosion at the adapter boundary, and makes the A20 "neither present" fallback a natural third backend instead of sprinkled conditionals. Ship detection+backend first (hypr parity + niri monitors/DPI/workspace), then geometry dispatch, then expand-mode — sliceable into chained PRs under the 400-line guard.

## Risks

- **HIGH — regression on the working Hyprland path**: 60 call sites are rewritten behind wrappers; hypr's physical→logical division and `sort_by(.x)` semantics must survive verbatim. Mitigation: adapter unit tests with the existing fixture JSONs + structural `hyprland-api.bats` kept green; manual verify on Hyprland before archive.
- **HIGH — unverified niri geometry semantics**: `move-floating-window` absolute-vs-delta syntax, global-vs-output-local coords, and XWayland `app_id`↔`/wm-class` mapping are all UNVERIFIED (actions mutate the live session; not probed under research-only mandate). Mitigation: dedicated live-verification task at apply time BEFORE wiring expand-mode; document degraded expand (float + set-window-width/height per selected output) if positioning proves impossible.
- **MEDIUM — strict-mode traps**: current unguarded sites (engine:233/238/802/803) kill the engine on any compositor hiccup; the new layer must make ALL compositor queries WARN+degrade (never abort), while keeping the `|| true` policy spec text truthful (engine-robustness delta required — it currently names specific hyprctl dispatchers). Do NOT let wrappers gain `|| true` around `jq`/file tests.
- **MEDIUM — profile-key semantics drift**: `MONITOR_ID`/`MONITOR_ORDER` numeric tokens are hypr detection-order ids; niri's stable token is the output NAME (DP-2) and desc = make+model+serial (two identical Dells disambiguate ONLY by serial — same ambiguity class as hypr today). Canonical layer must define token resolution per backend and document it in `append_tunables_block` text (lib:602-610 mentions hyprctl ids explicitly).
- **MEDIUM — test-matrix size**: 3 compositors × 3 monitor modes × ordering overrides. Contained by the canonical-shape contract; forecast chained PRs (this change alone will exceed 400 lines).
- **LOW — i18n**: no existing MSG mentions hypr (grepped); new user-facing strings need es+en pairs through `parse_env_safe` i18n mode.
- **LOW — deployed drift**: none today (installed == HEAD verified); keep installing via `make install` per task checklist.
- Security invariants **untouched** by design: `parse_env_safe` allowlist, `/from-stdin:force` piping, `setsid --wait` re-exec, lockfile never-unlink, `"${ARR[@]}"` expansion rule — the compositor layer must not appear between the password pipe and xfreerdp3 argv assembly.

## Ready for Proposal

**Yes.** All A–E questions answered with live evidence except three deliberately-deferred niri geometry live-verifications (flagged above as apply-time tasks). Orchestrator should tell the user: recommended approach is the lib-level normalized backend layer, delivered as chained PRs (1: detection+monitors+DPI, 2: workspace/launch dispatch, 3: expand-mode geometry), with the niri geometry live-verify task gated BEFORE PR 3.
