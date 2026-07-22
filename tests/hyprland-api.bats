#!/usr/bin/env bats
# tests/hyprland-api.bats — covers the Hyprland 0.55+ Lua dispatcher migration.
#
# Since Hyprland 0.55, `hyprctl keyword` and the legacy `hyprctl dispatch <x>
# <args>` form are deprecated (the parser is now Lua: `hl.dsp.*` via
# `hyprctl dispatch '<lua>'` / `hyprctl eval`). The engine's old calls
# (`hyprctl keyword windowrulev2 ...`, `hyprctl dispatch focuswindow class:...`)
# were silently no-op / spammy on 0.56.
#
# This file is the structural backstop: it asserts the engine uses the new
# `hl.dsp.*` API and contains NO deprecated `hyprctl keyword` / `focuswindow`
# calls in code. Real compositor execution stays manual-verify (the user
# confirms the window actually moves/focuses/fullscreens).
#
# Migration mapping:
#   focus peer window : hyprctl dispatch 'hl.dsp.focus({ window = "class:..." })'
#   move to workspace : hyprctl dispatch 'hl.dsp.window.move({ workspace, window })
#   fullscreen (single): hyprctl dispatch 'hl.dsp.window.fullscreen({ mode, action, window })

load test_helper

@test "engine_uses_lua_focus_dispatcher_not_legacy_focuswindow" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.focus'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "new hl.dsp.focus dispatcher missing"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'focuswindow'"
  [ "$status" -ne 0 ] || fail "legacy 'focuswindow' still present in CODE"
  assert_output "0"
}

@test "engine_uses_lua_fullscreen_dispatcher_for_single_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.window.fullscreen'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "hl.dsp.window.fullscreen dispatcher missing (single-mode auto-fullscreen)"
}

@test "engine_uses_lua_move_dispatcher_for_workspace" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.window.move'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "hl.dsp.window.move dispatcher missing (PREFERRED_WS assignment)"
}

@test "engine_does_not_use_deprecated_hyprctl_keyword" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # No `hyprctl keyword` in CODE (the 0.56 parser rejects it). The FIXME
  # comments mention it in prose, so strip comments before grepping.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hyprctl keyword'"
  [ "$status" -ne 0 ] || fail "deprecated 'hyprctl keyword' still in CODE"
  assert_output "0"
}
