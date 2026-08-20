# tests/compositor-backends.bats — compositor-aware change, PR slice 1a
#
# Spec: openspec/changes/compositor-aware/specs/compositor-backends/spec.md
# (the @test names below are the spec scenario ids, verbatim, so the spec's
# annotations resolve; the file tasks.md 1.2 calls tests/backends.bats was
# renamed to compositor-backends.bats per the orchestrator's PR1a split).
#
# PR1a slice: lib adapter layer ONLY — detection, canonical monitor model,
# DPI source, dispatch wrappers. The niri argv-capture cases and the
# niri-windows.json fixture are PR2 (moved out of this slice).
#
# Mock strategy (two kinds, by necessity):
#   - DETECTION tests use PATH-shadowed FAKE BINARIES (executable scripts in
#     a temp dir prepended to PATH): detect_compositor probes through
#     `timeout 2 <cli> ...`, and timeout(1) must exec a real file — a bash
#     function mock cannot be exec'd, so the hidpi.bats function-mock
#     pattern is unusable on the probe path.
#   - CANONICAL/DPI/DISPATCH tests call lib fns that invoke the CLIs WITHOUT
#     timeout (post-detection, cache-first), so plain function mocks
#     (hidpi.bats:33 pattern) shadowing hyprctl()/niri() work there.
#
# Fixtures: tests/fixtures/compositor/ — niri-outputs/niri-workspaces frozen
# from a LIVE read-only probe (2026-08-20, niri 26.04 8ed0da4, outputs
# attached: DP-3/DP-8/DP-7 — twin Dell U2417Hs disambiguated ONLY by serial,
# top-level scale:null on every output, per-output is_active:true confirmed;
# the 2026-08-19 19:23 zero-output anomaly was re-checked: transient — 3
# outputs answered now). Two documented deviations from the raw probe, both
# required by spec scenarios: DP-3 logical.scale 1.0→2.0
# (niri_logical_scale_not_configured needs logical.scale:2 vs scale:null),
# and one synthetic unmapped workspace (output:null — the 19:23 anomaly
# shape) appended to workspaces. hypr fixtures mirror the same physical desk
# in hyprctl monitors -j shape (id0 3840x2160@2 → canonical 1920x1080).

load test_helper

