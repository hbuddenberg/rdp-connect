#!/usr/bin/env bash
# tests/vpn-trim-probe.sh — T2.6 regression probe
#
# Validates that the engine's post-parse whitespace-trim block handles the
# 5 VPN_CHECK shapes the bug surfaced:
#
#   ""                   → trimmed empty → SKIP VPN preflight (correct)
#   " "                  → trimmed empty → SKIP (was: ENTER + fail on </dev/tcp/ /3389>)
#   "  10.8.0.1  "       → trimmed "10.8.0.1" → ENTER with clean host
#   "10.8.0.1"           → trimmed "10.8.0.1" → ENTER with clean host
#   "  vpn.example.com " → trimmed "vpn.example.com" → ENTER with clean host
#
# T2.1 (extraction-before-migration rule): this probe now sources
# lib/rdp-common.bash and calls the REAL trim_profile_fields on each fixture,
# rather than reimplementing the trim inline. This kills the "approval test
# exercises copy, not production code" smell flagged in explore F2 — the
# 8/8 PASS below is a genuine regression check on the extracted fn, not a
# tautology over a duplicate idiom.
#
# Engine-equivalent decision logic: after trim, [ -n "$VPN_CHECK" ] decides
# ENTER vs SKIP.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/rdp-common.bash"
# shellcheck source=/dev/null
source "$LIB"

# Caller contract for trim_profile_fields: ALL 5 trimmed globals MUST be set
# before invocation (the engine pre-inits them to empty at engine L159-160
# right before parse_env_safe). Under `set -u` the indirect read ${!_field}
# raises "unbound variable" on a global that was never assigned — this is the
# same contract the engine satisfies; the probe mirrors it. The 6 vars below
# that the probe never reads directly ARE read indirectly by trim_profile_fields
# (via ${!_field}); shellcheck can't see through indirect access, hence the
# scoped SC2034 disable.
# shellcheck disable=SC2034  # consumed indirectly by trim_profile_fields
HOST="" USER_RDP="" PASS_RDP="" DOMAIN=""
# shellcheck disable=SC2034  # consumed indirectly by trim_profile_fields
VPN_CHECK="" PREFERRED_WS="" LANG_OVERRIDE=""

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

# Each case sets the VPN_CHECK global, invokes trim_profile_fields (the
# production fn), then asserts on the post-trim value of VPN_CHECK.
expect_skip() {
    local label="$1" input="$2"
    TOTAL=$((TOTAL+1))
    VPN_CHECK="$input"
    trim_profile_fields
    if [ -z "$VPN_CHECK" ]; then
        printf '  %s %s (input=[%s] trimmed=[])\n' "$(color 32 PASS)" "$label" "$input"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        printf '  %s %s (input=[%s] trimmed=[%s] — expected SKIP, got ENTER)\n' \
            "$(color 31 FAIL)" "$label" "$input" "$VPN_CHECK"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

expect_enter_with() {
    local label="$1" input="$2" expected="$3"
    TOTAL=$((TOTAL+1))
    VPN_CHECK="$input"
    trim_profile_fields
    if [ "$VPN_CHECK" = "$expected" ]; then
        printf '  %s %s (input=[%s] trimmed=[%s])\n' \
            "$(color 32 PASS)" "$label" "$input" "$VPN_CHECK"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        printf '  %s %s (input=[%s] trimmed=[%s] expected=[%s])\n' \
            "$(color 31 FAIL)" "$label" "$input" "$VPN_CHECK" "$expected"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

echo "T2.6 — VPN_CHECK whitespace-trim regression probe"
echo "================================================"

expect_skip     "F1 empty literal"                ""
expect_skip     "F2 single space"                 " "
expect_skip     "F3 multiple spaces"              "    "
expect_skip     "F4 tab only"                     $'\t'
expect_enter_with "F5 IP with surrounding ws"     "  10.8.0.1  "      "10.8.0.1"
expect_enter_with "F6 clean IP"                   "10.8.0.1"          "10.8.0.1"
expect_enter_with "F7 hostname with surrounding"  "  vpn.example.com " "vpn.example.com"
expect_enter_with "F8 clean hostname"             "vpn.example.com"   "vpn.example.com"

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '%s\n' "$(color 32 "ALL $TOTAL CASES PASSED")"
    exit 0
else
    printf '%s\n' "$(color 31 "$FAIL_COUNT/$TOTAL FAILED")"
    exit 1
fi
