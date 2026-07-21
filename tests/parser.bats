# tests/parser.bats — bats migration of tests/parser-probe.sh (F1–F24)
#
# Spec provenance: openspec/changes/strict-tdd-enable/specs/engine-robustness-delta.md
# (Scenario-to-test parity for robustness scenarios). 24 @test blocks mirroring
# the 24 probe cases one-for-one. Mechanical translation per design.md
# Decision: migration_pattern.
#
# Probe idiom → bats mapping (design L75–83):
#   expect_rc      → parse_env_safe_under_setu + assert_success + rc-column check
#   expect_val     → _parse_and_get_value + assert_success + rc + value-column check
#   expect_rc_msg  → parse_env_safe_under_setu + assert_success + rc + $stderr substring
#
# IMPORTANT: the child bash inside parse_env_safe_under_setu ALWAYS exits 0
# (it catches parse_env_safe's rc internally and prints "<rc>\t<ok>"). The <ok>
# sentinel proves set -u survived past the parser. Failure of the parse itself
# is signaled by the rc column (${lines[0]%$'\t'*}) being "1", NOT by $status.
# This is why every case uses assert_success (child OK) plus an explicit rc
# check — the same pattern F14 uses for the set-u safety load-bearing test.
#
# F14 preserves the child-bash `set -u` idiom via test_helper.bash::
# parse_env_safe_under_setu (bats @test blocks run in-process; the child bash
# contains the unbound-variable failure mode to a single `run` capture).

load test_helper

# ============================================================================
# Spec scenarios F1–F14 (parse_env_safe base contract)
# ============================================================================

@test "F1: dangerous key PATH= is rejected (rc=1)" {
  parse_env_safe_under_setu 'PATH=/usr/bin/attacker\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F2: unknown non-allowlisted key FOO= is rejected (rc=1)" {
  parse_env_safe_under_setu 'FOO=bar\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F3: all 7 allowlisted keys accepted (rc=0)" {
  parse_env_safe_under_setu 'HOST=h\nUSER_RDP=u\nPASS_RDP=p\nDOMAIN=d\nVPN_CHECK=\n'"\
PREFERRED_WS=3\nLANG_OVERRIDE=es\n" profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
}

@test "F4: inline # inside double quotes is preserved (value='server # production')" {
  _parse_and_get_value 'HOST="server # production"\n' profile HOST
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "server # production" ]
}

@test "F5: trailing unquoted # comment is stripped (PREFERRED_WS='3')" {
  _parse_and_get_value 'PREFERRED_WS=3  # target workspace\n' profile PREFERRED_WS
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "3" ]
}

@test "F6: single-quoted value is unquoted (DOMAIN='MicrosoftAccount')" {
  _parse_and_get_value "DOMAIN='MicrosoftAccount'\n" profile DOMAIN
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "MicrosoftAccount" ]
}

@test "F7: malformed line (no =) is rejected (rc=1)" {
  parse_env_safe_under_setu 'garbage line no equals here\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F8: first-= split keeps = inside password (PASS_RDP='secret=with=equals')" {
  _parse_and_get_value 'PASS_RDP=secret=with=equals\n' profile PASS_RDP
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "secret=with=equals" ]
}

@test "F9: unterminated double quote is rejected (rc=1)" {
  parse_env_safe_under_setu 'HOST="unterminated\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F10: unquoted value# without whitespace is rejected (augmentation)" {
  parse_env_safe_under_setu 'HOST=server# x\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F11: blank lines and full-line comments are accepted (rc=0)" {
  parse_env_safe_under_setu $'\n# a comment\n   \n  # indented comment\nHOST=h\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
}

@test "F12: key starting with digit is rejected (rc=1)" {
  parse_env_safe_under_setu '0KEY=v\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F13 i18n: MSG_PROMPT_SELECT accepted in i18n mode (rc=0)" {
  parse_env_safe_under_setu 'MSG_PROMPT_SELECT=Select:\n' i18n
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
}

@test "F13 i18n: PATH= rejected in i18n mode (rc=1)" {
  parse_env_safe_under_setu 'PATH=/x\n' i18n
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "F14: set -u safety — rejected assoc key returns 1 cleanly (no unbound-variable abort)" {
  # Load-bearing re-verification of the design's `[[ -v arr[k] ]]` vs
  # `${arr[k]}` note. The child bash runs under set -u; if parse_env_safe had
  # aborted on the unbound assoc key, the child would exit non-zero with
  # "unbound variable" on $stderr and the "<rc>\t<ok>" line would never print.
  # We assert: (a) child exited 0 (set -u survived), (b) parse_env_safe rc=1
  # (clean rejection, not an abort), (c) <ok> sentinel present, (d) $stderr
  # does NOT mention "unbound variable".
  parse_env_safe_under_setu 'KEYNOTREAL=v\n' profile
  assert_success                     # child bash itself exited 0
  [ "${lines[0]%$'\t'*}" = "1" ]     # parse_env_safe returned 1 (rejection)
  [ "${lines[0]#*$'\t'}" = "<ok>" ]  # child survived past parse_env_safe
  [[ "${stderr}" != *"unbound variable"* ]]
}

# ============================================================================
# T2.4 quoted-value robustness scenarios (F15–F23)
# ============================================================================

@test "F15: empty quoted value parses to empty string (regression)" {
  _parse_and_get_value 'VPN_CHECK=""\n' profile VPN_CHECK
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "" ]
}

@test "F16: CRLF after closing quote (empty value) — strip \r before quote check" {
  # printf '%b' interprets \r inside the helper, so the fixture file gets real
  # CRLF bytes. Without the lib's `line="${line%$'\r'}"` strip (lib L87), this
  # was misreported as "unterminated quote".
  _parse_and_get_value 'VPN_CHECK=""\r\n' profile VPN_CHECK
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "" ]
}

@test "F17: trailing space after closing quote is tolerated (HOST='value')" {
  _parse_and_get_value 'HOST="value" \n' profile HOST
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "value" ]
}

@test "F18: trailing tab after closing quote is tolerated (HOST='value')" {
  _parse_and_get_value 'HOST="value"\t\n' profile HOST
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "value" ]
}

@test "F19: inline comment after closing quote is stripped (HOST='value')" {
  _parse_and_get_value 'HOST="value" # comment\n' profile HOST
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "value" ]
}

@test "F20: garbage after closing quote is REJECTED with diagnostic" {
  # Old parser silently extracted "value" (off-by-one slice); new parser rejects
  # with "unexpected content after closing quote". Assert: (a) child OK,
  # (b) parse_env_safe rc=1, (c) $stderr contains the diagnostic. The helper
  # uses `run --separate-stderr`, so the _reject diagnostic lands in $stderr
  # (string) — not $output (which holds "<rc>\t<ok>" on stdout).
  parse_env_safe_under_setu 'HOST="value"garbage\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
  [[ "${stderr}" == *"unexpected content after closing quote"* ]]
}

@test "F21: unterminated quote diagnostic includes raw-value preview" {
  parse_env_safe_under_setu 'HOST="value\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
  [[ "${stderr}" == *"unterminated quote (raw:"* ]]
}

@test "F22: quoted password with = signs preserves all = (first-= split)" {
  _parse_and_get_value 'PASS_RDP="a=b=c"\n' profile PASS_RDP
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "a=b=c" ]
}

@test "F23: quoted value with # inside preserves interior # " {
  # Re-verifies F4 with the T2.4 closing-quote search: the FIRST `"` after the
  # leading one is the closer, so `# production` stays inside the value.
  _parse_and_get_value 'HOST="server # production"\n' profile HOST
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
  [ "${lines[0]#*$'\t'}" = "server # production" ]
}

# ============================================================================
# Helper — runs parse_env_safe in a child bash and prints "<rc>\t<value-of-var>"
# ============================================================================
# Mirrors parser-probe.sh::run_probe (lines 27-43). The probe captured the
# value via indirect expansion in the child bash; we do the same here so the
# @test can assert on the parsed value, not just rc. Used by F4/F5/F6/F8 and
# all of F15–F23 (value-asserting cases). The rc-only cases (F1, F2, F3, F7,
# F9, F10, F11, F12, F13×2, F14, F20, F21) call parse_env_safe_under_setu
# directly and ignore the value column.
_parse_and_get_value() {
  local fixture="$1" mode="$2" var="$3"
  local fixture_file
  fixture_file="$(mktemp)"
  printf '%b' "$fixture" > "${fixture_file}"
  # shellcheck disable=SC2154  # `run` is a bats builtin
  run --separate-stderr bash -c '
    set -u
    # shellcheck source=/dev/null  # path resolved at runtime via "$1"
    source "$1"
    parse_env_safe "$2" "$3"
    rc=$?
    val="${!4-<unset>}"
    printf "%d\t%s\n" "$rc" "$val"
  ' _ "${LIB_FILE}" "${fixture_file}" "${mode}" "${var}"
  rm -f "${fixture_file}"
}
