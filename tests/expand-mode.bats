#!/usr/bin/env bats
# tests/expand-mode.bats — covers `rdp-connect --expand <profile>`.
#
# Applies the span layout (float + exact resize + exact move) to an ALREADY
# RUNNING session's window, live, WITHOUT launching a new xfreerdp3 process
# or touching credentials. Meant to be bound to a Hyprland keybind so a
# single-mode session (which always has +dynamic-resolution — see
# tests/monitor-mode.bats) can be "expanded" across N monitors on demand,
# instead of only via `--span` at launch time.
#
# Canvas math and monitor-selection reuse the exact same approach as span
# mode (tests/span-mode.bats): width = sum of selected monitors' widths,
# height = MAX of their heights, via hyprctl monitors -j + jq. Selection here
# is via --monitors/--monitor-order flags only (no profile-config re-read —
# --expand is a live action against an existing window, not a launch).
#
# Uses the CLASSIC hyprctl dispatch forms (movewindowpixel/resizewindowpixel/
# setfloating), confirmed live against a running window on Hyprland 0.56.1 —
# see tests/hyprland-api.bats for how/why (the Lua hl.dsp.* API this codebase
# used originally does not work without the optional Lua config manager,
# which is not active on the target environment).

load test_helper

@test "engine_parses_expand_flag_with_profile_arg" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--expand' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--expand not handled"
}

@test "engine_checks_target_window_exists_before_dispatching" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Must confirm the window is actually running (hyprctl clients -j) before
  # firing any dispatch — same guard pattern the launch-time poller uses.
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF 'hyprctl clients -j'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand does not verify the target window exists first"
}

@test "engine_expand_uses_classic_exact_resize_dispatcher" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF 'dispatch resizewindowpixel'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "classic resizewindowpixel dispatcher missing (--expand live resize)"
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF 'exact'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "resize call missing 'exact' (must be absolute, not a delta move)"
}

@test "engine_expand_reuses_span_canvas_math" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF '.width] | add'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand does not compute canvas width the same way span mode does"
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF '.height] | max'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand does not compute canvas height the same way span mode does"
}

@test "engine_expand_sorts_default_monitor_ids_by_physical_x_position" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # --expand computes its own default monitor-id list inline (it short-
  # circuits before the launch-path's _MON_IDS is built) — must sort by x
  # too, same bug/fix as tests/monitor-config.bats's equivalent test.
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF 'sort_by(.x)'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand's default monitor-id list is not sorted by x"
}

@test "engine_expand_exits_without_launching_xfreerdp" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # The --expand block must `exit 0` (or exit 1 on error) itself, same as
  # --log/--new — it must never fall through to the selector/launch pipeline.
  # Sliced via the block's comment header (a fixed string) rather than the
  # `if [ "${1:-}" ... ]` condition itself, so the awk regex never has to
  # parse a literal `{1:-}` (interval-expression syntax trips some awk
  # implementations).
  run bash -c "awk '/MODO EXPANDIR/,/^fi\$/' '$engine' | grep -cF 'exit'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand block has no exit — would fall through to profile launch"
}

@test "expand_flag_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--expand' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--expand should appear in parsing AND --help (found $output)"
}
