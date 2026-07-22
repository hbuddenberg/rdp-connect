#!/usr/bin/env bats
# tests/verbose-mode.bats — covers the --verbose / -v diagnostic mode.
#
# The engine is otherwise silent on the terminal: log_event (engine, now lib)
# writes ONLY to the per-profile log file, and errors surface via notify-send
# (desktop notification). Running `rdp-connect <profile>` produced zero
# terminal feedback — the user saw only the opaque `setsid: child N did not
# exit normally: Success` on failure. The verbose mode tees log_event lines
# (engine milestones + xfreerdp3 output) to stderr so the user can SEE whether
# the session is progressing and, on failure, WHY (exit code + extracted cause).
#
# Design (extract-before-mock): the tee decision is pure logic over two globals
# (LOG_FILE, VERBOSE), so log_event was lifted from the engine into
# lib/rdp-common.bash — the same extraction pattern that produced
# trim_profile_fields and extract_session_error. This makes the tee behavior
# unit-testable directly (no engine sourcing, no xfreerdp3/hyprctl shimming).
#
# Coverage split (per the repo's ci_xfreerdp3_strategy):
#   - Behavioral (here): log_event tee — VERBOSE=0 silent on stderr + writes
#     file; VERBOSE=1 tees to stderr + still writes file.
#   - Structural (here): the engine parses -v/--verbose, strips it from $@, and
#     documents it in --help. Real xfreerdp3 execution stays manual-verify.

load test_helper

# log_event, LOG_FILE, VERBOSE, REPO_ROOT, TESTS_DIR come from test_helper.bash
# (which sources lib/rdp-common.bash). Each @test sets LOG_FILE/VERBOSE locally.

# ============================================================================
# Behavioral — log_event tee (lib unit tests)
# ============================================================================

@test "log_event_writes_to_log_file_when_verbose_unset" {
  local tmp
  tmp="$(mktemp)"
  LOG_FILE="$tmp" VERBOSE=0
  log_event "INFO" "hello-world"
  [ -s "$tmp" ] || fail "log file empty — log_event did not append"
  grep -q "hello-world" "$tmp" || fail "log file missing the message"
  rm -f "$tmp"
}

@test "log_event_is_silent_on_stderr_when_verbose_unset" {
  local tmp err
  tmp="$(mktemp)"
  LOG_FILE="$tmp" VERBOSE=0
  err=$(log_event "INFO" "secret-payload" 2>&1 >/dev/null)
  [ -z "$err" ] || fail "stderr non-empty when VERBOSE=0: '$err'"
  rm -f "$tmp"
}

@test "log_event_tees_to_stderr_when_verbose" {
  local tmp err
  tmp="$(mktemp)"
  LOG_FILE="$tmp" VERBOSE=1
  err=$(log_event "INFO" "visible-payload" 2>&1 >/dev/null)
  [[ "$err" == *"visible-payload"* ]] || fail "stderr missing the line when VERBOSE=1: '$err'"
  [ -s "$tmp" ] || fail "log file empty — verbose must STILL write the file"
  grep -q "visible-payload" "$tmp" || fail "log file missing the message in verbose mode"
  rm -f "$tmp"
}

@test "log_event_format_includes_timestamp_and_level" {
  local tmp err
  tmp="$(mktemp)"
  LOG_FILE="$tmp" VERBOSE=1
  err=$(log_event "WARN" "scale-fallback" 2>&1 >/dev/null)
  # Format: [YYYY-MM-DD HH:MM:SS] [LEVEL] msg
  [[ "$err" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\]\ \[WARN\]\ scale-fallback$ ]] \
    || fail "format wrong: '$err'"
  rm -f "$tmp"
}

# ============================================================================
# Structural — engine arg parsing + help (source-grep, per ci_xfreerdp3_strategy)
# ============================================================================

@test "engine_parses_verbose_flag" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # The engine MUST accept both -v and --verbose and set VERBOSE=1.
  run grep -cE '\-\-verbose' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--verbose not handled"
  run grep -cE '\-v\b' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "-v not handled"
  # VERBOSE variable is assigned (default + flag set).
  run grep -cE 'VERBOSE=[01]' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "VERBOSE assignment missing"
}

@test "verbose_flag_is_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # The --help heredoc MUST mention the verbose option so it's discoverable.
  run grep -cE 'verbose|diagnóstic|stderr' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "verbose not mentioned in --help text"
}
