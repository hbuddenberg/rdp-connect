#!/usr/bin/env bats
# tests/monitor-mode.bats — covers the single vs multi monitor mode toggle.
#
# Under Hyprland/XWayland, xfreerdp3 cannot span a single window across
# physical monitors — /multimon renders all remote monitors into ONE client
# window (cramped, non-resizable). The user wants to choose between that
# (multi) and single-monitor fullscreen (one remote monitor, fullscreened).
#
# Two control surfaces, same pattern as the audio toggle:
#   - Profile keys: MONITOR_MODE (multi [default] | single) + MONITOR_ID
#     (which remote monitor in single mode, default 0).
#   - CLI flags: --single-mon / --multi-mon (per-invocation override).
#
# Single mode always applies "+dynamic-resolution" (windowed, resizable RDP
# session — no more fixed /size+f) and the window is set floating +
# auto-fullscreened via Hyprland's hl.dsp.window.float / .fullscreen
# dispatchers (WM-level, not an xfreerdp3 flag — see hyprland-api.bats). This
# means un-fullscreening (or dragging) the floating window always leaves a
# freely resizable session whose RDP resolution follows the window live.
# Multi mode delegates to build_mon_flags (/multimon /monitors:<all>) —
# unchanged default behavior.
#
# Coverage:
#   - Behavioral (parse_env_safe): MONITOR_MODE and MONITOR_ID accepted in
#     profile mode (allowlist). Direct call (not `run`) so the printf -v global
#     assignment propagates to the assertion.
#   - Structural (engine): --single-mon/--multi-mon parsed, MON_FLAGS built
#     conditionally on mode, +dynamic-resolution used in single mode
#     unconditionally, --help documents it.

load test_helper

# ============================================================================
# Behavioral — parse_env_safe allowlist (lib unit tests)
# ============================================================================

@test "parse_env_safe_accepts_MONITOR_MODE_multi" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_MODE=multi\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_MODE=multi (rc=$_rc)"
  [ "${MONITOR_MODE:-}" = "multi" ] || fail "MONITOR_MODE not assigned to 'multi'"
}

@test "parse_env_safe_accepts_MONITOR_MODE_single" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_MODE=single\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_MODE=single (rc=$_rc)"
  [ "${MONITOR_MODE:-}" = "single" ] || fail "MONITOR_MODE not assigned to 'single'"
}

@test "parse_env_safe_accepts_MONITOR_ID" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_ID=2\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_ID=2 (rc=$_rc)"
  [ "${MONITOR_ID:-}" = "2" ] || fail "MONITOR_ID not assigned to '2'"
}

# ============================================================================
# Structural — engine arg parsing + MON_FLAGS construction (source-grep, -F)
# ============================================================================

@test "engine_parses_single_mon_and_multi_mon_flags" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--single-mon' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--single-mon not handled"
  run grep -cF -- '--multi-mon' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--multi-mon not handled"
  run grep -cE 'MONITOR_MODE_OVERRIDE' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "MONITOR_MODE_OVERRIDE missing"
}

@test "engine_builds_MON_FLAGS_conditionally_on_monitor_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Single mode: always +dynamic-resolution (windowed, resizable) — fullscreen
  # on launch comes from the Hyprland hl.dsp.window.fullscreen dispatcher, not
  # an xfreerdp3 /size+f flag, so leaving fullscreen always yields a live-
  # resizable session.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '+dynamic-resolution'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode missing '+dynamic-resolution'"
  # MONITOR_MODE consulted in code.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'MONITOR_MODE'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "MONITOR_MODE not consulted in CODE"
}

@test "monitor_mode_flags_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--single-mon' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--single-mon should appear in parsing AND --help (found $output)"
  run grep -cF -- '--multi-mon' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--multi-mon should appear in parsing AND --help (found $output)"
}
