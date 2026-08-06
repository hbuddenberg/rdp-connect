#!/usr/bin/env bats
# tests/monitor-config.bats — covers the multi-monitor layout config.
#
# Profile keys (all optional; flag CLI > config > computed default):
#   MONITORS=<n>              multi: use this many monitors (first N detected)
#   MONITOR_ORDER=<id1>,<id2>,...  multi: physical IDs in the order to use
#   MONITOR_<pos>=<W>x<H>     single: resolution for logical position <pos>
#   DYNAMIC_RESOLUTION=1      single: +dynamic-resolution (windowed, resize live)
#                             instead of fixed /size +f (fullscreen)
#
# FreeRDP constraint (documented): per-monitor resolution (MONITOR_<pos>) is only
# honored in SINGLE mode (/size). In multi (/multimon) FreeRDP uses each monitor's
# native resolution — MONITOR_<pos> is ignored there. DYNAMIC_RESOLUTION is
# single-mode only (windowed, resizable).
#
# Parser change: MONITOR_<pos> is a DYNAMIC key (any digits suffix), accepted via
# a ^MONITOR_[0-9]+$ pattern in profile mode (like MSG_* in i18n mode), NOT a
# fixed allowlist entry.

load test_helper

# ============================================================================
# Behavioral — parse_env_safe allowlist (lib unit tests)
# ============================================================================

@test "parse_env_safe_accepts_MONITORS" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'MONITORS=2\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "MONITORS rejected (rc=$_rc)"
  [ "${MONITORS:-}" = "2" ] || fail "MONITORS not assigned"
}

@test "parse_env_safe_accepts_MONITOR_ORDER" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'MONITOR_ORDER=1,3,2\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "MONITOR_ORDER rejected (rc=$_rc)"
  [ "${MONITOR_ORDER:-}" = "1,3,2" ] || fail "MONITOR_ORDER not assigned"
}

@test "parse_env_safe_accepts_DYNAMIC_RESOLUTION" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'DYNAMIC_RESOLUTION=1\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "DYNAMIC_RESOLUTION rejected (rc=$_rc)"
  [ "${DYNAMIC_RESOLUTION:-}" = "1" ] || fail "DYNAMIC_RESOLUTION not assigned"
}

@test "parse_env_safe_accepts_dynamic_MONITOR_digit_keys" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'MONITOR_1=1920x1080\nMONITOR_2=1920x1080\nMONITOR_3=2560x1440\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "MONITOR_<digit> rejected (rc=$_rc)"
  [ "${MONITOR_1:-}" = "1920x1080" ] || fail "MONITOR_1 not assigned"
  [ "${MONITOR_2:-}" = "1920x1080" ] || fail "MONITOR_2 not assigned"
  [ "${MONITOR_3:-}" = "2560x1440" ] || fail "MONITOR_3 not assigned"
}

@test "parse_env_safe_accepts_MONITOR_with_multidigit_suffix" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'MONITOR_12=1920x1080\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "MONITOR_12 rejected (rc=$_rc)"
  [ "${MONITOR_12:-}" = "1920x1080" ] || fail "MONITOR_12 not assigned"
}

@test "parse_env_safe_rejects_MONITOR_with_nondigit_suffix" {
  # MONITOR_foo is NOT a valid dynamic monitor key (suffix must be digits) and
  # is not in the allowlist — must be rejected so typos don't silently create
  # junk globals.
  local tmp _rc
  tmp="$(mktemp)"; printf 'MONITOR_foo=1920x1080\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -ne 0 ] || fail "MONITOR_foo was ACCEPTED (should be rejected — only MONITOR_<digits> allowed)"
}

# ============================================================================
# Structural — engine arg parsing + monitor-config construction (source-grep)
# ============================================================================

@test "engine_parses_monitor_config_flags" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--monitors' "$engine"
  assert_success; [ "$output" != "0" ] || fail "--monitors not handled"
  run grep -cF -- '--monitor-order' "$engine"
  assert_success; [ "$output" != "0" ] || fail "--monitor-order not handled"
  run grep -cF -- '--dynamic-resolution' "$engine"
  assert_success; [ "$output" != "0" ] || fail "--dynamic-resolution not handled"
}

@test "engine_uses_dynamic_resolution_flag_in_single_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '+dynamic-resolution'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single-mode missing '+dynamic-resolution' (DYNAMIC_RESOLUTION path)"
}

@test "engine_consults_MONITOR_ORDER_and_MONITORS_in_multi_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'MONITOR_ORDER'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "MONITOR_ORDER not consulted in CODE"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'MONITORS'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "MONITORS not consulted in CODE"
}

@test "engine_sorts_default_monitor_ids_by_physical_x_position" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # hyprctl's numeric monitor `id` is assigned by detection/connection order,
  # NOT physical left-to-right position (confirmed on real hardware: DP-3
  # id=0 x=1920, DP-6 id=2 x=3840, DP-5 id=1 x=6400 — id order 0,1,2 is NOT
  # spatial order 0,2,1). The DEFAULT "all detected" monitor-id list (used by
  # multi/span/expand when no explicit MONITOR_ORDER/--monitor-order is
  # given) must sort by x before joining ids, or /monitors:<ids> and the
  # multi-mode window's remote-monitor content land in the wrong physical
  # slots even though the WINDOW itself is positioned correctly.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'sort_by(.x)'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "default monitor-id list is not sorted by x (sort_by(.x) missing)"
}
