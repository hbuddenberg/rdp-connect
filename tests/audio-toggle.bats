#!/usr/bin/env bats
# tests/audio-toggle.bats — covers the audio redirect toggle.
#
# The engine always emitted /sound + /microphone, forcing remote audio to the
# client. The user wants to choose: redirect to client (current) OR leave audio
# on the remote machine. Two control surfaces:
#   - Profile key AUDIO_REDIRECT (1=redirect [default], 0=keep on remote)
#   - CLI flag --no-audio (per-invocation override, forces off)
#
# The engine builds an SOUND_FLAGS array conditionally and expands it with the
# "${SOUND_FLAGS[@]}" form (zero args when empty — the CORRECT empty-array
# form; the "-default" gotcha that broke DPI_FLAGS must NOT reappear here).
#
# Coverage:
#   - Behavioral (parse_env_safe): AUDIO_REDIRECT accepted in profile mode for
#     both 1 and 0 values (allowlist gate). Run in the SAME shell (not `run`)
#     so the printf -v global assignment propagates to the assertion.
#   - Structural (engine): --no-audio parsed, SOUND_FLAGS built conditionally,
#     correct array-expansion form, --help documents it. Greps use -F
#     (fixed-string) to avoid ERE escaping issues.

load test_helper

# ============================================================================
# Behavioral — parse_env_safe allowlist (lib unit tests)
# ============================================================================
# NOTE: parse_env_safe is called directly (NOT via `run`) so its `printf -v`
# global assignment of AUDIO_REDIRECT is visible to the [ ... ] assertion.
# `assert_success` is NOT used here — it requires $output (only set by `run`).

@test "parse_env_safe_accepts_AUDIO_REDIRECT_one" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'AUDIO_REDIRECT=1\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected AUDIO_REDIRECT=1 (rc=$_rc)"
  [ "${AUDIO_REDIRECT:-}" = "1" ] || fail "AUDIO_REDIRECT not assigned to '1'"
}

@test "parse_env_safe_accepts_AUDIO_REDIRECT_zero" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'AUDIO_REDIRECT=0\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected AUDIO_REDIRECT=0 (rc=$_rc)"
  [ "${AUDIO_REDIRECT:-}" = "0" ] || fail "AUDIO_REDIRECT not assigned to '0'"
}

# ============================================================================
# Structural — engine arg parsing + SOUND_FLAGS construction (source-grep, -F)
# ============================================================================

@test "engine_parses_no_audio_flag" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--no-audio' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--no-audio not handled"
  run grep -cE 'NO_AUDIO=[01]' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "NO_AUDIO assignment missing"
}

@test "engine_builds_SOUND_FLAGS_conditionally_on_AUDIO_REDIRECT" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Both AUDIO_REDIRECT (profile) and SOUND_FLAGS must appear in CODE lines.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'AUDIO_REDIRECT'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "AUDIO_REDIRECT not consulted in CODE"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'SOUND_FLAGS'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "SOUND_FLAGS array not built"
}

@test "engine_sound_flags_use_correct_empty_array_expansion" {
  # The "${SOUND_FLAGS[@]-}" form (with `-`) would re-introduce the phantom
  # empty-arg bug that broke DPI_FLAGS. MUST be "${SOUND_FLAGS[@]}" (no `-`).
  # Fixed-string greps (-F) to avoid ERE escaping of ${}[].
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'SOUND_FLAGS[@]-'"
  [ "$status" -ne 0 ] || fail "found 'SOUND_FLAGS[@]-' — phantom empty-arg bug returned"
  assert_output "0"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '\"\${SOUND_FLAGS[@]}\"'"
  [ "$status" -eq 0 ] || fail "correct expansion form missing"
  [ "$output" != "0" ] || fail "correct '\"\${SOUND_FLAGS[@]}\"' expansion missing"
}

@test "no_audio_flag_is_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # --no-audio appears in arg parsing AND --help text => count >= 2.
  run grep -cF -- '--no-audio' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--no-audio should appear in parsing AND --help (found $output)"
}
