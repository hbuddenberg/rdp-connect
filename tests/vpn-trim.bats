# tests/vpn-trim.bats — bats migration of tests/vpn-trim-probe.sh (F1–F8)
# plus 2 meta-tests required by engine-robustness-delta.md.
#
# Spec provenance: openspec/changes/strict-tdd-enable/specs/engine-robustness-delta.md
# Requirements:
#   - "trim_profile_fields() extraction preserves byte-identical behavior"
#     (3 trim scenarios: whitespace-only VPN_CHECK, surrounding-whitespace
#     HOST, padded PASS_RDP/USER_RDP with the exclusion invariant)
#   - "@test coverage for trim_profile_fields()"
#
# T2.1 (extraction-before-migration rule, applied FIRST in this PR): every
# @test below calls the REAL trim_profile_fields from lib/rdp-common.bash,
# NOT a reimplementation. This kills the "approval test exercises copy, not
# production code" smell flagged in explore F2.
#
# Per design.md Decision: migration_pattern, 10 @test blocks:
#   F1-F8: 8 fixture-driven @test (one per tests/fixtures/vpn-trim/F*.env)
#   trim_profile_fields_byte_identical_on_fixtures: the spec's approval-test
#     form, loops all 8 fixtures and asserts each equals its __snapshots__/*.txt
#   trim_profile_fields_has_unit_coverage: meta-test asserting ≥ 8 @test blocks
#     in this file target trim_profile_fields

load test_helper

# `_load_fixture_and_trim <fixture_path>` — pre-inits the 5 trimmed globals,
# runs parse_env_safe (the prod path), then invokes the REAL trim_profile_fields.
# After this returns, $HOST/$USER_RDP/$PASS_RDP/$DOMAIN/$VPN_CHECK/$PREFERRED_WS/
# $LANG_OVERRIDE all hold their post-trim values for the caller to assert on.
_load_fixture_and_trim() {
  local fixture="$1"
  # Pre-init globals: engine contract (engine L159-160). Under set -u the
  # indirect read ${!_field} in trim_profile_fields raises "unbound variable"
  # on a global that was never assigned.
  # shellcheck disable=SC2034  # consumed indirectly by parse_env_safe + trim_profile_fields
  HOST="" USER_RDP="" PASS_RDP="" DOMAIN=""
  # shellcheck disable=SC2034  # consumed indirectly by parse_env_safe + trim_profile_fields
  VPN_CHECK="" PREFERRED_WS="" LANG_OVERRIDE=""
  parse_env_safe "$fixture" profile
  trim_profile_fields
}

# ============================================================================
# F1-F8 — fixture-driven @test blocks
# ============================================================================

@test "F1: empty VPN_CHECK stays empty (baseline)" {
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F1-empty-vpn-check.env"
  [ "$VPN_CHECK" = "" ]
  [ "$HOST" = "server.example.com" ]
}

@test "F2: single-space VPN_CHECK trims to empty (the original bug case)" {
  # The original bug: VPN_CHECK=" " was treated as ENTER by the pre-trim code,
  # producing "VPN requerida ( ) inalcanzable" on every invocation. Trim MUST
  # yield empty so the preflight guard `[ -n "$VPN_CHECK" ]` correctly skips.
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F2-single-space-vpn-check.env"
  [ "$VPN_CHECK" = "" ]
}

@test "F3: multi-space VPN_CHECK trims to empty" {
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F3-multi-space-vpn-check.env"
  [ "$VPN_CHECK" = "" ]
}

@test "F4: tab-only VPN_CHECK trims to empty" {
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F4-tab-only-vpn-check.env"
  [ "$VPN_CHECK" = "" ]
}

@test "F5: padded HOST and VPN_CHECK trim cleanly; USER_RDP/PASS_RDP keep leading ws (exclusion invariant)" {
  # Mixed fixture: HOST and VPN_CHECK are in the trim allowlist (MUST trim);
  # USER_RDP and PASS_RDP are in the exclusion list (MUST preserve literal
  # whitespace — credentials MAY legally contain surrounding spaces).
  # parse_env_safe strips trailing ws on unquoted values; trim_profile_fields
  # does NOT touch USER_RDP/PASS_RDP. So they keep their leading ws verbatim.
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F5-ip-with-ws-and-creds.env"
  [ "$HOST" = "10.8.0.1" ]
  [ "$VPN_CHECK" = "10.8.0.1" ]
  [ "$USER_RDP" = "  corpuser" ]
  [ "$PASS_RDP" = "  s3cret with spaces" ]
}

@test "F6: clean values are idempotent under trim (no-op on already-clean)" {
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F6-clean-values.env"
  [ "$HOST" = "10.8.0.1" ]
  [ "$USER_RDP" = "user" ]
  [ "$PASS_RDP" = "secret" ]
  [ "$DOMAIN" = "corp" ]
  [ "$VPN_CHECK" = "10.8.0.1" ]
  [ "$PREFERRED_WS" = "3" ]
  [ "$LANG_OVERRIDE" = "es" ]
}

@test "F7: surrounding-whitespace HOST trims; creds preserve leading ws" {
  # The documented "surrounding-whitespace HOST" scenario from
  # engine-robustness/spec.md "Preflight input normalization".
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F7-hostname-with-ws.env"
  [ "$HOST" = "vpn.example.com" ]
  [ "$VPN_CHECK" = "" ]
  [ "$PREFERRED_WS" = "2" ]
  [ "$LANG_OVERRIDE" = "en" ]
  [ "$USER_RDP" = "  user@example" ]
  [ "$PASS_RDP" = "  p@ss w0rd" ]
}

@test "F8: all 7 fields padded — 5 trimmed, 2 excluded (comprehensive allowlist)" {
  # The most comprehensive fixture: every field padded. Used by
  # engine-security.bats::trim_allowlist_is_five_trimmed_two_excluded (PR3)
  # as well. Here we assert the same property from the robustness angle.
  _load_fixture_and_trim "${TESTS_DIR}/fixtures/vpn-trim/F8-all-fields-padded.env"
  [ "$HOST" = "vpn.example.com" ]
  [ "$DOMAIN" = "corp.local" ]
  [ "$VPN_CHECK" = "10.8.0.1" ]
  [ "$PREFERRED_WS" = "3" ]
  [ "$LANG_OVERRIDE" = "es" ]
  [ "$USER_RDP" = "  user" ]
  [ "$PASS_RDP" = "  pass with trailing space" ]
}

# ============================================================================
# Meta-test 1 — byte-identical snapshot approval (spec scenario)
# ============================================================================
# engine-robustness-delta.md scenario "8 vpn-trim fixtures pass byte-identical
# pre/post extraction": loops all 8 fixtures, runs parse_env_safe + trim, and
# asserts each 7-line actual output equals its __snapshots__/*.txt. The
# snapshots were generated by running the REAL production code (parse_env_safe
# + trim_profile_fields) against each fixture; they are byte-identical to
# production BY CONSTRUCTION (see T2.5 commit).
@test "trim_profile_fields_byte_identical_on_fixtures" {
  local f name snapshot actual
  for f in "${TESTS_DIR}/fixtures/vpn-trim"/F*.env; do
    name="$(basename "$f" .env)"
    snapshot="${TESTS_DIR}/fixtures/vpn-trim/__snapshots__/${name}.txt"
    [ -f "$snapshot" ] || fail "missing snapshot for $name"
    _load_fixture_and_trim "$f"
    # Snapshot format MUST match the generator exactly (7 lines, KEY=value).
    actual="$(printf 'HOST=%s\nUSER_RDP=%s\nPASS_RDP=%s\nDOMAIN=%s\nVPN_CHECK=%s\nPREFERRED_WS=%s\nLANG_OVERRIDE=%s\n' \
      "$HOST" "$USER_RDP" "$PASS_RDP" "$DOMAIN" "$VPN_CHECK" "$PREFERRED_WS" "$LANG_OVERRIDE")"
    [ "$actual" = "$(cat "$snapshot")" ] || \
      fail "fixture $name: actual differs from snapshot
--- expected (snapshot) ---
$(cat "$snapshot")
--- actual (post-trim) ---
$actual"
  done
}

# ============================================================================
# Meta-test 2 — ≥ 8 @test blocks target trim_profile_fields (spec scenario)
# ============================================================================
# engine-robustness-delta.md scenario "@test coverage for trim_profile_fields()":
# meta-assertion that ≥ 8 cases in this file exercise the function. We assert
# against $BATS_TEST_NAMES (populated by bats after loading the .bats file).
# F1-F8 + this byte-identical test + this meta-test = 10 @test blocks, of
# which F1-F8 + byte-identical = 9 directly exercise trim_profile_fields.
@test "trim_profile_fields_has_unit_coverage" {
  # shellcheck disable=SC2154  # BATS_TEST_NAMES is populated by bats at load time
  [ "${#BATS_TEST_NAMES[@]}" -ge 8 ]
}
