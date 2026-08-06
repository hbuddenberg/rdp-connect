#!/usr/bin/env bats
# tests/hyprland-api.bats — covers the hyprctl dispatch calls used for
# post-launch window management (positioning, floating, fullscreen).
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
# This file is the structural backstop: it asserts the engine uses the
# classic dispatcher forms and contains NO `hl.dsp.*`/`hyprctl eval` calls.
# Real compositor execution stays manual-verify for anything beyond what was
# directly confirmed above (this project's established convention for
# hyprctl calls — see README).
#
# Confirmed dispatcher forms:
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

@test "engine_uses_classic_focuswindow_dispatcher" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch focuswindow'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic focuswindow dispatcher missing"
}

@test "engine_uses_classic_fullscreen_dispatcher_for_single_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch fullscreen \"0\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic fullscreen dispatcher (mode 0) missing (single-mode auto-fullscreen)"
}

@test "engine_uses_classic_setfloating_dispatcher" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch setfloating'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic setfloating dispatcher missing"
}

@test "engine_uses_classic_exact_pixel_move_and_resize_for_span_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch movewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic movewindowpixel dispatcher missing (span/multi/expand positioning)"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch resizewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic resizewindowpixel dispatcher missing (span/expand sizing)"
}

@test "engine_uses_classic_move_to_workspace_dispatcher" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch movetoworkspacesilent'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic movetoworkspacesilent dispatcher missing (PREFERRED_WS assignment)"
}

@test "engine_does_not_use_lua_hl_dsp_api" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # hl.dsp.* / hyprctl eval only work with the OPTIONAL Lua config manager —
  # confirmed NOT active here ("Invalid dispatcher" / "eval is only
  # supported with the lua config manager"). Must never reappear in CODE.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.'"
  [ "$status" -ne 0 ] || fail "Lua hl.dsp.* call present in CODE — confirmed non-functional on this project's target (classic config)"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hyprctl eval'"
  [ "$status" -ne 0 ] || fail "'hyprctl eval' present in CODE — confirmed non-functional on this project's target (classic config)"
  assert_output "0"
}

@test "engine_does_not_use_deprecated_hyprctl_keyword" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # `hyprctl keyword` is unrelated to dispatch (it's for reloading config
  # keywords at runtime) and was never needed by this engine — kept as a
  # regression guard from the original baseline-hardening change.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hyprctl keyword'"
  [ "$status" -ne 0 ] || fail "deprecated 'hyprctl keyword' still in CODE"
  assert_output "0"
}
