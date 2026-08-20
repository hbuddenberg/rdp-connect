#!/usr/bin/env bats
# tests/hyprland-api.bats — structural backstop for the hyprctl dispatch
# forms used for post-launch window management (positioning, floating,
# fullscreen).
#
# CORRECTED (was wrong from the original baseline-hardening change onward):
# Hyprland 0.55+ added an OPTIONAL Lua config manager (`hl.dsp.*` via
# `hyprctl eval`), but classic hyprlang config + the classic
# `hyprctl dispatch <dispatcher> <args>` form remain fully supported and are
# what a non-Lua-config Hyprland instance actually understands. This project
# targets classic config. Verified LIVE against a running rdp-* window on
# Hyprland 0.56.1 (classic config):
#   - `hyprctl dispatch "hl.dsp.window.move({...})"` -> "Invalid dispatcher"
#   - `hyprctl eval "..."` -> "eval is only supported with the lua config manager"
#   - `hyprctl dispatch movewindowpixel "exact 1920 0,class:rdp-ti-partner"` -> "ok",
#     confirmed via `hyprctl clients -j` (window actually moved)
#
# RETARGETED in compositor-aware PR2: the engine's launch-path dispatch now
# goes through the lib wrappers (lib/rdp-common.bash::_hypr_dispatch call
# sites), so the classic-form assertions grep the LIB — the emitted hyprctl
# argv is byte-identical and additionally regression-locked by
# compositor-backends.bats::dispatch_golden_argv_hypr_forms. The engine's
# remaining raw classic forms (the PR3-pending --expand block) are covered
# by expand-mode.bats and allowlisted in niri-api.bats. The negative
# assertions (no Lua hl.dsp.*, no hyprctl eval/keyword) scan BOTH files.
#
# Confirmed dispatcher forms (asserted against the lib):
#   focus peer window      : hyprctl dispatch focuswindow "class:..."
#   move to workspace      : hyprctl dispatch movetoworkspacesilent "<ws>,class:..."
#   float (force on)       : hyprctl dispatch setfloating "class:..."
#   fullscreen (single)    : hyprctl dispatch fullscreen "0"  (no window arg —
#                             acts on the focused window; mode 0 = true
#                             edge-to-edge fullscreen, mode 1 = maximize)
#   move by exact pixels   : hyprctl dispatch movewindowpixel "exact <x> <y>,class:..."
#   resize by exact pixels : hyprctl dispatch resizewindowpixel "exact <w> <h>,class:..."
#
# NOT confirmed / dropped: `hyprctl setprop <window> <noborder|noblur|...> 1`
# returned "unknown request" for every property name tried live on this
# build — span/multi mode no longer attempt it (see engine comments).

load test_helper

@test "lib_uses_classic_focuswindow_dispatcher" {
  local lib="${LIB_FILE}"
  [ -f "$lib" ] || fail "lib missing at $lib"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch focuswindow'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic focuswindow dispatcher missing from lib _hypr_dispatch site"
}

@test "lib_uses_classic_fullscreen_dispatcher_for_single_mode" {
  local lib="${LIB_FILE}"
  [ -f "$lib" ] || fail "lib missing at $lib"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch fullscreen \"0\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic fullscreen dispatcher (mode 0) missing from lib (single-mode auto-fullscreen)"
}

@test "lib_uses_classic_setfloating_dispatcher" {
  local lib="${LIB_FILE}"
  [ -f "$lib" ] || fail "lib missing at $lib"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch setfloating'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic setfloating dispatcher missing from lib _hypr_dispatch site"
}

@test "lib_uses_classic_exact_pixel_move_and_resize_for_span_mode" {
  local lib="${LIB_FILE}"
  [ -f "$lib" ] || fail "lib missing at $lib"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch movewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic movewindowpixel dispatcher missing from lib (span/multi/expand positioning)"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch resizewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic resizewindowpixel dispatcher missing from lib (span/expand sizing)"
}

@test "lib_uses_classic_move_to_workspace_dispatcher" {
  local lib="${LIB_FILE}"
  [ -f "$lib" ] || fail "lib missing at $lib"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'dispatch movetoworkspacesilent'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic movetoworkspacesilent dispatcher missing from lib (PREFERRED_WS assignment)"
}

@test "engine_and_lib_do_not_use_lua_hl_dsp_api" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  local lib="${LIB_FILE}"
  [ -f "$engine" ] || fail "engine missing at $engine"
  [ -f "$lib" ] || fail "lib missing at $lib"
  # hl.dsp.* / hyprctl eval only work with the OPTIONAL Lua config manager —
  # confirmed NOT active here ("Invalid dispatcher" / "eval is only
  # supported with the lua config manager"). Must never reappear in CODE,
  # in the engine OR the lib backend layer.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.'"
  [ "$status" -ne 0 ] || fail "Lua hl.dsp.* call present in ENGINE CODE — confirmed non-functional on this project's target (classic config)"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hyprctl eval'"
  [ "$status" -ne 0 ] || fail "'hyprctl eval' present in ENGINE CODE — confirmed non-functional on this project's target (classic config)"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'hl.dsp.'"
  [ "$status" -ne 0 ] || fail "Lua hl.dsp.* call present in LIB CODE"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'hyprctl eval'"
  [ "$status" -ne 0 ] || fail "'hyprctl eval' present in LIB CODE"
  assert_output "0"
}

@test "engine_and_lib_do_not_use_deprecated_hyprctl_keyword" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  local lib="${LIB_FILE}"
  [ -f "$engine" ] || fail "engine missing at $engine"
  [ -f "$lib" ] || fail "lib missing at $lib"
  # `hyprctl keyword` is unrelated to dispatch (it's for reloading config
  # keywords at runtime) and was never needed by this engine — kept as a
  # regression guard from the original baseline-hardening change, now
  # scanning the lib backend layer too.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hyprctl keyword'"
  [ "$status" -ne 0 ] || fail "deprecated 'hyprctl keyword' still in ENGINE CODE"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$lib' | grep -cF 'hyprctl keyword'"
  [ "$status" -ne 0 ] || fail "deprecated 'hyprctl keyword' still in LIB CODE"
  assert_output "0"
}
