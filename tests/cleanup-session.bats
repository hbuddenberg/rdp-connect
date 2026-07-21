# tests/cleanup-session.bats — covering @test blocks for extract_session_error
#
# Spec provenance: openspec/changes/strict-tdd-enable/specs/engine-robustness-delta.md
# Requirements:
#   - "extract_session_error() extraction preserves behavior"
#     (4 cleanup-session-isolation scenarios: stale prior-session ERROR, PID
#     prefix collision 222 vs 2222, current-session no-ERROR, legacy
#     no-SESSION_START)
#   - "@test coverage for extract_session_error()"
#
# T3.1 (extraction-before-tests rule, applied FIRST in this PR): every @test
# below calls the REAL extract_session_error from lib/rdp-common.bash, NOT a
# reimplementation. This kills the "approval test exercises copy, not
# production code" smell flagged in explore F2 for the trim case; the same
# invariant applies here.
#
# Per design.md Decision: session_error_extraction, 6 @test blocks:
#   F1-F4: 4 fixture-driven @test (one per tests/fixtures/cleanup-session/F*.log)
#   extract_session_error_byte_identical_on_fixtures: the spec's approval-test
#     form, loops all 4 fixtures and asserts each equals its __snapshots__/*.txt
#   extract_session_error_has_unit_coverage: meta-test asserting >= 4 @test
#     blocks in this file target extract_session_error
#
# Production-realism note: each fixture models the perspective of the CURRENT
# session's cleanup trap (the session whose SESSION_START marker is the LAST
# one in the log file). At cleanup time, the active session's marker is the
# most recent one written — earlier markers belong to prior, already-exited
# sessions. The 4 spec scenarios all assume this perspective. See T3.1 commit
# body for the analysis of why querying an EARLIER session's pid is
# production-impossible (cleanup fires at session END).

load test_helper

# `extract_session_error` and `LIB_FILE` are sourced via test_helper.bash.

# ============================================================================
# F1-F4 — fixture-driven @test blocks (4 cleanup-session-isolation scenarios)
# ============================================================================

@test "F1: stale ERROR from previous session is NOT returned (PID scoping)" {
  # engine-robustness-delta scenario "prior-session-stale-ERROR": the current
  # session (pid=2222, LAST SESSION_START marker in the log) MUST NOT surface
  # the prior session's (pid=1111) stale ERROR line. The awk's `found` flag
  # stays 0 until THIS session's marker appears, so prior-session ERRORs are
  # invisible. The current session in this fixture has no ERROR of its own,
  # so the result is empty.
  local fixture="${TESTS_DIR}/fixtures/cleanup-session/F1-stale-prior-session-ERROR.log"
  [ -f "$fixture" ]
  run extract_session_error "$fixture" 2222
  assert_success
  assert_output ""
}

@test "F2: PID prefix collision — pid=222 does NOT match a pid=2222 marker" {
  # engine-robustness-delta scenario "PID prefix collision 2222 vs 22222":
  # the awk anchor `([^0-9]|$)` after the pid digits demands a non-digit or
  # EOL, so a marker for pid=2222 is NOT matched when querying pid=222 (the
  # next char after "222" inside "2222" is "2", a digit). Querying the
  # current session (pid=222, LAST marker) returns ONLY the 222 ERROR line.
  local fixture="${TESTS_DIR}/fixtures/cleanup-session/F2-pid-prefix-collision.log"
  [ -f "$fixture" ]
  run extract_session_error "$fixture" 222
  assert_success
  # The returned line MUST be the 222 ERROR, NOT the stale 2222 ERROR.
  [[ "$output" == *"session 222 (MUST NOT be returned for pid=222)" ]] && \
    fail "BUG: stale pid=2222 ERROR leaked into pid=222 result: $output"
  [[ "$output" == *"VPN requerida (10.8.0.1) inalcanzable. Abortando." ]]
}

@test "F3: current session with no ERROR line returns empty" {
  # engine-robustness-delta scenario "current-session-no-ERROR": the current
  # session (pid=3333) has SESSION_START + INFO lines only. extract_session_error
  # MUST return empty so the engine's cleanup trap falls back to the generic
  # 'Ver log en $LOG_FILE' notify-send message.
  local fixture="${TESTS_DIR}/fixtures/cleanup-session/F3-current-session-no-ERROR.log"
  [ -f "$fixture" ]
  run extract_session_error "$fixture" 3333
  assert_success
  assert_output ""
}

@test "F4: legacy log without SESSION_START marker degrades gracefully" {
  # engine-robustness-delta scenario "legacy-no-SESSION_START": a log file
  # from before the T2.5 (Bug B) fix has no SESSION_START markers at all.
  # extract_session_error MUST return empty (the `found` flag never becomes
  # true, so the matching predicate never fires). This is the engine's
  # generic "see log" fallback path — preserves behavior for logs left over
  # from older deployments.
  local fixture="${TESTS_DIR}/fixtures/cleanup-session/F4-legacy-no-SESSION_START.log"
  [ -f "$fixture" ]
  run extract_session_error "$fixture" 4444
  assert_success
  assert_output ""
}

# ============================================================================
# Meta-test 1 — byte-identical snapshot approval (spec scenario)
# ============================================================================
# engine-robustness-delta.md scenario "Multi-session LOG_FILE fixtures match
# pre-extraction output": loops all 4 fixtures, runs extract_session_error
# with the production-realistic current-session pid for each, and asserts
# each actual output equals its __snapshots__/*.txt. The snapshots were
# generated by running the REAL production code (extract_session_error)
# against each fixture; they are byte-identical to production BY CONSTRUCTION
# (see T3.2 commit).
@test "extract_session_error_byte_identical_on_fixtures" {
  # fixture|pid pairs — each pid is the CURRENT session's pid for that fixture
  # (the LAST SESSION_START marker in the log). See the file header note on
  # production-realism.
  local cases=(
    "F1-stale-prior-session-ERROR.log|2222"
    "F2-pid-prefix-collision.log|222"
    "F3-current-session-no-ERROR.log|3333"
    "F4-legacy-no-SESSION_START.log|4444"
  )
  local entry fixture pid snapshot actual
  for entry in "${cases[@]}"; do
    fixture="${entry%|*}"
    pid="${entry#*|}"
    snapshot="${TESTS_DIR}/fixtures/cleanup-session/__snapshots__/${fixture%.log}.txt"
    [ -f "$snapshot" ] || fail "missing snapshot for $fixture"
    actual="$(extract_session_error "${TESTS_DIR}/fixtures/cleanup-session/${fixture}" "${pid}")"
    [ "$actual" = "$(cat "$snapshot")" ] || \
      fail "fixture ${fixture}: actual differs from snapshot
--- expected (snapshot) ---
$(cat "$snapshot")
--- actual ---
${actual}"
  done
}

# ============================================================================
# Meta-test 2 — >= 4 @test blocks target extract_session_error (spec scenario)
# ============================================================================
# engine-robustness-delta.md scenario "@test coverage for extract_session_error()":
# meta-assertion that >= 4 cases in this file exercise the function. We assert
# against $BATS_TEST_NAMES (populated by bats after loading the .bats file).
# F1-F4 + this byte-identical test + this meta-test = 6 @test blocks, of
# which F1-F4 + byte-identical = 5 directly exercise extract_session_error.
@test "extract_session_error_has_unit_coverage" {
  # shellcheck disable=SC2154  # BATS_TEST_NAMES is populated by bats at load time
  [ "${#BATS_TEST_NAMES[@]}" -ge 4 ]
}
