#!/usr/bin/env bats
# tests/span-mode.bats — covers MONITOR_MODE=span / --span: unifying N
# physical monitors into ONE floating xfreerdp3 window sized to their
# combined canvas (the "3 monitores como si fuera uno solo" case).
#
# Unlike single (one remote monitor, fullscreened) and multi (/multimon, one
# window per FreeRDP's own layout), span computes an explicit /size:<W>x<H>
# canvas from hyprctl monitors -j at RUNTIME (width = sum of selected
# monitors' widths, height = MAX of their heights — takes the FULL resolution
# of the tallest selected monitor, e.g. a 1440p center between two 1080p
# monitors gets its full 1440 height; the 1080p monitors then only display
# the top 1080 rows of that shared canvas, since they have no physical pixels
# below that — this is a hard display-hardware limit, not a bug), then floats
# + resizes + moves the window to the selected monitors' origin via the
# CLASSIC hyprctl dispatch forms (setfloating / resizewindowpixel exact /
# movewindowpixel exact — see tests/hyprland-api.bats for why classic, not
# Lua hl.dsp.*, is correct here). noborder/noblur/noshadow were dropped:
# `hyprctl setprop` returned "unknown request" for every property name tried
# live on the target Hyprland build.
#
# Monitor selection reuses the SAME precedence as multi mode (MONITOR_ORDER /
# MONITORS / --monitor-order / --monitors) — no new profile keys.
#
# Coverage:
#   - Structural (engine): --span parsed, span case computes width/height via
#     jq, /size: built from the computed canvas, --help documents it.

load test_helper

@test "engine_parses_span_flag" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--span' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--span not handled"
}

@test "engine_computes_span_canvas_from_hyprctl_monitors" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Width = sum of selected monitors' widths (auto-detected, not hardcoded).
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '.width] | add'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span canvas width not computed via jq 'add' over detected monitor widths"
  # Height = max of selected monitors' heights (takes the tallest monitor's
  # full native resolution, e.g. a 1440p center monitor between two 1080p
  # monitors keeps its full 1440 height).
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '.height] | max'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span canvas height not computed via jq 'max' over detected monitor heights"
}

@test "engine_builds_size_flag_from_span_canvas" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # _SPAN_W/_SPAN_H (uppercase — renamed so they persist to the background
  # dispatcher subshell for resizewindowpixel; see engine comment).
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '/size:\${_SPAN_W}x\${_SPAN_H}'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span mode missing '/size:\${_SPAN_W}x\${_SPAN_H}'"
}

@test "engine_enables_dynamic_resolution_in_span_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # /size: alone only sets the INITIAL canvas — without +dynamic-resolution,
  # dragging the floating window's edges never renegotiates the RDP
  # resolution (xfreerdp3 /help: "+dynamic-resolution: Enable Send
  # resolution updates when the window is resized"). Sliced to the span)
  # case arm so this doesn't just match single mode's own +dynamic-resolution.
  run bash -c "awk '/^    span\\)/,/^        ;;/' '$engine' | grep -cF '+dynamic-resolution'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span mode does not enable +dynamic-resolution — window resize won't live-update the RDP canvas"
}

@test "engine_reuses_monitor_order_and_monitors_precedence_in_span_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # span must consult the SAME MONITOR_ORDER_OVERRIDE/MONITORS_OVERRIDE chain
  # multi mode uses (no new profile keys for monitor selection).
  run bash -c "grep -n 'span)' '$engine'"
  assert_success
  [ -n "$output" ] || fail "no 'span)' case arm found"
  run bash -c "awk '/^    span\\)/,/^        ;;/' '$engine' | grep -cF 'MONITOR_ORDER_OVERRIDE'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span case does not consult MONITOR_ORDER_OVERRIDE"
}

@test "span_flag_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--span' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--span should appear in parsing AND --help (found $output)"
}

@test "parse_env_safe_accepts_MONITOR_MODE_span" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_MODE=span\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_MODE=span (rc=$_rc)"
  [ "${MONITOR_MODE:-}" = "span" ] || fail "MONITOR_MODE not assigned to 'span'"
}
