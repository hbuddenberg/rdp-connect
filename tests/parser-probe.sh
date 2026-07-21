#!/usr/bin/env bash
# tests/parser-probe.sh — fixture-driven probe for parse_env_safe (F3, T1.2)
#
# Sources lib/rdp-common.bash in a child bash running under `set -u`, feeds
# well-formed and hostile fixtures, and asserts on exit code + assigned value.
# Re-verifies the design's set-u safety claim (`[[ -v arr[k] ]]` vs `${arr[k]}`).
#
# Run: ./tests/parser-probe.sh
# Exit: 0 if all fixtures pass, 1 otherwise.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/rdp-common.bash"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n        %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# run_probe <fixture_content> <mode> <inspect_var>
# Prints "<rc>\t<value>" — the child bash exits with parse_env_safe's code,
# and we capture the value of the inspected var via indirect expansion.
run_probe() {
  local fixture="$1" mode="$2" var="$3"
  local f="$TMP/fixture.env"
  printf '%b' "$fixture" > "$f"
  # Double-quoting LIB for the inner bash -c is safe (no spaces in our path),
  # but we escape via printf %q to be robust against arbitrary LIB paths.
  local lib_q; lib_q=$(printf '%q' "$LIB")
  local f_q;   f_q=$(printf '%q' "$f")
  bash -c '
    set -u
    source '"$lib_q"'
    parse_env_safe '"$f_q"' "'"$mode"'"
    rc=$?
    val="${!1-<unset>}"
    printf "%d\t%s\n" "$rc" "$val"
  ' _ "$var"
}

# expect_rc <label> <fixture> <mode> <expected_rc>
expect_rc() {
  local label="$1" fixture="$2" mode="$3" expected="$4"
  local out rc
  out=$(run_probe "$fixture" "$mode" "_unused_")
  rc=${out%%$'\t'*}
  if [[ "$rc" == "$expected" ]]; then
    ok "$label (rc=$rc)"
  else
    fail "$label" "expected rc=$expected, got rc=$rc; out=$out"
  fi
}

# expect_val <label> <fixture> <mode> <inspect_var> <expected_value>
expect_val() {
  local label="$1" fixture="$2" mode="$3" var="$4" expected="$5"
  local out rc val
  out=$(run_probe "$fixture" "$mode" "$var")
  rc=${out%%$'\t'*}
  val=${out#*$'\t'}
  if [[ "$rc" == "0" && "$val" == "$expected" ]]; then
    ok "$label (val=$val)"
  else
    fail "$label" "expected rc=0 val=<$expected>, got rc=$rc val=<$val>"
  fi
}

# expect_rc_msg <label> <fixture> <mode> <expected_rc> <expected_stderr_substring>
# Captures the child bash's stderr (where _reject writes) and asserts both the
# return code AND that the diagnostic contains the substring. Used to verify
# T2.4's improved error messages (raw-value preview, "unexpected content" tag).
expect_rc_msg() {
  local label="$1" fixture="$2" mode="$3" expected="$4" msg="$5"
  local out err rc
  : > "$TMP/err"
  out=$(run_probe "$fixture" "$mode" "_unused_" 2>"$TMP/err")
  rc=${out%%$'\t'*}
  err=$(<"$TMP/err")
  if [[ "$rc" == "$expected" && "$err" == *"$msg"* ]]; then
    ok "$label (rc=$rc, stderr matched <$msg>)"
  else
    fail "$label" "expected rc=$expected and stderr containing <$msg>; got rc=$rc err=<$err>"
  fi
}

echo "parse_env_safe probe — lib=$LIB"
echo

# ---- F1: spec — Dangerous key in profile is rejected -----------------------
expect_rc  "F1 reject PATH= (dangerous key)" \
           'PATH=/usr/bin/attacker\n' \
           profile 1

# ---- F2: spec — Unknown non-allowlisted key is rejected --------------------
expect_rc  "F2 reject FOO= (unknown key)" \
           'FOO=bar\n' \
           profile 1

# ---- F3: spec — All allowlisted keys accepted ------------------------------
expect_rc  "F3 accept all 7 allowlisted keys" \
           'HOST=h\nUSER_RDP=u\nPASS_RDP=p\nDOMAIN=d\nVPN_CHECK=\n'\
'PREFERRED_WS=3\nLANG_OVERRIDE=es\n' \
           profile 0

# ---- F4: spec — Inline comment inside double-quoted value is preserved -----
expect_val "F4 preserve inline # inside double quotes" \
           'HOST="server # production"\n' \
           profile HOST 'server # production'

# ---- F5: spec — Trailing comment after unquoted value is stripped ----------
expect_val "F5 strip trailing unquoted # comment" \
           'PREFERRED_WS=3  # target workspace\n' \
           profile PREFERRED_WS '3'

# ---- F6: spec — Single-quoted value is unquoted ----------------------------
expect_val "F6 single-quoted value stripped" \
           "DOMAIN='MicrosoftAccount'\n" \
           profile DOMAIN 'MicrosoftAccount'

# ---- F7: spec — Malformed line (no =) aborts -------------------------------
expect_rc  "F7 reject malformed line (no =)" \
           'garbage line no equals here\n' \
           profile 1

# ---- F8: design — first-= split preserves = inside passwords ---------------
expect_val "F8 first-= split keeps = in password" \
           'PASS_RDP=secret=with=equals\n' \
           profile PASS_RDP 'secret=with=equals'

# ---- F9: design — unterminated quote rejected ------------------------------
expect_rc  "F9 reject unterminated double quote" \
           'HOST="unterminated\n' \
           profile 1

# ---- F10: augmentation — unquoted # without whitespace rejected ------------
expect_rc  "F10 reject unquoted value# space-token (augmentation)" \
           'HOST=server# x\n' \
           profile 1

# ---- F11: design — blank lines and full-line comments skipped --------------
expect_rc  "F11 accept blank lines and full-line comments" \
           $'\n# a comment\n   \n  # indented comment\nHOST=h\n' \
           profile 0

# ---- F12: design — invalid key charset (starts with digit) rejected --------
expect_rc  "F12 reject key starting with digit" \
           '0KEY=v\n' \
           profile 1

# ---- F13: i18n mode — MSG_* accepted, non-MSG_* rejected -------------------
expect_rc  "F13 i18n: accept MSG_PROMPT_SELECT" \
           'MSG_PROMPT_SELECT=Select:\n' \
           i18n 0
expect_rc  "F13 i18n: reject PATH=" \
           'PATH=/x\n' \
           i18n 1

# ---- F14: design — set -u safety: rejected assoc key must NOT raise --------
# This is the load-bearing re-verification of the design's `-v` vs `${arr[k]}`
# note. Under set -u, a non-allowlisted key in profile mode must return 1
# cleanly (no "unbound variable" abort that would mask the rejection).
out=$(run_probe 'KEYNOTREAL=v\n' profile '_unused_')
rc=${out%%$'\t'*}
if [[ "$rc" == "1" ]]; then
  ok "F14 set -u safety: rejected key returns 1 (no unbound-variable abort)"
else
  fail "F14 set -u safety: rejected key returns 1" "expected rc=1, got rc=$rc; out=$out"
fi

# ============================================================================
# T2.4 — quoted-value robustness: CRLF, trailing whitespace, inline comments,
# clearer diagnostics. All cases below MUST pass on the new parser; F15/F22
# are regressions for behavior that was already correct and must stay correct.
# ============================================================================

# ---- F15: regression — empty quoted value (was already correct) -------------
expect_val "F15 empty quoted value" \
           'VPN_CHECK=""\n' \
           profile VPN_CHECK ''

# ---- F16: NEW — CRLF line ending after closing quote ------------------------
# printf '%b' interprets \r — the fixture file gets real CRLF bytes.
# Without the T2.4 `line="${line%$'\r'}"` strip, this was misreported as
# "unterminated quote" because the trailing \r failed the old "raw ends with
# quote" check.
expect_val "F16 CRLF after closing quote (empty value)" \
           'VPN_CHECK=""\r\n' \
           profile VPN_CHECK ''

# ---- F17: NEW — trailing space after closing quote --------------------------
expect_val "F17 trailing space after closing quote" \
           'HOST="value" \n' \
           profile HOST 'value'

# ---- F18: NEW — trailing tab after closing quote ----------------------------
expect_val "F18 trailing tab after closing quote" \
           'HOST="value"\t\n' \
           profile HOST 'value'

# ---- F19: NEW — inline comment after closing quote --------------------------
expect_val "F19 inline comment after closing quote" \
           'HOST="value" # comment\n' \
           profile HOST 'value'

# ---- F20: NEW — non-whitespace garbage after closing quote is REJECTED ------
# Old parser: silently extracted "value" as the value (off-by-one in the
# `${raw:1:${#raw}-2}` slice — accepted `HOST="value"garbage` as `value"garbage`-1
# chars minus outer quotes, leaking the closing quote and trailing junk into
# the value). New parser: reject with "unexpected content after closing quote".
expect_rc_msg "F20 reject garbage after closing quote" \
              'HOST="value"garbage\n' \
              profile 1 "unexpected content after closing quote"

# ---- F21: NEW — unterminated quote includes raw-value preview ---------------
# Old diagnostic was the bare "unterminated quote" with no context, hiding the
# actual offending bytes (invisible whitespace / CRLF). New diagnostic includes
# a 40-char preview so the user can SEE what's wrong.
expect_rc_msg "F21 unterminated quote shows raw preview" \
              'HOST="value\n' \
              profile 1 "unterminated quote (raw:"

# ---- F22: regression — quoted password containing '=' (first-= split) -------
# Verifies the new closing-quote search handles quoted values with embedded
# `=`. The first-= split happened BEFORE this block, so raw='"a=b=c"'; the
# closing-quote search finds the trailing `"` and value preserves `a=b=c`.
expect_val "F22 quoted value with = signs" \
           'PASS_RDP="a=b=c"\n' \
           profile PASS_RDP 'a=b=c'

# ---- F23: regression — quoted value containing '#' (interior preserved) -----
# Re-verifies F4 with the new closing-quote search: the FIRST `"` after the
# leading one is the closer, so `# production` stays inside the value.
expect_val "F23 quoted value with # inside (interior preserved)" \
           'HOST="server # production"\n' \
           profile HOST 'server # production'

echo
if [[ "$FAIL" == 0 ]]; then
  printf '\033[32mALL %d FIXTURES PASSED\033[0m\n' "$PASS"
  exit 0
else
  printf '\033[31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi
