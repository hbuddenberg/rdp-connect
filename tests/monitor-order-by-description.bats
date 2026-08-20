#!/usr/bin/env bats
# tests/monitor-order-by-description.bats — covers resolve_monitor_order(),
# which lets MONITOR_ORDER / --monitor-order select monitors by a substring
# of `hyprctl monitors -j`'s `.description` field, in addition to plain
# numeric hyprctl ids.
#
# Why: hyprctl's monitor `id` (and its DP-N port name) is assigned by
# detection/connection order, NOT a stable hardware identity — confirmed live
# on real hardware: the SAME physical layout enumerated as DP-4/DP-9/DP-8 one
# day and DP-3/DP-5/DP-6 the next (a replug/reboot reordered them), while
# `.description` (vendor + model + serial, e.g. "Dell Inc. DELL U2417H
# XVNNT6BTAPBL") stayed identical. MONITOR_ORDER/--monitor-order pinned to
# numeric ids silently breaks across a replug/reboot; description-based
# selection survives it.
#
# resolve_monitor_order is a PURE function (JSON string + selector string in,
# resolved id CSV out or a non-zero return) — no hyprctl call inside it, so
# it's unit-testable with a fixture JSON blob instead of mocking hyprctl.

load test_helper

# Fixture in the CANONICAL monitor-model shape (compositor-aware task 2.4
# migration): {id, desc, x, y, w, h, scale, ws_ref} — the shape
# get_monitors_json() emits for every backend and the only shape the engine
# feeds resolve_monitor_order since PR2. `id` is numeric here (hypr); niri
# name-ids are covered by niri-api.bats::resolve_monitor_order_supports_niri_name_ids.
# Includes a headless/virtual output with an empty desc (like the hypr-rdp
# virtual monitor on this host) to prove an empty-desc monitor never
# spuriously matches a substring token.
_FIXTURE_MONITORS_JSON='[
  {"id":0,"desc":"Dell Inc. DELL U2417H XVNNT6BTAPBL","x":0,"y":0,"w":1920,"h":1080,"scale":1.0,"ws_ref":1},
  {"id":1,"desc":"Dell Inc. DELL U2417H J75VK884B7ZL","x":1920,"y":0,"w":1920,"h":1080,"scale":1.0,"ws_ref":2},
  {"id":2,"desc":"ASUSTek COMPUTER INC XG27ACS T6LMTF111342","x":3840,"y":0,"w":2560,"h":1440,"scale":1.0,"ws_ref":3},
  {"id":3,"desc":"","x":5760,"y":0,"w":1920,"h":1080,"scale":1.0,"ws_ref":null}
]'

@test "resolve_monitor_order_passes_numeric_tokens_through_unchanged" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "0,2"
  assert_success
  [ "$output" = "0,2" ] || fail "expected '0,2', got '$output'"
}

@test "resolve_monitor_order_resolves_a_unique_description_substring" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "ASUS"
  assert_success
  [ "$output" = "2" ] || fail "expected '2' (the ASUS monitor), got '$output'"
}

@test "resolve_monitor_order_matches_description_case_insensitively" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "asustek"
  assert_success
  [ "$output" = "2" ] || fail "expected '2' via case-insensitive match, got '$output'"
}

@test "resolve_monitor_order_resolves_mixed_numeric_and_description_tokens_in_order" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "ASUS,0"
  assert_success
  [ "$output" = "2,0" ] || fail "expected '2,0' (selector order preserved), got '$output'"
}

@test "resolve_monitor_order_disambiguates_identical_models_by_serial_suffix" {
  # Both Dells share "Dell Inc. DELL U2417H" — only the trailing serial is
  # unique. A model-only token must fail (next test); the serial must resolve.
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "J75VK884B7ZL"
  assert_success
  [ "$output" = "1" ] || fail "expected '1' via serial match, got '$output'"
}

@test "resolve_monitor_order_fails_on_ambiguous_description_substring" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "U2417H"
  assert_failure
  [ -z "$output" ] || fail "ambiguous match must not print a partial id list, got '$output'"
}

@test "resolve_monitor_order_fails_on_no_match" {
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "LG"
  assert_failure
  [ -z "$output" ] || fail "no-match must not print a partial id list, got '$output'"
}

@test "resolve_monitor_order_never_matches_an_empty_description" {
  # The headless/virtual monitor (id 3) has description=""; a token must
  # never accidentally match it via an empty-string `contains`.
  run resolve_monitor_order "$_FIXTURE_MONITORS_JSON" "Dell"
  # Should fail (ambiguous: matches BOTH Dells), not resolve to id 3.
  assert_failure
  [ -z "$output" ] || fail "empty description must never match, got '$output'"
}

# ============================================================================
# Structural — engine wires resolve_monitor_order into span/multi/--expand
# ============================================================================

@test "engine_calls_resolve_monitor_order_in_span_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "awk '/^    span\\)/,/^        ;;/' '$engine' | grep -cF 'resolve_monitor_order'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "span mode does not call resolve_monitor_order"
}

@test "engine_calls_resolve_monitor_order_in_multi_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "awk '/^    multi\\|\\*\\)/,/^esac/' '$engine' | grep -cF 'resolve_monitor_order'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "multi mode does not call resolve_monitor_order"
}

@test "engine_calls_resolve_monitor_order_in_expand_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "awk '/--expand/,0' '$engine' | grep -cF 'resolve_monitor_order'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--expand does not call resolve_monitor_order"
}

@test "monitor_order_by_description_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # --help text is hardcoded English (unlike runtime log_event messages, which
  # go through the Spanish-default i18n/{es,en}.env dictionaries).
  run bash -c "grep -ciF 'description substring' '$engine'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "--help does not mention description-based monitor selection"
}
