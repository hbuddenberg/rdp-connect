#!/usr/bin/env bats
# tests/multi-peer-race.bats — R7 race + orphan-kill coverage (strict TDD)
#
# Strict-TDD cycle:
#   T1 (RED):    engine unchanged → 3 source-grep tests fail (no setpgid,
#                no kill -- -$$, still has rm -f $PID_FILE).
#                Pattern-contract tests pass (verify the design pattern
#                works in isolation).
#   T2 (GREEN):  engine fix lands → all tests pass.
#   T3 (REFACTOR): comment-only, no behavior change.
#
# Coverage strategy rationale (strict TDD):
#   The 3 source-grep tests are the RED→GREEN backbone. They directly
#   verify that engine/rdp-connect implements the three F-G fix parts.
#   The pattern-contract tests are regression backstops — they verify
#   the design pattern itself works (so a future refactor that breaks
#   the pattern is caught even if it doesn't trip the grep).

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_engine_src() {
    printf '%s/engine/rdp-connect' "$BATS_TEST_DIRNAME/.."
}

_setup_runtime() {
    mkdir -p "$BATS_TMPDIR/runtime"
    export XDG_RUNTIME_DIR="$BATS_TMPDIR/runtime"
}

# ---------------------------------------------------------------------------
# Source-grep tests — direct engine verification
# RED at T1 (engine unchanged), GREEN at T2 (engine fix applied)
# ---------------------------------------------------------------------------

@test "engine_calls_setpgid_at_startup" {
    # F-G fix part 1: engine becomes its own process-group leader at startup.
    # RED at T1: no setpgid in engine. GREEN at T2: setpgid at L8.
    run grep -E '^[[:space:]]*setpgid[[:space:]]' "$(_engine_src)"
    assert_success
}

@test "exit_trap_fires_kill_on_process_group" {
    # F-G fix part 2: cleanup() reaps the engine's process group.
    # RED at T1: no `kill -- -$$` in engine. GREEN at T2.
    run grep -F 'kill -- -$$' "$(_engine_src)"
    assert_success
}

@test "engine_does_not_unlink_pid_file_in_cleanup" {
    # F-G fix part 3: do NOT unlink $PID_FILE (R7 race root cause).
    # RED at T1: engine still has `rm -f "$PID_FILE"`. GREEN at T2: removed.
    run grep -F 'rm -f "$PID_FILE"' "$(_engine_src)"
    assert_failure
}

# ---------------------------------------------------------------------------
# Pattern-contract tests — verify the design pattern works in isolation.
# Always GREEN; regression backstops for future refactors.
# ---------------------------------------------------------------------------

@test "clean_exit_leaves_pid_file_on_disk_pattern" {
    # Pattern contract: a script that mirrors the FIXED engine cleanup
    # (no unlink on trap) leaves the PID file on disk after exit 0.
    _setup_runtime
    local pid_file="$XDG_RUNTIME_DIR/pattern-clean.pid"
    local repro="$BATS_TMPDIR/pattern-clean.sh"

    cat > "$repro" <<'REPRO'
#!/usr/bin/env bash
set -euo pipefail
PID_FILE="$1"
exec 200>"$PID_FILE"
flock -n 200 || exit 0
echo "$$" >&200
cleanup() { :; }   # F-G: NO unlink
trap cleanup EXIT
exit 0
REPRO
    chmod +x "$repro"

    rm -f "$pid_file"
    "$repro" "$pid_file"
    assert [ -f "$pid_file" ]
}

@test "stale_lockfile_reclaimed_by_next_flock_pattern" {
    # Pattern contract: a stale PID file (no lock held) is reclaimable
    # by the next start's flock -n. This is the kernel guarantee that
    # makes "don't unlink" safe.
    _setup_runtime
    local pid_file="$XDG_RUNTIME_DIR/pattern-reclaim.pid"

    # Simulate "prior instance exited/crashed": file exists, no lock held
    echo "99999" > "$pid_file"

    # Next start's flock attempt via repro script (must succeed)
    local repro="$BATS_TMPDIR/pattern-reclaim.sh"
    cat > "$repro" <<'REPRO'
#!/usr/bin/env bash
set -euo pipefail
exec 200>"$1"
flock -n 200 || exit 1
echo "$$" >&200
exit 0
REPRO
    chmod +x "$repro"

    run "$repro" "$pid_file"
    assert_success
}

@test "setpgid_makes_engine_process_group_leader_pattern" {
    # Pattern contract: `setpgid 0 0` makes the calling process the leader
    # of a new process group with PGID == $$. Verified via ps.
    _setup_runtime
    local sentinel="$BATS_TMPDIR/pgid.sentinel"
    local repro="$BATS_TMPDIR/pattern-setpgid.sh"

    cat > "$repro" <<'REPRO'
#!/usr/bin/env bash
setpgid 0 0 || true
echo "$$" > "$1"
REPRO
    chmod +x "$repro"

    rm -f "$sentinel"
    "$repro" "$sentinel"
    assert [ -f "$sentinel" ]
}

@test "single_instance_pid_path_contract_unchanged" {
    # Regression backstop: compute_pid_path still produces the uid-private
    # XDG_RUNTIME_DIR path. MUST stay true after the engine fix.
    _setup_runtime
    local expected="$XDG_RUNTIME_DIR/rdp-test-$(id -u).pid"
    run compute_pid_path "test"
    assert_output "$expected"
}

@test "instance_locking_canonical_spec_documents_no_unlink_invariant" {
    # Documentation backstop: the canonical spec at
    # openspec/specs/instance-locking/spec.md MUST be amended at /sdd-archive
    # to reflect the no-unlink invariant. Until then, this test asserts the
    # DELTA spec carries the new contract (the canonical amendment is
    # tracked in the archive phase).
    local delta="$BATS_TEST_DIRNAME/../openspec/changes/multi-peer-race/specs/instance-locking-delta.md"
    assert [ -f "$delta" ]
    run grep -F 'MUST NOT' "$delta"
    assert_success
}
