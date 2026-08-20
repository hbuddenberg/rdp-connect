#!/usr/bin/env bats
# tests/niri-api.bats — compositor-aware change, PR2 (tasks 1.10 argv-capture
# residue + 2.6 structural invariants).
#
# Spec provenance:
#   openspec/changes/compositor-aware/specs/compositor-backends/spec.md
#     - ::niri-contract "move-to-workspace uses the --window-id flag"
#       (@test move_window_to_workspace_uses_window_id_flag)
#     - ::hypr-owns-/scale "/scale monitor conversion appears only in the
#       hypr adapter" (@test scale_conversion_only_in_hypr_adapter — moved
#       here from compositor-backends.bats in PR2 so the spec annotation
#       resolves to this file, per tasks 1.10's original intent)
#   openspec/changes/compositor-aware/specs/test-harness/spec.md
#     - "Structural invariant — compositor IPC only in lib backends"
#       (@test no_raw_compositor_ipc_in_engine)
#
# Two test kinds live here:
#   1. argv-capture cases over the lib dispatch wrappers under
#      COMPOSITOR=niri (PR1a shipped the wrappers; these are the
#      golden-argv locks that were split out of PR1 to keep its review
#      budget — they are approval/regression tests over existing lib
#      behavior, plus the engine-side structural guards that go RED until
#      the PR2 engine migration lands).
#   2. structural greps over engine/rdp-connect proving the migrated launch
#      path calls the wrappers and contains zero raw compositor IPC outside
#      the documented, PR3-pending --expand allowlist.

load test_helper

setup() {
  # Scrub compositor state (this file runs on a live niri host where
  # NIRI_SOCKET is exported); COMPOSITOR is set per-test explicitly.
  unset COMPOSITOR _PROBE_JSON_HYPR _PROBE_JSON_NIRI _CANON_MONITORS _WIN_TOKEN
  unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
}

_niri_windows_json() { cat "${TESTS_DIR}/fixtures/compositor/niri-windows.json"; }
_niri_outputs_json()  { cat "${TESTS_DIR}/fixtures/compositor/niri-outputs.json"; }
_niri_workspaces_json() { cat "${TESTS_DIR}/fixtures/compositor/niri-workspaces.json"; }

# ============================================================================
# Dispatch argv capture (spec compositor-backends::niri-contract)
# ============================================================================

@test "move_window_to_workspace_uses_window_id_flag" {
  # Spec: with a matched window id 42 and ws ref 3 under COMPOSITOR=niri,
  # the wrapper's argv is `msg action move-window-to-workspace <ref>
  # --window-id <id>` (flag is --window-id, NOT --id — live-verified) and
  # the move also focuses the target workspace. Args captured with a
  # unit-separator join so arg boundaries are preserved.
  COMPOSITOR=niri
  WM_CLASS="rdp-test"
  _WIN_TOKEN=42
  local cap="${BATS_TEST_TMPDIR}/argv.cap"
  : > "${cap}"
  niri() { local IFS=$'\037'; printf '%s\n' "$*" >> "${cap}"; }
  dispatch_move_to_ws "3"
  [ "$(grep -c '' "${cap}")" = "2" ]
  [ "$(sed -n 1p "${cap}")" = $'msg\037action\037move-window-to-workspace\0373\037--window-id\03742' ]
  [ "$(sed -n 2p "${cap}")" = $'msg\037action\037focus-workspace\0373' ]
}

@test "move_window_to_workspace_named_ref_is_one_argv_token" {
  # Triangulation: a niri NAMED workspace (with an embedded space) must
  # travel as ONE quoted argv token, never word-split or eval'd.
  COMPOSITOR=niri
  WM_CLASS="rdp-test"
  _WIN_TOKEN=42
  local cap="${BATS_TEST_TMPDIR}/argv.cap"
  : > "${cap}"
  niri() { local IFS=$'\037'; printf '%s\n' "$*" >> "${cap}"; }
  dispatch_move_to_ws "ws con espacio"
  [ "$(sed -n 1p "${cap}")" = $'msg\037action\037move-window-to-workspace\037ws con espacio\037--window-id\03742' ]
  [ "$(sed -n 2p "${cap}")" = $'msg\037action\037focus-workspace\037ws con espacio' ]
}

