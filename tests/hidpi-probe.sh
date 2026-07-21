#!/usr/bin/env bash
# tests/hidpi-probe.sh — fixture-driven probe for compute_dpi_flags (F1, T2.1)
#
# Sources lib/rdp-common.bash in a child bash, mocks `hyprctl` to emit fixed
# JSON fixtures, and asserts on DPI_FLAGS[], IS_HIDPI, SCALE_PCT, plus the
# WARN log line for unparsable cases. Covers all 5 hidpi-scaling-delta scenarios:
#   S1 scale=2.0  → /scale-desktop:200 /smart-sizing   (spec: HiDPI)
#   S2 scale=1.5  → /scale-desktop:150 /smart-sizing   (spec: fractional)
#   S3 scale=1.0  → empty DPI_FLAGS                     (spec: no flags)
#   S4 scale=null → empty + WARN                        (spec: null fallback)
#   S5 scale=auto → empty + WARN                        (spec: non-numeric)
# Plus two robustness cases: malformed JSON and empty monitors array.
#
# Run: ./tests/hidpi-probe.sh
# Exit: 0 if all cases pass, 1 otherwise.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/rdp-common.bash"

PASS=0
FAIL=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n        %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Stub log_event: compute_dpi_flags calls log_event(level, msg). We capture
# WARN lines so fallback cases can assert on the diagnostic.
WARN_LINES=()
# shellcheck disable=SC2329  # invoked indirectly by compute_dpi_flags in sourced lib
log_event() {
  local level="$1" msg="$2"
  [[ "$level" == "WARN" ]] && WARN_LINES+=("$msg")
}

# Mock hyprctl: emit a fixed JSON fixture for `monitors -j`.
HYPRCTL_JSON=""
# shellcheck disable=SC2329  # invoked indirectly by compute_dpi_flags in sourced lib
hyprctl() { printf '%s' "$HYPRCTL_JSON"; }

# shellcheck source=/dev/null
source "$LIB"

# run_case <label> <json> <expect_hidpi> <expect_pct> <expect_dpi_flags_joined> <expect_warn>
run_case() {
  local label="$1" json="$2" exp_hidpi="$3" exp_pct="$4" exp_flags="$5" exp_warn="$6"
  HYPRCTL_JSON="$json"
  WARN_LINES=()
  compute_dpi_flags
  local actual_flags="${DPI_FLAGS[*]-}"
  local actual_warn_count=${#WARN_LINES[@]}
  local errs=""
  [[ "${IS_HIDPI:-}" == "$exp_hidpi" ]] || errs+="IS_HIDPI:want=$exp_hidpi,got=${IS_HIDPI:-<unset>}; "
  [[ "${SCALE_PCT:-}" == "$exp_pct" ]] || errs+="SCALE_PCT:want=$exp_pct,got=${SCALE_PCT:-<unset>}; "
  [[ "$actual_flags" == "$exp_flags" ]] || errs+="DPI_FLAGS:want=[$exp_flags],got=[$actual_flags]; "
  if [[ "$exp_warn" == "warn" ]]; then
    [[ "$actual_warn_count" -ge 1 ]] || errs+="WARN:expected but not emitted; "
  else
    [[ "$actual_warn_count" == 0 ]] || errs+="WARN:unexpected (${WARN_LINES[*]}); "
  fi
  if [[ -z "$errs" ]]; then
    ok "$label (IS_HIDPI=$IS_HIDPI SCALE_PCT=$SCALE_PCT flags=[${actual_flags:-<empty>}])"
  else
    fail "$label" "$errs"
  fi
}

echo "compute_dpi_flags probe — lib=$LIB"
echo

# S1 (spec): scale 2.0 → HiDPI, 200%, /scale-desktop:200 /smart-sizing
run_case "S1 scale=2.0 -> HiDPI flags" \
  '[{"id":0,"scale":2.0}]' \
  1 200 "/scale-desktop:200 /smart-sizing" "no-warn"

# S2 (spec): scale 1.5 → fractional, rounds to 150
run_case "S2 scale=1.5 -> fractional 150" \
  '[{"id":0,"scale":1.5}]' \
  1 150 "/scale-desktop:150 /smart-sizing" "no-warn"

# S3 (spec): scale 1.0 → no DPI flags (not HiDPI)
run_case "S3 scale=1.0 -> empty flags" \
  '[{"id":0,"scale":1.0}]' \
  0 100 "" "no-warn"

# S4 (spec): scale null → WARN fallback, empty DPI_FLAGS
run_case "S4 scale=null -> WARN + empty" \
  '[{"id":0,"scale":null}]' \
  0 100 "" "warn"

# S5 (spec): non-numeric scale "auto" → WARN fallback
run_case "S5 scale=auto -> WARN + empty" \
  '[{"id":0,"scale":"auto"}]' \
  0 100 "" "warn"

# S6 (robustness): malformed JSON → WARN fallback
run_case "S6 malformed JSON -> WARN + empty" \
  'this-is-not-json' \
  0 100 "" "warn"

# S7 (robustness): empty monitors array (no .[0]) → WARN fallback
run_case "S7 empty monitors [] -> WARN + empty" \
  '[]' \
  0 100 "" "warn"

# S8 (robustness): scale field missing entirely → WARN fallback
run_case "S8 scale missing -> WARN + empty" \
  '[{"id":0,"name":"DP-1"}]' \
  0 100 "" "warn"

echo
if [[ "$FAIL" == 0 ]]; then
  printf '\033[32mALL %d CASES PASSED\033[0m\n' "$PASS"
  exit 0
else
  printf '\033[31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi
