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
#   float (single/span): hyprctl dispatch 'hl.dsp.window.float({ action, window })
#   move by coords (span): hyprctl dispatch 'hl.dsp.window.move({ x, y, window })
#   set prop (span)     : hyprctl dispatch 'hl.dsp.window.set_prop({ prop, value, window })

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

@test "engine_uses_lua_float_dispatcher_for_single_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.window.float'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "hl.dsp.window.float dispatcher missing (single-mode floating window for cross-monitor drag/resize)"
}

@test "engine_uses_lua_coord_move_and_set_prop_dispatchers_for_span_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Span mode needs an absolute-pixel move (x/y), distinct from the existing
  # workspace-based hl.dsp.window.move({ workspace = ... }) call — assert the
  # coord form specifically.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.window.move({ x ='"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "hl.dsp.window.move coord form missing (span-mode positioning)"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'hl.dsp.window.set_prop'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "hl.dsp.window.set_prop dispatcher missing (span-mode noborder/noblur/noshadow)"
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