setup() {
  # Scrub compositor state + session hints: this file runs on a live niri
  # host where NIRI_SOCKET/XDG_CURRENT_DESKTOP are exported — detection MUST
  # be tested against controlled hints only.
  unset COMPOSITOR _PROBE_JSON_HYPR _PROBE_JSON_NIRI _CANON_MONITORS _WIN_TOKEN
  unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# _setup_fakebin — create the fake-binary dir and prepend it to PATH.
_setup_fakebin() {
  FAKEBIN="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "${FAKEBIN}"
  export PATH="${FAKEBIN}:${PATH}"
}

# _fake_cli <name> <payload> <rc> — write a fake CLI that prints <payload>
# to stdout and exits <rc>. Payload is embedded with %q quoting, so
# multi-line JSON is safe.
_fake_cli() {
  printf '#!/usr/bin/env bash\nprintf %%s %q\nexit %s\n' "$2" "$3" > "${FAKEBIN}/$1"
  chmod +x "${FAKEBIN}/$1"
}

_hypr_monitors_json() { cat "${TESTS_DIR}/fixtures/compositor/hypr-monitors.json"; }
_niri_outputs_json()  { cat "${TESTS_DIR}/fixtures/compositor/niri-outputs.json"; }
_niri_workspaces_json() { cat "${TESTS_DIR}/fixtures/compositor/niri-workspaces.json"; }
_hypr_clients_json()  { cat "${TESTS_DIR}/fixtures/compositor/hypr-clients.json"; }

# ============================================================================
# Detection (spec: compositor-backends::detection — 4 scenarios)
# ============================================================================

@test "detect_niri_via_json_probe" {
  _setup_fakebin
  _fake_cli niri "$(_niri_outputs_json)" 0
  _fake_cli hyprctl 'HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)' 1
  detect_compositor
  [ "$COMPOSITOR" = "niri" ]
  [ -n "${_PROBE_JSON_NIRI:-}" ]
}

@test "detect_hypr_via_json_probe" {
  _setup_fakebin
  _fake_cli hyprctl "$(_hypr_monitors_json)" 0
  _fake_cli niri 'error connecting to the niri socket' 1
  detect_compositor
  [ "$COMPOSITOR" = "hypr" ]
  # jq -e . normalizes (pretty-prints) its input, so compare canonicalized
  # forms — the cache must carry the probe's JSON, not the raw file bytes.
  [ "$(printf '%s' "${_PROBE_JSON_HYPR:-}" | jq -c .)" = "$(_hypr_monitors_json | jq -c .)" ]
}

@test "detect_none_when_no_valid_json" {
  _setup_fakebin
  _fake_cli hyprctl 'HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)' 1
  _fake_cli niri 'error connecting to the niri socket' 1
  export MSG_COMPOSITOR_NONE="TEST-MSG-NONE"
  local warn_log="${BATS_TEST_TMPDIR}/warn.log"
  : > "${warn_log}"
  export _WARN_LOG="${warn_log}"
  # Child bash under set -euo pipefail: proves "no jq parse crash, engine
  # continues" (spec scenario wording) — a plain-text rc=1 answer from both
  # CLIs must land in COMPOSITOR=none with EXACTLY one WARN.
  run bash -c 'set -euo pipefail
    source "$1"
    log_event() { printf "%s\t%s\n" "$1" "$2" >> "${_WARN_LOG}"; }
    detect_compositor
    printf "COMPOSITOR=%s" "$COMPOSITOR"' _ "${LIB_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "COMPOSITOR=none" ]
  [ "$(grep -c . "${warn_log}")" = "1" ]
  grep -q "$(printf 'WARN\tTEST-MSG-NONE')" "${warn_log}"
}

@test "env_hint_does_not_decide" {
  _setup_fakebin
  export XDG_CURRENT_DESKTOP="niri" NIRI_SOCKET="/run/user/1000/niri.wayland-1.fake.sock"
  # Hint points at niri, but the niri CLI answers rc=0 GARBAGE (worse than
  # rc=1: a lying CLI) and hyprctl answers valid monitors JSON.
  _fake_cli niri 'totally-not-json' 0
  _fake_cli hyprctl "$(_hypr_monitors_json)" 0
  run bash -c 'set -euo pipefail
    source "$1"
    detect_compositor
    printf "COMPOSITOR=%s" "$COMPOSITOR"' _ "${LIB_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "COMPOSITOR=hypr" ]
}

@test "wrong_compositor_cli_warn_degrade_no_abort" {
  # Both directions, set -euo pipefail on (tasks 1.2). A wrong-compositor
  # plain-text rc=1 answer is the NORMAL state of the other CLI and must
  # never abort detection; the winner is decided on JSON evidence only.
  _setup_fakebin
  _fake_cli hyprctl "$(_hypr_monitors_json)" 0
  _fake_cli niri 'error connecting to the niri socket' 1
  run bash -c 'set -euo pipefail
    source "$1"
    detect_compositor
    printf "%s" "$COMPOSITOR"' _ "${LIB_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "hypr" ]
  _fake_cli niri "$(_niri_outputs_json)" 0
  _fake_cli hyprctl 'HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)' 1
  run bash -c 'set -euo pipefail
    source "$1"
    detect_compositor
    printf "%s" "$COMPOSITOR"' _ "${LIB_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "niri" ]
}

# ============================================================================
# Canonical monitor model (spec: compositor-backends::canonical-model +
# ::niri-contract) — function mocks only; adapters call the CLIs without
# timeout, cache-first.
# ============================================================================

@test "hypr_fixture_to_canonical_logical" {
  COMPOSITOR=hypr
  hyprctl() { _hypr_monitors_json; }
  local canon w
  canon=$(get_monitors_json)
  [ "$(printf '%s' "$canon" | jq '. | length')" = "3" ]
  # Physical→logical applied ONCE, inside the adapter: 3840x2160@2 → 1920x1080.
  [ "$(printf '%s' "$canon" | jq -r '.[0].w')" = "1920" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].h')" = "1080" ]
  [ "$(printf '%s' "$canon" | jq '.[0].scale == 2')" = "true" ]
  # id/desc/x/y/ws_ref semantics: detection-order id, description verbatim,
  # x/y passthrough (hypr already reports logical origins), activeWorkspace.id.
  [ "$(printf '%s' "$canon" | jq -r '.[0].id')" = "0" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].desc')" = "Dell Inc. DELL U2417H XVNNT6BTAPBL" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].x')" = "0" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].y')" = "0" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].ws_ref')" = "6" ]
  # sort_by(.x) verbatim: canonical order is 0 (x=0), 1 (x=1920), 2 (x=4480);
  # the unscaled monitors (scale 1) keep their physical == logical size.
  [ "$(printf '%s' "$canon" | jq -r '[.[].id] | @csv')" = "0,1,2" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].w')" = "2560" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].h')" = "1440" ]
  [ "$(printf '%s' "$canon" | jq '.[1].scale == 1')" = "true" ]
}

@test "niri_fixture_to_canonical" {
  COMPOSITOR=niri
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  local canon
  canon=$(get_monitors_json)
  [ "$(printf '%s' "$canon" | jq '. | length')" = "3" ]
  # id = output NAME; logical.* passes through UNCONVERTED; x-order 0,1920,4480.
  [ "$(printf '%s' "$canon" | jq -r '[.[].id] | @csv')" = '"DP-3","DP-8","DP-7"' ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].w')" = "1920" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].h')" = "1080" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].w')" = "2560" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].h')" = "1440" ]
  # x-then-y tiebreak (same x, different y → y decides) — inline triangulation
  # so the fixture's distinct-x case doesn't leave the second sort key untested.
  local tie='{"B":{"logical":{"x":0,"y":720}},"A":{"logical":{"x":0,"y":0}}}'
  [ "$(printf '%s' "$tie" | jq -c '[to_entries | sort_by(.value.logical.x, .value.logical.y) | .[].key]')" = '["A","B"]' ]
}

@test "niri_ws_ref_from_workspaces" {
  COMPOSITOR=niri
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  local canon
  canon=$(get_monitors_json)
  # Per-output ACTIVE workspace name (is_active on real outputs — live-probed):
  # DP-3 → silencio, DP-8 → musica (also is_focused), DP-7 → mensajeria.
  [ "$(printf '%s' "$canon" | jq -r '.[0].ws_ref')" = "silencio" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].ws_ref')" = "musica" ]
  [ "$(printf '%s' "$canon" | jq -r '.[2].ws_ref')" = "mensajeria" ]
  # Null tolerance (live 19:23 finding): an output whose workspaces are all
  # inactive reports ws_ref=null (engine degrades to PREFERRED_WS passthrough),
  # and the unmapped named workspace (output:null) is never selected.
  local stripped
  stripped=$(jq '[.[] | (if .output == "DP-3" then .is_active = false else . end)]' \
    "${TESTS_DIR}/fixtures/compositor/niri-workspaces.json")
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  printf '%s' "$stripped" ;;
    esac
  }
  _CANON_MONITORS=""
  canon=$(get_monitors_json)
  [ "$(printf '%s' "$canon" | jq -r '.[0].ws_ref')" = "null" ]
  [ "$(printf '%s' "$canon" | jq -r '.[1].ws_ref')" = "musica" ]
}

@test "niri_logical_scale_not_configured" {
  COMPOSITOR=niri
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  # Fixture carries top-level scale:null on every output; canonical scale MUST
  # come from logical.scale (effective) — DP-3 has logical.scale=2 → scale=2.
  local canon
  canon=$(get_monitors_json)
  [ "$(printf '%s' "$canon" | jq '.[0].scale == 2')" = "true" ]
  [ "$(printf '%s' "$canon" | jq '.[1].scale == 1')" = "true" ]
}

@test "niri_serial_disambiguation" {
  COMPOSITOR=niri
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  # Twin Dell U2417Hs (live hardware) differ ONLY by serial — desc MUST be
  # "make model serial" so the two Dells are distinct tokens.
  local canon dells
  canon=$(get_monitors_json)
  dells=$(printf '%s' "$canon" | jq -r '[.[].desc | select(contains("DELL U2417H"))] | length')
  [ "$dells" = "2" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].desc')" = "Dell Inc. DELL U2417H XVNNT6BTAPBL" ]
  [ "$(printf '%s' "$canon" | jq -r '.[2].desc')" = "Dell Inc. DELL U2417H J75VK884B7ZL" ]
  [ "$(printf '%s' "$canon" | jq -r '.[0].desc')" != "$(printf '%s' "$canon" | jq -r '.[2].desc')" ]
}

