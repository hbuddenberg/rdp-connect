# tests/pid-path.bats — bats migration of tests/pid-path-probe.sh (S1–S6)
#
# Spec provenance: openspec/specs/engine-robustness/spec.md "PID lockfile
# path" requirement. 6 @test blocks, one per probe case. Per design.md
# Decision: migration_pattern — mechanical 1:1 translation.
#
# Per design.md Decision: ci_xfreerdp3_strategy — every test is lib-boundary
# (sources lib/rdp-common.bash, exercises compute_pid_path with a mocked `id`).
# NO real id, NO real flock, NO real XDG_RUNTIME_DIR side effects.
#
# Mock strategy: each @test exports a function named `id` that echoes
# $FAKE_UID. The lib's compute_pid_path calls `id -u` via command substitution;
# bash function lookup precedes PATH lookup, so the function shadows the real
# id binary. XDG_RUNTIME_DIR is exported per-test (or unset) to drive the
# branch under test.

load test_helper

# `_mock_id <uid>` — installs a function-shadow mock for `id` and exports
# FAKE_UID so subsequent calls can re-mock with a different uid.
_mock_id() {
  local uid="$1"
  FAKE_UID="$uid"
  # shellcheck disable=SC2329  # invoked indirectly by compute_pid_path in sourced lib
  id() { echo "$FAKE_UID"; }
}

setup() {
  unset FAKE_UID XDG_RUNTIME_DIR
}

# ============================================================================
# S1 (spec): XDG_RUNTIME_DIR set + uid 1000 → /run/user/1000/rdp-partner-1000.pid
# ============================================================================
@test "S1: XDG set + uid 1000 -> /run/user/1000/rdp-partner-1000.pid" {
  _mock_id 1000
  XDG_RUNTIME_DIR=/run/user/1000
  out="$(compute_pid_path partner)"
  [ "$out" = "/run/user/1000/rdp-partner-1000.pid" ]
}

# ============================================================================
# S2 (spec): XDG unset falls back to /tmp WITH uid suffix retained
# (two users on the same host still don't collide)
# ============================================================================
@test "S2: XDG unset + uid 1000 -> /tmp/rdp-partner-1000.pid (uid suffix retained)" {
  _mock_id 1000
  unset XDG_RUNTIME_DIR
  out="$(compute_pid_path partner)"
  [ "$out" = "/tmp/rdp-partner-1000.pid" ]
}

# ============================================================================
# S3 (spec): Two users with XDG set do NOT collide
# (the security property — distinct uids → distinct paths)
# ============================================================================
@test "S3: two-user paths differ (XDG set): uid 1000 vs uid 1001" {
  _mock_id 1000
  XDG_RUNTIME_DIR=/run/user/1000
  p1000="$(compute_pid_path partner)"
  _mock_id 1001
  XDG_RUNTIME_DIR=/run/user/1001
  p1001="$(compute_pid_path partner)"
  [ "$p1000" != "$p1001" ]
  [ "$p1000" = "/run/user/1000/rdp-partner-1000.pid" ]
  [ "$p1001" = "/run/user/1001/rdp-partner-1001.pid" ]
}

# ============================================================================
# S4: Two users with XDG unset still don't collide (uid suffix saves us)
# This is the load-bearing regression case — the legacy /tmp/rdp-<profile>.pid
# path collided here. The uid suffix on the fallback is what eliminates the
# symlink/DoS vector the engine had before T1.4.
# ============================================================================
@test "S4: two-user paths differ (XDG unset): uid 1000 vs uid 1001" {
  unset XDG_RUNTIME_DIR
  _mock_id 1000
  p1000="$(compute_pid_path partner)"
  _mock_id 1001
  p1001="$(compute_pid_path partner)"
  [ "$p1000" != "$p1001" ]
  [ "$p1000" = "/tmp/rdp-partner-1000.pid" ]
  [ "$p1001" = "/tmp/rdp-partner-1001.pid" ]
}

# ============================================================================
# S5: New path is NOT the legacy /tmp/rdp-<profile>.pid
# (explicit negative assertion — catches a regression that reintroduces the
# world-writable collision vector)
# ============================================================================
@test "S5: new path != legacy /tmp/rdp-partner.pid" {
  _mock_id 1000
  unset XDG_RUNTIME_DIR
  p="$(compute_pid_path partner)"
  [ "$p" != "/tmp/rdp-partner.pid" ]
}

# ============================================================================
# S6: Per-profile isolation — different profiles get different paths
# ============================================================================
@test "S6: profile-isolated (uid 1000): profile a vs profile b differ" {
  _mock_id 1000
  XDG_RUNTIME_DIR=/run/user/1000
  pa="$(compute_pid_path a)"
  pb="$(compute_pid_path b)"
  [ "$pa" != "$pb" ]
  [ "$pa" = "/run/user/1000/rdp-a-1000.pid" ]
  [ "$pb" = "/run/user/1000/rdp-b-1000.pid" ]
}