@test "niri_find_window_matches_app_id_and_caches_token" {
  # compositor_find_window under niri: matches by app_id over
  # `niri msg --json windows` (fixture = live shape: app_id/id/is_floating/
  # is_focused/layout/pid/title/workspace_id) and caches the numeric id in
  # _WIN_TOKEN — the --window-id token the dispatch wrappers consume.
  COMPOSITOR=niri
  niri() {
    case "$3" in
      windows) _niri_windows_json ;;
    esac
  }
  compositor_find_window "rdp-test"
  [ "${_WIN_TOKEN:-}" = "42" ]
  # Triangulation: a different app resolves to ITS id (not a stale one).
  compositor_find_window "foot"
  [ "${_WIN_TOKEN:-}" = "7" ]
  # Negative: an absent class must fail the poll (engine treats rc as "not yet").
  run compositor_find_window "rdp-absent"
  [ "$status" -ne 0 ]
}

@test "niri_focus_and_geometry_action_argv" {
  # Golden argv for the remaining wrappers under niri (live-probed action
  # forms, design D6): focus-window --id, move-window-to-floating --id,
  # fullscreen-window --id, set-window-width/height --id (niri has no single
  # set-window-geometry — resize is two calls), move-floating-window -x/-y.
  COMPOSITOR=niri
  WM_CLASS="rdp-test"
  _WIN_TOKEN=42
  local cap="${BATS_TEST_TMPDIR}/argv.cap"
  : > "${cap}"
  niri() { local IFS=$'\037'; printf '%s\n' "$*" >> "${cap}"; }
  dispatch_focus
  dispatch_float
  dispatch_fullscreen
  dispatch_resize "2560" "1440"
  dispatch_move "1920" "0"
  [ "$(grep -c '' "${cap}")" = "6" ]
  [ "$(sed -n 1p "${cap}")" = $'msg\037action\037focus-window\037--id\03742' ]
  [ "$(sed -n 2p "${cap}")" = $'msg\037action\037move-window-to-floating\037--id\03742' ]
  [ "$(sed -n 3p "${cap}")" = $'msg\037action\037fullscreen-window\037--id\03742' ]
  [ "$(sed -n 4p "${cap}")" = $'msg\037action\037set-window-width\037--id\03742\0372560' ]
  [ "$(sed -n 5p "${cap}")" = $'msg\037action\037set-window-height\037--id\03742\0371440' ]
  [ "$(sed -n 6p "${cap}")" = $'msg\037action\037move-floating-window\037--id\03742\037-x\0371920\037-y\0370' ]
  # The resize emits TWO calls (width + height); move emits ONE:
  [ "$(grep -c 'set-window-width' "${cap}")" = "1" ]
  [ "$(grep -c 'set-window-height' "${cap}")" = "1" ]
  [ "$(grep -c 'move-floating-window' "${cap}")" = "1" ]
}

@test "resolve_monitor_order_supports_niri_name_ids" {
  # PR2 lib change: resolve_monitor_order reads the CANONICAL `.desc` field
  # (design D3 token match `(.id|tostring)==$tok` — hypr numeric ids AND
  # niri output names both work). Built from the live-shape niri fixtures
  # through the real adapter chain (get_monitors_json), then resolved.
  COMPOSITOR=niri
  niri() {
    case "$3" in
      outputs)     _niri_outputs_json ;;
      workspaces)  _niri_workspaces_json ;;
    esac
  }
  local canon
  canon=$(get_monitors_json)
  # Description substring over niri canonical (make model serial):
  run resolve_monitor_order "$canon" "ASUSTek"
  assert_success
  [ "$output" = "DP-8" ]
  # Niri output NAME token resolves to itself (string id):
  run resolve_monitor_order "$canon" "DP-3"
  assert_success
  [ "$output" = "DP-3" ]
  # Mixed name + description tokens, selector order preserved:
  run resolve_monitor_order "$canon" "ASUSTek,DP-3"
  assert_success
  [ "$output" = "DP-8,DP-3" ]
}

