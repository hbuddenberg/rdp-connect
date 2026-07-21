#!/usr/bin/env bash
# tests/pid-path-probe.sh — fixture-driven probe for compute_pid_path (F5, T1.4)
#
# Confirms the PID lockfile path is uid-private and lands under XDG_RUNTIME_DIR
# (or /tmp fallback WITH the uid suffix). Re-verifies the design's two-user
# non-collision claim by mocking `id -u` for two distinct uids.
#
# Run: ./tests/pid-path-probe.sh
# Exit: 0 if all scenarios pass, 1 otherwise.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/rdp-common.bash"

PASS=0
FAIL=0

ok() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31mFAIL\033[0m  %s\n        %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Mock id to fake uids; compute_pid_path calls `id -u` via command substitution.
id() { echo "$FAKE_UID"; }

# shellcheck source=/dev/null
source "$LIB"

echo "compute_pid_path probe — lib=$LIB"
echo

# Scenario 1 (spec): XDG_RUNTIME_DIR set resolves under /run/user
FAKE_UID=1000
# shellcheck disable=SC2034  # consumed by compute_pid_path (in sourced lib) via ${XDG_RUNTIME_DIR:-/tmp}
XDG_RUNTIME_DIR=/run/user/1000 out=$(compute_pid_path partner)
[[ "$out" == "/run/user/1000/rdp-partner-1000.pid" ]] \
  && ok "S1 XDG set + uid 1000 → $out" \
  || no "S1 XDG set + uid 1000" "got '$out'"

# Scenario 2 (spec): XDG_RUNTIME_DIR unset falls back to /tmp WITH uid suffix
unset XDG_RUNTIME_DIR
out=$(compute_pid_path partner)
[[ "$out" == "/tmp/rdp-partner-1000.pid" ]] \
  && ok "S2 XDG unset + uid 1000 → $out (uid suffix retained)" \
  || no "S2 XDG unset fallback" "got '$out'"

# Scenario 3 (spec): Two users on the same host do not collide (XDG set)
FAKE_UID=1000
# shellcheck disable=SC2034  # consumed by compute_pid_path in the sourced lib
XDG_RUNTIME_DIR=/run/user/1000 p1000=$(compute_pid_path partner)
FAKE_UID=1001; XDG_RUNTIME_DIR=/run/user/1001 p1001=$(compute_pid_path partner)
[[ "$p1000" != "$p1001" ]] \
  && ok "S3 two-user paths differ (XDG set): uid1000=$p1000 vs uid1001=$p1001" \
  || no "S3 two-user paths differ (XDG set)" "COLLISION: both = $p1000"

# Scenario 4: Two users with XDG unset still do not collide (uid suffix saves us)
unset XDG_RUNTIME_DIR
FAKE_UID=1000 p1000=$(compute_pid_path partner)
FAKE_UID=1001 p1001=$(compute_pid_path partner)
[[ "$p1000" != "$p1001" ]] \
  && ok "S4 two-user paths differ (XDG unset): $p1000 vs $p1001" \
  || no "S4 two-user paths differ (XDG unset)" "COLLISION: both = $p1000"

# Scenario 5: New path is NOT the legacy /tmp/rdp-<profile>.pid
[[ "$p1000" != "/tmp/rdp-partner.pid" ]] \
  && ok "S5 new path != legacy /tmp/rdp-partner.pid" \
  || no "S5 legacy migration" "still using legacy path"

# Scenario 6: Per-profile isolation — different profiles get different paths
FAKE_UID=1000
# shellcheck disable=SC2034  # consumed by compute_pid_path in the sourced lib
XDG_RUNTIME_DIR=/run/user/1000
pa=$(compute_pid_path a)
pb=$(compute_pid_path b)
[[ "$pa" != "$pb" ]] \
  && ok "S6 profile-isolated: $pa vs $pb" \
  || no "S6 profile isolation" "got same path for different profiles"

echo
if [[ "$FAIL" == 0 ]]; then
  printf '\033[32mALL %d SCENARIOS PASSED\033[0m\n' "$PASS"
  exit 0
else
  printf '\033[31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi
