# tests/engine-security.bats — boundary tests for the trim allowlist +
# post-parse call-site invariant.
#
# Spec provenance: openspec/changes/strict-tdd-enable/specs/engine-security-delta.md
# Requirement: "Post-parse trim consumers use the extracted helper"
# (2 scenarios):
#   - "Parser consumers call trim_profile_fields(), not inline trim"
#   - "trim_profile_fields() allowlist is the documented 5 trimmed + 2 excluded"
#
# This file is the @test backstop for the T2.1 extraction. T2.1 already did
# the structural lift (engine invokes `trim_profile_fields` as a one-line
# call at engine/rdp-connect:182; the inline `${VAR#"${VAR%%...` idiom is
# gone from the engine). The PR2 verify-report correctly DEFERRED the
# canonical @test coverage to PR3 T3.3 — this file fulfills that deferral.
#
# Per design.md Decision: trim_extraction, 2 @test blocks:
#   engine_calls_trim_profile_fields_not_inline: grep the engine for a call
#     to trim_profile_fields AND assert no inline trim idiom remains at the
#     post-parse call site (structural assertion — pass-by-construction
#     after T2.1, but the @test is the regression backstop).
#   trim_allowlist_is_five_trimmed_two_excluded: call trim_profile_fields
#     with all 7 profile globals set, assert the 5 allowlisted fields are
#     trimmed AND the 2 excluded fields retain literal surrounding whitespace
#     (both halves of the security-critical invariant in one test).
#
# Why this is a security-relevant test: the trim allowlist is the place
# where a future regression could silently widen to include PASS_RDP or
# USER_RDP (credential fields that MAY legally contain surrounding
# whitespace). An accidental widening corrupts credentials at the preflight
# boundary with no diagnostic. The structural + behavioral assertions in
# this file are the regression backstop — a widening fails BOTH tests.

load test_helper

# `trim_profile_fields`, `LIB_FILE`, `REPO_ROOT`, and `TESTS_DIR` are all
# provided by test_helper.bash (which sources lib/rdp-common.bash).

# ============================================================================
# Structural — call-site boundary (engine-security-delta R1)
# ============================================================================

@test "engine_calls_trim_profile_fields_not_inline" {
  # Spec scenario "Parser consumers call trim_profile_fields(), not inline
  # trim": the engine's post-parse trim step MUST invoke the extracted lib
  # fn, and the inline parameter-expansion idiom MUST NOT appear at the
  # post-parse call site. We assert BOTH halves:
  #   1. grep finds a bare `trim_profile_fields` invocation in engine/rdp-connect
  #   2. the inline `${VAR#"${VAR%%[![:space:]]*}"}` idiom does NOT appear
  #      in engine/rdp-connect (it lives ONLY in lib/rdp-common.bash now)
  # AND there is NO surviving `for _field in HOST VPN_CHECK` loop in the
  # engine (the loop body is the lifted idiom's container).
  #
  # Why grep instead of sourcing the engine and intercepting with a bats
  # spy: the engine's startup path requires xfreerdp3/hyprctl/jq/flock/
  # notify-send on PATH and a real profile; sourcing it to the post-parse
  # trim step in a bats @test would require shimming 5 binaries. The
  # structural grep is the lib-boundary assertion the design's
  # ci_xfreerdp3_strategy decision endorses (Option (c) — only test lib
  # functions in CI; engine integration stays manual-verify).
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"

  # 1. trim_profile_fields is invoked from the engine.
  run grep -nE '^[[:space:]]*trim_profile_fields\b' "$engine"
  assert_success
  [[ "$output" == *"trim_profile_fields"* ]]

  # 2. NO inline parameter-expansion trim idiom at the engine post-parse
  #    call site. The idiom is `${VAR#"${VAR%%[![:space:]]*}"}` (strip
  #    leading ws) and `${VAR%"${VAR##*[![:space:]]}"}` (strip trailing).
  #    After T2.1 both forms live ONLY in lib/rdp-common.bash::trim_profile_fields.
  #
  # Note on `run grep` semantics: grep returns rc=1 when NO lines match.
  # `run` captures rc=1 into $status; $output holds the count ("0" with -c).
  # We assert status != 0 (no match) AND output == "0" (count is zero).
  run grep -cE '\$\{[A-Za-z_]+#"?\$\{[A-Za-z_]+%%' "$engine"
  [ "$status" -ne 0 ]
  assert_output "0"

  # 3. NO surviving `for _field in HOST VPN_CHECK` loop container in the
  #    engine (the loop body was the inline trim's home before T2.1).
  run grep -cE 'for[[:space:]]+_field[[:space:]]+in[[:space:]]+HOST[[:space:]]+VPN_CHECK' "$engine"
  [ "$status" -ne 0 ]
  assert_output "0"
}

# ============================================================================
# Behavioral — allowlist invariant (engine-security-delta R2)
# ============================================================================

@test "trim_allowlist_is_five_trimmed_two_excluded" {
  # Spec scenario "trim_profile_fields() allowlist is the documented 5
  # trimmed + 2 excluded": call trim_profile_fields with all 7 profile
  # globals set to values with surrounding whitespace, then assert:
  #   TRIMMED (5): HOST, VPN_CHECK, DOMAIN, PREFERRED_WS, LANG_OVERRIDE
  #   EXCLUDED (2): PASS_RDP, USER_RDP (credentials — whitespace may be
  #                 significant; the engine's preflight never touches them)
  #
  # This is the canonical @test for the security-critical exclusion
  # invariant. The vpn-trim.bats::F8 case covers the same property from
  # the robustness angle (byte-identical snapshots); this @test is the
  # engine-security spec's canonical form (both halves of the invariant
  # asserted in one test, per the spec scenario text).
  #
  # Note on parse_env_safe interaction: we set the globals DIRECTLY (not
  # via parse_env_safe) so the test exercises trim_profile_fields in
  # isolation. parse_env_safe strips trailing ws on unquoted values; going
  # direct lets us put leading+trailing ws on every field and assert the
  # trim behavior unambiguously.
  # shellcheck disable=SC2034  # consumed indirectly by trim_profile_fields
  HOST="  host.example.com  "
  # shellcheck disable=SC2034
  VPN_CHECK="  vpn.example.com  "
  # shellcheck disable=SC2034
  DOMAIN="  corp.local  "
  # shellcheck disable=SC2034
  PREFERRED_WS="  3  "
  # shellcheck disable=SC2034
  LANG_OVERRIDE="  es  "
  # shellcheck disable=SC2034
  USER_RDP="  user@example  "
  # shellcheck disable=SC2034
  PASS_RDP="  p@ss w0rd with trailing ws   "

  trim_profile_fields

  # 5 trimmed: surrounding whitespace is GONE on all of them.
  [ "$HOST"         = "host.example.com" ] || \
    fail "HOST not trimmed: '${HOST}'"
  [ "$VPN_CHECK"    = "vpn.example.com" ] || \
    fail "VPN_CHECK not trimmed: '${VPN_CHECK}'"
  [ "$DOMAIN"       = "corp.local" ] || \
    fail "DOMAIN not trimmed: '${DOMAIN}'"
  [ "$PREFERRED_WS" = "3" ] || \
    fail "PREFERRED_WS not trimmed: '${PREFERRED_WS}'"
  [ "$LANG_OVERRIDE" = "es" ] || \
    fail "LANG_OVERRIDE not trimmed: '${LANG_OVERRIDE}'"

  # 2 excluded: surrounding whitespace is PRESERVED VERBATIM. PASS_RDP and
  # USER_RDP are credential-adjacent — an accidental widening of the
  # allowlist is the highest-risk vector in this change (silent credential
  # corruption at the preflight boundary).
  [ "$USER_RDP" = "  user@example  " ] || \
    fail "USER_RDP widened into allowlist (security regression): '${USER_RDP}'"
  [ "$PASS_RDP" = "  p@ss w0rd with trailing ws   " ] || \
    fail "PASS_RDP widened into allowlist (security regression): '${PASS_RDP}'"
}