# ============================================================================
# Engine structural invariants (PR2 engine migration — spec test-harness)
# ============================================================================

@test "engine_critical_dispatch_sites_use_wrappers" {
  # Spot-assert (design: "Engine hypr path: adapters emit byte-identical
  # hyprctl argv (wrappers guarantee; spot-assert 3 critical sites)") that
  # the migrated engine calls the wrappers at the three geometry-critical
  # sites: ws pin, span resize, single move. The byte-identical hypr argv
  # itself is locked by compositor-backends.bats::dispatch_golden_argv_hypr_forms.
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  grep -qF 'dispatch_move_to_ws "$_EFF_WS"' "$engine" \
    || fail "ws-pin site does not call dispatch_move_to_ws"
  grep -qF 'dispatch_resize "${_SPAN_W:-0}" "${_SPAN_H:-0}"' "$engine" \
    || fail "span resize site does not call dispatch_resize"
  grep -qF 'dispatch_move "${_SINGLE_X:-0}" "${_SINGLE_Y:-0}"' "$engine" \
    || fail "single move site does not call dispatch_move"
}

@test "no_raw_compositor_ipc_in_engine" {
  # Spec test-harness: "Engine source has zero raw compositor IPC sites"
  # outside lib-sourced backend functions.
  #
  # TEMPORARY ALLOWLIST (PR2 of compositor-aware): the --expand block stays
  # hypr-raw until PR3 wires it through the wrappers behind the D8 live-
  # verification gate (PR3 task 3.3 removes this allowlist AND the raw
  # block). The sed range below deletes exactly that block before scanning.
  # `require_cmd` lines are excluded from the scan: naming a CLI binary for
  # a PATH check is not an IPC call (the D7 case-arm form `hypr) require_cmd
  # hyprctl hyprland` does not START with require_cmd, so the exclusion
  # matches the token anywhere in the line).
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  local offenders
  offenders=$(sed '/== "--expand" ]; then$/,/^fi$/d' "$engine" \
    | grep -vE '^[[:space:]]*#' \
    | grep -v 'require_cmd' \
    | grep -nE 'hyprctl|niri msg' || true)
  [ -z "$offenders" ] \
    || fail "raw compositor IPC in engine outside the allowlisted --expand block: ${offenders}"
  # Guard the guard: the allowlisted block must still EXIST and still carry
  # the raw forms — if the block moves/disappears, the sed above becomes
  # vacuous and this test must fail rather than pass silently.
  local block
  block=$(sed -n '/== "--expand" ]; then$/,/^fi$/p' "$engine")
  [ -n "$block" ] || fail "--expand block not found — allowlist deletion is vacuous"
  [ "$(printf '%s\n' "$block" | grep -c 'hyprctl')" -ge 3 ] \
    || fail "allowlisted --expand block no longer contains the expected raw hyprctl sites"
}

# ============================================================================
# Structural twins moved from compositor-backends.bats (PR2 — spec
# annotations name niri-api.bats as their home; tasks 1.10)
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

@test "niri_action_forms_static_guard" {
  # The lib must carry the live-verified niri action forms and contain NO
  # eval — compositor strings only ever travel as quoted argv tokens / jq
  # --arg.
  local lib="${LIB_FILE}"
  grep -qF 'move-window-to-workspace "$ws" --window-id "$_WIN_TOKEN"' "$lib" \
    || fail "workspace move must use the --window-id flag form (live-verified; --id is wrong)"
  grep -qF 'focus-workspace "$ws"' "$lib" || fail "workspace move must also focus the target workspace"
  run grep -nE '\beval [^ ]' "$lib"
  [ "$status" -ne 0 ] || fail "eval must never appear in the lib: $output"
}