@test "detect_caches_winning_probe_json" {
  _setup_fakebin
  _fake_cli hyprctl "$(_hypr_monitors_json)" 0
  _fake_cli niri 'error connecting to the niri socket' 1
  detect_compositor
  [ "$COMPOSITOR" = "hypr" ]
  # Flip the fake's answer AFTER detection: canonical must come from the
  # probe cache, proving ≤1 monitor IPC per run (D4).
  _fake_cli hyprctl '[]' 0
  local canon
  canon=$(COMPOSITOR=hypr get_monitors_json)
  [ "$(printf '%s' "$canon" | jq '. | length')" = "3" ]
}

# ============================================================================
# Structural (spec: compositor-backends::hypr-owns-/scale; tasks 1.10 residue
# — the niri argv-capture half of 1.10 is PR2)
# ============================================================================

@test "scale_conversion_only_in_hypr_adapter" {
  local lib="${LIB_FILE}"
  # Every division-by-.scale in the lib must live inside _monitors_hypr's
  # body (reads like .[0].scale or logical.scale are not divisions — the
  # regex demands a slash, optionally spaced, immediately before .scale).
  local body first_line last_line match_line offending=""
  body=$(awk '/^_monitors_hypr\(\) \{/,/^\}/' "$lib")
  [ -n "$body" ] || fail "_monitors_hypr not found in lib"
  first_line=$(grep -n '^_monitors_hypr() {' "$lib" | cut -d: -f1)
  last_line=$((first_line + $(printf '%s\n' "$body" | grep -c '') - 1))
  while IFS= read -r match_line; do
    [ -z "$match_line" ] && continue
    if [ "$match_line" -lt "$first_line" ] || [ "$match_line" -gt "$last_line" ]; then
      offending="${offending}${match_line} "
    fi
  done < <(grep -nE '/[[:space:]]*\.scale' "$lib" | cut -d: -f1)
  [ -z "$offending" ] || fail "/.scale division outside _monitors_hypr at lines: ${offending}"
  # The conversion itself must EXIST in the adapter (w and h divisions).
  [ "$(printf '%s\n' "$body" | grep -cE '/[[:space:]]*\.scale')" -ge 2 ]
}

# ============================================================================
# DPI (spec: hidpi::pure-bash-math via the new backend-internal source,
# design D5; tasks 1.8 deltas live here per the orchestrator's PR1a split)
# ============================================================================

@test "hidpi_scale_200_via_canonical" {
  # COMPOSITOR=hypr: compute_dpi_flags sources its scale through get_dpi_scale
  # (detection-order .[0] of the raw hypr array — byte-identical semantics to
  # the legacy direct hyprctl call). Fixture .[0] is scale 2 → 200%.
  COMPOSITOR=hypr
  unset DISABLE_DPI
  local -a warn_lines=()
  hyprctl() { _hypr_monitors_json; }
  log_event() {
    if [[ "$1" == "WARN" ]]; then warn_lines+=("$2"); fi
  }
  compute_dpi_flags
  [ "$IS_HIDPI" = "1" ]
  [ "$SCALE_PCT" = "200" ]
  [ "${DPI_FLAGS[*]}" = "/scale-desktop:200" ]
  [ "${#warn_lines[@]}" = "0" ]
}

@test "niri_logical_scale_same_flags" {
  # COMPOSITOR=niri: the SAME /scale-desktop:200 flags must come out of the
  # niri backend (leftmost canonical monitor = DP-3, logical.scale 2 — the
  # effective scale, never top-level scale:null).
  COMPOSITOR=niri
  unset DISABLE_DPI
  local -a warn_lines=()
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  log_event() {
    if [[ "$1" == "WARN" ]]; then warn_lines+=("$2"); fi
  }
  compute_dpi_flags
  [ "$IS_HIDPI" = "1" ]
  [ "$SCALE_PCT" = "200" ]
  [ "${DPI_FLAGS[*]}" = "/scale-desktop:200" ]
  [ "${#warn_lines[@]}" = "0" ]
}

# ============================================================================
# Dispatch contract (spec: compositor-backends::dispatch-contract — D6).
# The niri argv-capture cases (move_window_to_workspace_uses_window_id_flag
# etc.) are PR2; PR1a proves the hypr forms byte-identical + none no-op +
# failure tolerance.
# ============================================================================

