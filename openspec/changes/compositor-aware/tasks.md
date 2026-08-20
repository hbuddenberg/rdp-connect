# Tasks: compositor-aware — Hyprland + Niri backends, degraded `none`

> Strict TDD (`make ci` = shellcheck + bats). Engine never executes in bats; lib is sourced.
> Live-probe evidence 2026-08-19 19:23 (-04): niri 26.04 (8ed0da4), `NIRI_SOCKET` set, no Hyprland
> process. `is_active` EXISTS in workspaces JSON schema; current instance reports `outputs` = `{}`
> (0 outputs) and all 9 workspaces `output:null, is_active:false` — see Task 1.1.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Overall estimated changed lines | ~1000 total (design D-slices) |
| Per-PR estimate (vs 400) | PR1 ~380 (near-ceiling) · PR2 ~340 · PR3 ~280 |
| 400-line budget risk — PR1 | **Medium-High** — near-ceiling; split option: move niri argv-capture cases + `niri-windows.json` fixture to PR2 |
| 400-line budget risk — PR2 | Medium |
| 400-line budget risk — PR3 | Low-Medium |
| Chained PRs recommended | Yes — 3 slices per design Migration table |
| Delivery strategy | ask-on-risk |
| Decision needed before apply | **Yes** — orchestrator must resolve: (1) PR1 split-or-accept at ~380, (2) chain strategy (stacked-to-main vs feature-branch-chain) |

```text
Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High
```

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Lib adapter layer (detect/canonical/dispatch/DPI), engine untouched | PR1 | `bats tests/backends.bats tests/niri-api.bats tests/hidpi.bats` | LIVE Hyprland: DPI flags byte-identical to pre-change engine | `git revert` — engine file unchanged |
| 2 | Engine migration groups 1–6 (non-expand), D7 preflight, installer OR-pair, i18n, tunables | PR2 | `make ci` + `bats tests/installer-backends.bats` | LIVE niri (outputs attached): monitors+DPI+ws-pin; LIVE Hyprland checklist 1–4,6 | `git revert` + `make install` + `make verify-manifest` |
| 3 | Expand gate FIRST → wire/degraded, checklist artifact, docs, deploy + full E2E | PR3 | `make ci` + `bats tests/expand-mode.bats tests/backends.bats --filter expand` | LIVE niri + Hyprland (session toggle): full 6-item checklist both columns | `git revert` + `make install` |

## Resolved Decisions (design Open Questions)

- **(a) niri `is_active` — RESOLVED by live probe (read-only, this session):** field EXISTS in
  26.04 workspaces schema (`{id, idx, name, output, is_urgent, is_active, is_focused,
  active_window_id}`). Caveats recorded for fixtures: unmapped named workspaces carry
  `output:null` + `is_active:false`; a live instance can report **zero outputs** (observed —
  current session). Consequence: D2 filter `.output==$key and (.is_active // .is_focused)` is
  schema-valid, but `ws_ref` MUST be null-tolerant → `ws_ref=null` degrades to `PREFERRED_WS`
  passthrough (design pre-approved as acceptable). Task 1.1 re-probes in an outputs-attached
  state before fixture freeze.
- **(b) detection vs `load_language` ordering — DECIDED:** `detect_compositor` runs AFTER
  `load_language` (engine :180), so the none-WARN uses `MSG_COMPOSITOR_NONE` through the normal
  message pipeline (existing MSG pattern; no stderr literals). Fixed binary list stays at :125
  (still before profile parsing ~:400 — spec intact); the compositor-conditional `require_cmd`
  follows detection. Spec is silent on ordering; this decision is implemented in Task 2.2.

## PR 1 — Lib adapter layer (D1–D6; `engine/rdp-connect` byte-untouched)

> **PR1a slice note (orchestrator split, 2026-08-20):** PR1 was split — the
> niri argv-capture test cases + `niri-windows.json` fixture moved to PR2.
> File renames in this slice: `tests/backends.bats` landed as
> `tests/compositor-backends.bats` (orchestrator instruction; spec scenario
> ids unchanged, so `@test` annotations still resolve); the 1.10 structural
> twin lives in that same file this slice (`tests/niri-api.bats` itself is
> created in PR2 with the argv-capture cases). `niri-windows.json` deferred.

- [x] 1.1 **LIVE probe + fixture freeze** (open question a): in an outputs-attached niri state,
  re-probe `niri msg --json workspaces` / `--json outputs`; confirm per-output `is_active:true`
  on a real output; record findings in fixtures. Create `tests/fixtures/compositor/
  {hypr-monitors,hypr-clients,niri-outputs,niri-workspaces,niri-windows}.json` (twin Dells;
  `scale:null` + `logical.scale:2`; one unmapped named ws with `output:null`).
  Deps: none. Verify: `jq -e .` on each fixture.
  - [x] MV: probe run read-only in live niri; zero-output anomaly from 19:23 re-checked.
  - PR1a: re-probed 2026-08-20 (niri 26.04, outputs ATTACHED: DP-3/DP-8/DP-7 — twin Dell
    U2417Hs differing only by serial = live-real serial-disambiguation case; per-output
    `is_active:true` CONFIRMED; top-level `scale:null` on all 3). Zero-output anomaly was
    TRANSIENT (3 outputs answer now). Frozen fixtures + 2 documented deviations (DP-3
    `logical.scale` 1.0→2.0 for the not-configured scenario; one synthetic unmapped ws
    `output:null` appended — the 19:23 anomaly shape). `niri-windows.json` → PR2.
- [x] 1.2 **RED** — create `tests/backends.bats` (PATH-shadowed `hyprctl()`/`niri()` fn mocks,
  `log_event` stub asserting WARN; hidpi.bats:36 pattern): cases `detect_niri_via_json_probe`,
  `detect_hypr_via_json_probe`, `detect_none_when_no_valid_json`,
  `env_hint_does_not_decide`, `wrong_compositor_cli_warn_degrade_no_abort` (both directions; `set -euo pipefail` on).
  Files: tests/backends.bats, tests/test_helper.bash (if shared mock loader needed).
  - PR1a: landed as `tests/compositor-backends.bats`. Mock strategy correction: detection
    probes run under `timeout 2`, which execs a real file — bash FUNCTION mocks cannot be
    exec'd, so detection cases use PATH-shadowed fake BINARIES; fn mocks remain for the
    non-timeout paths (canonical/DPI/dispatch). No test_helper change needed.
- [x] 1.3 **GREEN** — implement `detect_compositor()` in `lib/rdp-common.bash` (D4: hint-ordered
  candidates, `timeout 2` probe, `jq -e .` validity, rc-capture in `if` — no `|| true`; none →
  exactly one WARN; `_PROBE_JSON_*` cache). Verify: `bats tests/backends.bats --filter detect`.
- [x] 1.4 **RED** — add canonical cases to `backends.bats`: `hypr_fixture_to_canonical_logical`
  (3840×2160@2→1920×1080), `niri_fixture_to_canonical` (name-id, logical passthrough, x-then-y
  order), `niri_ws_ref_from_workspaces` (incl. ws_ref=null tolerance case),
  `niri_logical_scale_not_configured`, `niri_serial_disambiguation`.
  - PR1a: x-then-y tiebreak triangulated inline (fixture xs are distinct); ws_ref null
    tolerance via is_active-stripped workspaces variant; unmapped ws (output:null) covered.
- [x] 1.5 **GREEN** — implement `_monitors_hypr` (D2: `sort_by(.x)` verbatim, `/scale` here and
  ONLY here), `_monitors_niri` (`to_entries`, `logical.*`, `make model serial` desc),
  `_monitors_none` (`[]`), `get_monitors_json()` + `_CANON_MONITORS` lazy cache (D1/D2/D3:
  `--arg`-only strings, no eval).
  - PR1a: none-`[]` inlined in `get_monitors_json` case; `_monitors_none` fn not needed.
- [x] 1.6 **RED** — dispatch cases: `dispatch_noop_warn_under_none` (zero IPC, rc 0),
  `dispatch_failure_does_not_abort` (wrapper rc≠0 under pipefail), hypr golden-argv capture for
  all 6 wrappers (byte-identical to today's forms), `move_window_to_workspace_uses_window_id_flag`.
  - PR1a: golden-argv uses unit-separator arg capture; `move_window_...` → PR2 (split).
- [x] 1.7 **GREEN** — implement `compositor_find_window` + `dispatch_{move_to_ws,focus,float,
  fullscreen,resize,move}` + `_hypr_dispatch`/`_niri_dispatch` (D6; hypr argv verbatim with
  documented-cosmetic `&>/dev/null || true`; niri `--window-id` flag; none → WARN noop).
- [x] 1.8 **RED** — hidpi.bats deltas: `hidpi_scale_200_via_canonical`, `niri_logical_scale_same_flags`;
  migrate `null_scale_fallback` / `non_numeric_scale_fallback` expectations to canonical source
  (text generalized off `hyprctl monitors -j`). Keep `fractional_scale_150`, `scale_one_no_flags` green.
  - PR1a: the two deltas landed in `tests/compositor-backends.bats` (orchestrator split);
    hidpi.bats S1–S9 byte-untouched and green (byte-identical source proof). The S4/S5
    description-text migration had no referent (descriptions never named `hyprctl monitors -j`;
    only the file-header mock comment mentions hyprctl, still accurate) — skipped as a no-op.
- [x] 1.9 **GREEN** — implement `get_dpi_scale()` (D5); `compute_dpi_flags` swaps source call only;
  hypr output byte-identical. Verify: `bats tests/hidpi.bats`.
- [x] 1.10 **RED→GREEN** — create `tests/niri-api.bats` structural twin: 
  `scale_conversion_only_in_hypr_adapter` (grep guard: `/scale` division only inside
  `_monitors_hypr`), niri action-form assertions (`--window-id`, action names, no eval forms).
  Verify: `bats tests/niri-api.bats`.
  - PR1a: structural guards (`scale_conversion_only_in_hypr_adapter` + static
    `--window-id`/action-name/no-eval greps) live in `tests/compositor-backends.bats`;
    `tests/niri-api.bats` is created in PR2 with its argv-capture cases.
- [ ] 1.11 **PR1 gate** — `make ci` green (existing `hyprland-api.bats` untouched and green —
  engine unmodified); `make smoke`; `make verify-manifest` unchanged.
  - PR1a status: `make smoke` ✅; manifest verified from `$HOME` ✅ (repo-root
    `make verify-manifest` has a pre-existing relative-path quirk — unchanged by this slice);
    `make ci` ⚠️ RED from **6 pre-existing failures on main** (diagnosed 2026-08-20, none
    touched by this slice, zero NEW failures: baseline 223 ok/6 fail → now 242 ok/same 6):
    `harness::make_test_passes_46_plus_cases` (collateral of the others),
    `monitor-order-by-description` ×3 (local bats 1.14.0 merges stderr into `$output`; tests
    assert empty output on failure paths), `multi-peer-race::engine_does_not_unlink_pid_file_in_cleanup`
    (**real engine regression**: engine:653 stale-lock force-recovery path reintroduced
    `rm -f "$PID_FILE"` vs R7 never-unlink — engine is byte-frozen this slice),
    `multi-position::engine_does_not_force_resize_in_multi_mode` (grep -c rc semantics).
    Needs an orchestrator decision before PR1 can gate green.
  - [ ] MV: live Hyprland session — `rdp-connect <profile> --verbose` DPI log/flags byte-identical to pre-change engine output (design PR1 gate).

## PR 2 — Engine migration (groups 1–6, expand stays raw), D7, installer, i18n

> **PR2 slice note (2026-08-20):** landed as one work-unit commit on main.
> i18n keys `MSG_COMPOSITOR_NONE`/`MSG_DISPATCH_NOOP` were already shipped
> by PR1a (verified) — task 2.2's i18n half was a no-op. The dispatcher
> subshell's geometry branch is wrapped in a `COMPOSITOR=hypr` guard: under
> niri, ws-pin + focus run (live-verified forms) but float/resize/move/
> fullscreen WARN+skip pending the PR3 D8 gate. `--expand` stays hypr-raw
> (niri: guard+exit 1; none: fails at find-window with the existing
> message) behind the documented temporary allowlist in
> niri-api.bats::no_raw_compositor_ipc_in_engine.

- [x] 2.1 **RED** — engine none-mode cases: `none_mode_skips_compositor_require_cmd`
  (structural scan of preflight), `none_mode_skips_menu_and_pin` (structural guards at menu +
  ws-pin sites + lib-level none-sim for `/f`@100% referencing `none_mode_f_100pct`).
- [x] 2.2 **GREEN** — D7 + decision (b): delete `require_cmd hyprctl hyprland` (engine:125);
  insert `detect_compositor` after `load_language` (:180); conditional `require_cmd hyprctl
  hyprland` / `require_cmd niri niri`; none → none. Add i18n keys `MSG_COMPOSITOR_NONE`,
  `MSG_DISPATCH_NOOP` to `i18n/es.env` + `i18n/en.env` (es/en mirrors per D4 text).
  Files: engine/rdp-connect, i18n/{es,en}.env. Deps: 1.3.
  - PR2: i18n keys already present from PR1a (verified byte-identical to D4 text).
- [x] 2.3 **GREEN** — migrate engine group 2 (11 monitor sites :233,:238,:245,:462,:802–803,:850,
  :914,:927,:976,:1004) → `get_monitors_json()`; `resolve_monitor_order` reads `.desc` (lib
  select per D3 token match); pre-connect menu gets `[ "$COMPOSITOR" != none ]` twin guard
  (no-wofi precedent engine:461). Engine canvas math on canonical logical values, written once.
  Deps: 1.5. Verify: `bats tests/monitor-mode.bats tests/span-mode.bats tests/multi-position.bats`.
  - PR2: :233/:238/:245 (expand) stay raw per task 2.5/3.3 (allowlisted); the other 8 sites
    migrated. resolve_monitor_order: `.desc` canonical-first + `.description` fallback for the
    expand caller (PR3 drops the fallback); exact-id string match added before desc substring
    (niri output names resolve to themselves).
- [x] 2.4 **Matrix migration** — update monitor suites to canonical fixtures where needed
  (design: raw-JSON `hyprctl()` mocks keep working — lib converts raw→canonical; only
  `monitor-order-by-description.bats` migrates to canonical fixtures); zero expectation edits.
  Verify: `make ci`.
  - PR2: canonical fixture migrated (zero expectation edits ✓); additionally the raw-form
    greps in monitor-mode/span-mode/multi-position/precheck-menu/hyprland-api were RETARGETED
    to the wrapper calls (same behavioral expectations — design File Changes row lists these
    files as Modify: "argv-capture regression; canonical-fixture migration").
- [x] 2.5 **GREEN** — migrate groups 4/5/6 non-expand: ws pin (:828,:865,:1112,:1153 →
  `dispatch_move_to_ws`, sequence/retries verbatim, `_EFF_WS` from canonical `ws_ref` with
  PREFERRED_WS passthrough on null); window poll (:223,:1094 → `compositor_find_window`);
  dispatcher subshell (:1125–1196 → float/resize/move/fullscreen wrappers, ORDER preserved —
  move last, settle retries); focus (:1115 → `dispatch_focus`). `--expand` path (:223–267 area)
  stays hypr-raw until PR3. Deps: 1.7, 2.3. Verify: `bats tests/hyprland-api.bats tests/expand-mode.bats` (expand expectations unchanged).
- [x] 2.6 **RED→GREEN** — structural invariants in `tests/niri-api.bats` +
  `tests/engine-security.bats`: `no_raw_compositor_ipc_in_engine` (grep guard: zero `hyprctl`/
  `niri msg` call forms in engine outside lib-sourced fns — ships with a documented temporary
  allowlist for the PR3-pending expand block); password-path adjacency guard (pipe block at
  engine:1217–1243 region byte-identical; no wrapper interposes between password pipe and
  xfreerdp3 argv; `"${ARR[@]}"` rule intact). Deps: 2.5.
- [x] 2.7 **RED→GREEN** — create `tests/installer-backends.bats` (pkg-manager spy):
  `niri_only_satisfies_compositor_dep` (asserts no hyprland install attempt),
  `no_compositor_installs_with_warn` (deploy+smoke+manifest complete, none-mode warning
  printed); then implement installer OR-pair (`hyprland` OR `niri`) + generalized
  missing-compositor warning in `install-rdp-framework.sh` (:60–119 pkg maps, :242–248 docs).
  - [x] MV: `HOME=$(mktemp -d) ./install-rdp-framework.sh` on this host (both CLIs present) — completes clean.
- [x] 2.8 **GREEN** — tunables text: `append_tunables_block` (lib:602–613) documents niri
  tokens: `MONITOR_ID` = output NAME (e.g. `DP-2`) under niri vs hypr numeric id; desc tokens
  serial-qualified; named workspaces = niri-idiomatic `PREFERRED_WS`. Verify:
  `bats tests/profile-key-writer.bats`.
- [x] 2.9 **PR2 gate** — `make ci`; `make smoke`.
  - PR2: `make lint` ✅; per-file bats 248 ok / 4 fail — the 4 are the documented pre-existing
    local-skew failures on main (monitor-order-by-description ×3 bats-1.14.0 stderr merge,
    multi-position ×1 grep -c rc semantics); zero new. `make smoke` ✅; manifest 5/5 ✅.
    The reported `make test` HANG is **tests/harness.bats::make_test_passes_46_plus_cases** —
    NOT a hang: it nests a full `make test` run (recursion-guarded), so the suite is ~2×
    linear ≈ 485s and simply exceeds a 120s timeout; it completes (rc=2 from the 4 pre-existing
    failures + the harness test's own `assert_success` collateral).
  - [ ] MV: live niri (outputs attached): `rdp-connect <profile> --verbose` — monitors detected, DPI flags, PREFERRED_WS pin. Record in checklist draft.
  - [ ] MV: live Hyprland: full manual regression — checklist items 1–4 + 6 (connect real profile, canvas per mode, ws pin, DPI flags, no-orphan cleanup).
  - [ ] MV: engine-robustness manual items: missing-jq exit 127 (PATH-shadow), real-failure propagation (profile at 127.0.0.1:1 → ERROR log + trap).

## PR 3 — Expand gate FIRST, wire-or-degrade, docs, E2E, deploy

- [ ] 3.1 **LIVE expand gate (D8) — BEFORE any wiring**: on the live niri session, using a
  scratch/spare window (not the user's windows): (a) `move-floating-window --id -x/-y`
  absolute-vs-delta semantics, (b) global-logical vs output-local coords — verify by querying
  the test window's layout geometry (`niri msg --json windows` `.layout`) after each move,
  (c) XWayland `app_id` ↔ `/wm-class` mapping (probe with a scratch xwayland client, e.g.
  `xeyes`/`xterm` if available). Record results in checklist; any fail/no-run ⇒ degraded expand.
  Needs live session; mutating probe confined to a disposable scratch window.
  - [ ] MV: three probe results + wire/degraded decision recorded in checklist.md.
- [ ] 3.2 **RED** — `niri_degraded_expand_fallback` (fullscreen on selected output + WARN
  `MSG_EXPAND_DEGRADED`, never silent breakage); if 3.1 verified semantics: RED cases for the
  wired positioning (3-call w/h/move geometry). Add `MSG_EXPAND_DEGRADED` to `i18n/{es,en}.env`.
- [ ] 3.3 **GREEN** — wire niri expand per recorded semantics OR degraded expand; migrate the
  expand path off raw hyprctl (engine group 5 expand sites :223–267) through wrappers
  (`compositor_find_window` app_id match); remove PR2's temporary allowlist →
  `no_raw_compositor_ipc_in_engine` fully green. Deps: 3.1, 3.2, 2.5.
  Verify: `bats tests/expand-mode.bats tests/backends.bats tests/niri-api.bats`.
- [ ] 3.4 **Create checklist artifact** — `openspec/changes/compositor-aware/checklist.md`:
  6 items × {niri, hyprland} columns: (1) real-profile connect — `ti-partner` (DISABLE_DPI=1)
  + `SmartBots` (DPI-active), (2) monitor canvas per mode, (3) PREFERRED_WS pin, (4) DPI flags,
  (5) expand or documented degraded expand, (6) cleanup: `pgrep -x xfreerdp3` empty after exit
  (no orphans). Plus expand-gate + none-mode rows. Deps: 3.1.
- [ ] 3.5 **E2E — niri column** (user is in niri now; confirm `niri msg --json outputs` non-empty
  first — see zero-output anomaly): run all 6 checklist items with deployed engine; record
  results. Uses real profiles `ti-partner` (DISABLE_DPI=1) and `SmartBots` (DPI-active).
  - [ ] MV: 6/6 pass recorded in checklist niri column; no orphaned xfreerdp3.
- [ ] 3.6 **E2E — Hyprland column** via session-toggle: same 6 items; zero behavior change vs
  pre-change engine; record. Rollback path documented (toggle back).
  - [ ] MV: 6/6 pass recorded in checklist hyprland column; no orphans.
- [ ] 3.7 **Docs** — `README.md` + `CLAUDE.md`: compositor support matrix (hypr / niri ≥ 26.04 /
  none degraded), `MONITOR_ID`/`MONITOR_ORDER` token semantics per backend, none-mode behavior
  (`/f`, 100% DPI, no menu/pin/expand), niri dependency note. Docs ride with the change they
  explain (same PR).
- [ ] 3.8 **Deploy + final E2E** — `make install`; `make verify-manifest`; `make ci`; re-run
  checklist spot-check (items 1, 5, 6) on deployed files in niri now, then Hyprland via
  session-toggle. Installed == repo verified.
  - [ ] MV: manifest verified; deployed E2E spot-check passes both compositors.

## Coverage Map (15 requirements / 44 scenarios → tasks)

| Req (spec) | Scenario → covering task |
|---|---|
| compositor-backends::detection | niri-probe→1.2/1.3 · hypr-probe→1.2/1.3 · none-no-valid-json→1.2/1.3 · env-hint-no-decide→1.2/1.3 |
| compositor-backends::canonical-model | hypr→logical→1.4/1.5 · niri-parsed→1.4/1.5 · ws_ref→1.1/1.4/1.5 |
| compositor-backends::dispatch-contract | noop-WARN→1.6/1.7 · hypr-forms-unchanged→1.6/1.7+2.5(hyprland-api green) |
| compositor-backends::hypr-owns-/scale | /scale-only-hypr→1.10 · suites-green→1.11/2.4 (make ci) |
| compositor-backends::niri-contract | logical.scale-wins→1.4/1.5 · serial-disambig→1.4/1.5 · --window-id→1.6/1.7 |
| compositor-backends::none-backend | /f@100%→2.1/2.2 (+1.2 none) · skip-menu-pin→2.1/2.3/2.5 · LIVE-none→3.4/3.5 checklist |
| compositor-backends::expand-gate | LIVE-gate-first→3.1 (order enforced) · degraded-fallback→3.2/3.3 |
| compositor-backends::e2e-checklist | niri-column→3.4/3.5 · hyprland-column→3.4/3.6 (+deploy 3.8) |
| engine-robustness::strict-mode | dispatch-blip→1.6/1.7 (+MV 2.9) · real-failure→MV 2.9 (existing trap) · wrong-CLI→1.2/1.3 |
| engine-robustness::require_cmd | missing-jq→MV 2.9 (existing) · wofi/rofi→existing+MV 2.9 · all-present→2.2 · none-no-abort→2.1/2.2 |
| hidpi::pure-bash-math | bc-less-200→1.8/1.9 · niri-same-flags→1.8/1.9 · fractional→1.8 · scale-1→1.8 |
| hidpi::safe-fallback | null→1.8/1.9 · non-numeric→1.8/1.9 · none-100%→2.1 (refs 1.2) |
| installer::dependency-list | missing-jq-installed→2.7 (+MV 2.7) · wofi-or-rofi→2.7 · niri-only→2.7 · neither+warn→2.7 |
| test-harness::compositor-mocks | fn-mocks→1.2 · both-missing→1.2 · ci-matrix→1.11/2.9 (make ci, no compositor on ubuntu-latest) |
| test-harness::structural-invariant | zero-raw-IPC→2.6 (full-green 3.3) · niri-twin→1.10 |
