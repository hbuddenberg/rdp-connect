#!/usr/bin/env bats
# tests/profile-key-writer.bats — covers set_profile_key(), the write-back
# half of the pre-connect checkbox menu (tests/precheck-menu.bats): when the
# user confirms a monitor/audio selection, the engine persists it into the
# profile .env so the NEXT launch pre-checks the same state ("recordar el
# ultimo estado" — the user's explicit ask).
#
# Deliberately NOT built on parse_env_safe/sourcing: set_profile_key is a
# plain line-rewrite over the raw file, matched the same way parse_env_safe
# distinguishes a real assignment from a full-line comment (leading-whitespace
# trim, then an exact "KEY=" prefix) — so it can never rewrite a commented-out
# example line like `# MONITOR_ORDER=1,3,2` in the tunables block.

load test_helper

@test "set_profile_key_replaces_an_existing_unquoted_value" {
  local tmp
  tmp="$(mktemp)"
  printf 'HOST="x"\nMONITOR_MODE=multi\nUSER_RDP="u"\n' > "$tmp"
  set_profile_key "$tmp" MONITOR_MODE span
  run grep -c '^MONITOR_MODE=' "$tmp"
  [ "$output" -eq 1 ] || fail "expected exactly one MONITOR_MODE= line, got $output"
  run grep -F 'MONITOR_MODE="span"' "$tmp"
  assert_success
  rm -f "$tmp"
}

@test "set_profile_key_replaces_an_existing_quoted_value" {
  local tmp
  tmp="$(mktemp)"
  printf 'MONITOR_ORDER="0,1"\n' > "$tmp"
  set_profile_key "$tmp" MONITOR_ORDER "ASUS,Dell J75VK884B7ZL"
  run grep -F 'MONITOR_ORDER="ASUS,Dell J75VK884B7ZL"' "$tmp"
  assert_success
  run grep -c '^MONITOR_ORDER=' "$tmp"
  [ "$output" -eq 1 ] || fail "expected exactly one MONITOR_ORDER= line, got $output"
  rm -f "$tmp"
}

@test "set_profile_key_appends_when_key_is_absent" {
  local tmp
  tmp="$(mktemp)"
  printf 'HOST="x"\n' > "$tmp"
  set_profile_key "$tmp" AUDIO_REDIRECT 0
  run grep -F 'AUDIO_REDIRECT="0"' "$tmp"
  assert_success
  run grep -cF 'HOST="x"' "$tmp"
  [ "$output" -eq 1 ] || fail "existing HOST line was disturbed"
  rm -f "$tmp"
}

@test "set_profile_key_never_touches_a_commented_out_example_line" {
  local tmp
  tmp="$(mktemp)"
  printf '# MONITOR_ORDER=1,3,2\nMONITOR_MODE=single\n' > "$tmp"
  set_profile_key "$tmp" MONITOR_ORDER "ASUS"
  run grep -cF '# MONITOR_ORDER=1,3,2' "$tmp"
  [ "$output" -eq 1 ] || fail "the commented example line was rewritten (should be untouched)"
  run grep -F 'MONITOR_ORDER="ASUS"' "$tmp"
  assert_success
  rm -f "$tmp"
}

@test "set_profile_key_preserves_every_other_line_verbatim" {
  local tmp
  tmp="$(mktemp)"
  printf 'HOST="x" # note\nDOMAIN=""\nMONITOR_ID=2\n' > "$tmp"
  set_profile_key "$tmp" MONITOR_ID 0
  run grep -cF 'HOST="x" # note' "$tmp"
  [ "$output" -eq 1 ] || fail "unrelated HOST line was disturbed"
  run grep -cF 'DOMAIN=""' "$tmp"
  [ "$output" -eq 1 ] || fail "unrelated DOMAIN line was disturbed"
  rm -f "$tmp"
}

@test "set_profile_key_fails_on_missing_file" {
  run set_profile_key "/nonexistent/$(date +%s%N)" MONITOR_MODE span
  assert_failure
}

# ============================================================================
# Structural — engine actually calls set_profile_key to persist the checkbox
# selection (see tests/precheck-menu.bats for the full menu coverage)
# ============================================================================

@test "engine_persists_checkbox_selection_via_set_profile_key" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF 'set_profile_key' "$engine"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "engine never calls set_profile_key — checkbox choice would not be remembered"
}