@test "hypr_find_window_poll_matches_class" {
  COMPOSITOR=hypr
  hyprctl() { _hypr_clients_json; }
  compositor_find_window "rdp-demo"
  run compositor_find_window "rdp-absent"
  [ "$status" -ne 0 ]
}

@test "dispatch_golden_argv_hypr_forms" {
  # Byte-identical regression lock: under COMPOSITOR=hypr the wrappers must
  # emit EXACTLY today's engine hyprctl argv (engine:1112/1115/1125/1132/
  # 1133/1140 forms). Args are captured with a unit-separator join so arg
  # boundaries are preserved (an arg containing spaces stays one arg).
  COMPOSITOR=hypr
  WM_CLASS="rdp-test"
  local cap="${BATS_TEST_TMPDIR}/argv.cap"
  : > "${cap}"
  hyprctl() { local IFS=$'\037'; printf '%s\n' "$*" >> "${cap}"; }
  dispatch_move_to_ws "3"
  dispatch_focus
  dispatch_float
  dispatch_fullscreen
  dispatch_resize "2560" "1440"
  dispatch_move "1920" "0"
  [ "$(grep -c '' "${cap}")" = "6" ]
  [ "$(sed -n 1p "${cap}")" = $'dispatch\037movetoworkspacesilent\0373,class:rdp-test' ]
  [ "$(sed -n 2p "${cap}")" = $'dispatch\037focuswindow\037class:rdp-test' ]
  [ "$(sed -n 3p "${cap}")" = $'dispatch\037setfloating\037class:rdp-test' ]
  [ "$(sed -n 4p "${cap}")" = $'dispatch\037fullscreen\0370' ]
  [ "$(sed -n 5p "${cap}")" = $'dispatch\037resizewindowpixel\037exact 2560 1440,class:rdp-test' ]
  [ "$(sed -n 6p "${cap}")" = $'dispatch\037movewindowpixel\037exact 1920 0,class:rdp-test' ]
}

@test "dispatch_noop_warn_under_none" {
  # Spec: under COMPOSITOR=none every wrapper logs WARN, performs NO IPC,
  # and returns success. Tripwire CLIs fail the test if touched.
  COMPOSITOR=none
  WM_CLASS="rdp-test"
  export MSG_DISPATCH_NOOP="TEST-MSG-NOOP"
  local -a warn_lines=()
  local -a ipc_fired=()
  hyprctl() { ipc_fired+=("hyprctl:$*"); return 0; }
  niri()    { ipc_fired+=("niri:$*");    return 0; }
  log_event() {
    if [[ "$1" == "WARN" ]]; then warn_lines+=("$2"); fi
  }
  dispatch_move_to_ws "3"
  dispatch_focus
  dispatch_float
  dispatch_fullscreen
  dispatch_resize "2560" "1440"
  dispatch_move "1920" "0"
  [ "${#warn_lines[@]}" = "6" ]
  local w
  for w in "${warn_lines[@]}"; do
    [ "$w" = "TEST-MSG-NOOP" ]
  done
  [ "${#ipc_fired[@]}" = "0" ]
}

@test "dispatch_failure_does_not_abort" {
  # A failing compositor CLI under set -euo pipefail must not kill the
  # caller (documented-cosmetic dispatch class — engine-robustness policy).
  run bash -c 'set -euo pipefail
    source "$1"
    COMPOSITOR=hypr
    WM_CLASS="rdp-test"
    hyprctl() { return 1; }
    dispatch_move_to_ws "3"
    dispatch_focus
    dispatch_float
    dispatch_fullscreen
    dispatch_resize "2560" "1440"
    dispatch_move "1920" "0"
    printf "SURVIVED"' _ "${LIB_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "SURVIVED" ]
}

@test "niri_action_forms_static_guard" {
  # tasks 1.10 structural residue (the argv-capture half is PR2): the lib
  # must carry the live-verified niri action forms and contain NO eval —
  # compositor strings only ever travel as quoted argv tokens / jq --arg.
  local lib="${LIB_FILE}"
  grep -qF 'move-window-to-workspace "$ws" --window-id "$_WIN_TOKEN"' "$lib" \
    || fail "workspace move must use the --window-id flag form (live-verified; --id is wrong)"
  grep -qF 'focus-workspace "$ws"' "$lib" || fail "workspace move must also focus the target workspace"
  run grep -nE '\beval [^ ]' "$lib"
  [ "$status" -ne 0 ] || fail "eval must never appear in the lib: $output"
}

