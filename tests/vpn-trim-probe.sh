#!/usr/bin/env bash
# tests/vpn-trim-probe.sh — T2.6 regression probe
#
# Validates that the engine's post-parse whitespace-trim block (engine/rdp-connect
# right after parse_env_safe) handles the 5 VPN_CHECK shapes the bug surfaced:
#
#   ""                   → trimmed empty → SKIP VPN preflight (correct)
#   " "                  → trimmed empty → SKIP (was: ENTER + fail on </dev/tcp/ /3389>)
#   "  10.8.0.1  "       → trimmed "10.8.0.1" → ENTER with clean host
#   "10.8.0.1"           → trimmed "10.8.0.1" → ENTER with clean host
#   "  vpn.example.com " → trimmed "vpn.example.com" → ENTER with clean host
#
# The trim idiom under test (parameter-expansion only, no subshell, set -e safe):
#   v="${v#"${v%%[![:space:]]*}"}"   # strip leading whitespace
#   v="${v%"${v##*[![:space:]]}"}"   # strip trailing whitespace
#
# Engine-equivalent decision logic: after trim, [ -n "$v" ] decides ENTER vs SKIP.
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

expect_skip() {
    local label="$1" input="$2"
    TOTAL=$((TOTAL+1))
    local v="$input"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [ -z "$v" ]; then
        printf '  %s %s (input=[%s] trimmed=[])\n' "$(color 32 PASS)" "$label" "$input"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        printf '  %s %s (input=[%s] trimmed=[%s] — expected SKIP, got ENTER)\n' \
            "$(color 31 FAIL)" "$label" "$input" "$v"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

expect_enter_with() {
    local label="$1" input="$2" expected="$3"
    TOTAL=$((TOTAL+1))
    local v="$input"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [ "$v" = "$expected" ]; then
        printf '  %s %s (input=[%s] trimmed=[%s])\n' \
            "$(color 32 PASS)" "$label" "$input" "$v"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        printf '  %s %s (input=[%s] trimmed=[%s] expected=[%s])\n' \
            "$(color 31 FAIL)" "$label" "$input" "$v" "$expected"
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
