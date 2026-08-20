#!/usr/bin/env bats
# tests/multi-position.bats — covers positioning the multi-mode (/multimon)
# window onto its physical monitors.
#
# Root cause (see README "What it does" + engine MONITOR MODE comments):
# under Hyprland/XWayland, xfreerdp3's /multimon window is just a regular
# XWayland window to the compositor — Hyprland has no idea it's meant to
# span 3 specific physical outputs, so its default tiling policy places it
# wherever, producing the documented "cramped" window. FreeRDP already
# negotiates the WINDOW SIZE itself from the /monitors:<ids> it's given (no
# forced resize needed — unlike --expand's exact resize call), so the fix is
# only to float it and move it to the selected monitors' origin, via the
# classic `movewindowpixel exact <x> <y>,class:...` dispatcher (also used by
# span/--expand — see tests/hyprland-api.bats for why the CLASSIC dispatch
# form is correct here, not Lua hl.dsp.*).
#
# Coverage:
#   - Structural (engine): multi case computes an origin (min x, min y) via
#     hyprctl monitors -j + jq over the SAME monitor-id list used for
#     /monitors:, and the background dispatcher floats + moves the window
#     when _EFF_MODE=multi.

load test_helper

@test "engine_computes_multi_mode_origin_from_hyprctl_monitors" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Sliced to the multi|*) case arm only, so this doesn't just match span's
  # identical-looking jq expression.
  run bash -c "awk '/multi\\|\\*\\)/,/^        ;;/' '$engine' | grep -cF '.x] | min'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "multi mode does not compute an origin (min x) from hyprctl monitors"
  run bash -c "awk '/multi\\|\\*\\)/,/^        ;;/' '$engine' | grep -cF '.y] | min'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "multi mode does not compute an origin (min y) from hyprctl monitors"
}

@test "engine_dispatches_float_and_move_for_multi_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Sliced from the background dispatcher's multi branch to its own fi/elif
  # boundary, so this is specifically the multi-mode dispatch, not span's.
  # (compositor-aware PR2: float/move go through the lib wrappers; the
  # emitted hyprctl argv is byte-identical — see the golden-argv test in
  # compositor-backends.bats.)
  run bash -c "awk '/_EFF_MODE:-multi\\}\" = \"multi\"/,/^    fi\$/' '$engine' | grep -cF 'dispatch_float'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "multi mode does not float the window"
  run bash -c "awk '/_EFF_MODE:-multi\\}\" = \"multi\"/,/^    fi\$/' '$engine' | grep -cF 'dispatch_move'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "multi mode does not move the window to its monitors' origin"
}

@test "engine_does_not_force_resize_in_multi_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # FreeRDP negotiates /multimon's window size itself from /monitors:<ids> —
  # forcing a resizewindowpixel dispatch here would fight that negotiation.
  run bash -c "awk '/_EFF_MODE:-multi\\}\" = \"multi\"/,/^    fi\$/' '$engine' | grep -cF 'dispatch resizewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  assert_output "0"
}
