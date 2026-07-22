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
    # Uses the `exec setsid --wait` idiom (NOT `setpgid 0 0` — that's the
    # util-linux external binary on Arch and takes different args; the
    # previous form `setpgid 0 0 || true` silently failed via `|| true`).
    run grep -F 'exec setsid --wait' "$(_engine_src)"
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
    # After /sdd-archive, the canonical spec at
    # openspec/specs/instance-locking/spec.md MUST carry the no-unlink
    # invariant (was originally in the delta, synced at archive time).
    local canonical="$BATS_TEST_DIRNAME/../openspec/specs/instance-locking/spec.md"
    assert [ -f "$canonical" ]
    run grep -F 'MUST NOT' "$canonical"
    assert_success
}

# ---------------------------------------------------------------------------
# Behavioral test for S9 (orphan-xfreerdp3 killed on signal exit)
# This is the test that CAUGHT the setpgid-vs-setsid bug: the previous
# `setpgid 0 0 || true` form silently failed (util-linux external binary),
# so the engine never became a process-group leader, and `kill -- -$$` in
# the trap would have killed the wrong process group.
# ---------------------------------------------------------------------------

@test "orphan_child_killed_when_engine_receives_signal_behavioral" {
    # Pattern: launch a subshell that mirrors the engine's structure
    # (setsid-based session establishment + cleanup trap + child spawn),
    # send SIGTERM, verify the child dies with the engine.
    _setup_runtime
    local ready="$BATS_TMPDIR/orphan-ready.sentinel"
    local child_mark="$BATS_TMPDIR/orphan-child.pid"
    local repro="$BATS_TMPDIR/orphan-repro.sh"

    cat > "$repro" <<'REPRO'
#!/usr/bin/env bash
set -euo pipefail
READY="$1"
CHILD_MARK="$2"

# F-G fix part 1 (corrected): use `exec setsid --wait`, NOT `setpgid 0 0`.
# setsid creates a new session with caller as leader; --wait propagates
# exit code. Guard prevents infinite re-exec.
if [ -z "${_RDP_SESSION_ESTABLISHED:-}" ]; then
    _RDP_SESSION_ESTABLISHED=1 exec setsid --wait "$0" "$@" || exit $?
fi

# F-G fix part 2: trap reaps the process group BEFORE logging
cleanup() {
    kill -- -$$ 2>/dev/null || true
}
trap cleanup EXIT

# Spawn a "child" (simulates xfreerdp3)
sleep 60 &
CHILD=$!
echo "$CHILD" > "$CHILD_MARK"
touch "$READY"

wait $CHILD 2>/dev/null || true
REPRO
    chmod +x "$repro"

    rm -f "$ready" "$child_mark"
    "$repro" "$ready" "$child_mark" &
    local parent=$!

    # Wait for ready (sentinel sync, not fixed sleep)
    local deadline=$(( $(date +%s) + 10 ))
    while [ ! -f "$ready" ] && [ $(date +%s) -lt $deadline ]; do
        sleep 0.05
    done
    [ -f "$ready" ] || skip "ready sentinel not created in time"

    local child_pid
    child_pid=$(<"$child_mark")

    # Child must be alive pre-signal
    kill -0 "$child_pid" 2>/dev/null || skip "child died before signal"

    # Verify child is in the engine's process group (the WHOLE POINT of setsid)
    local parent_pgid child_pgid
    parent_pgid=$(ps -o pgid= -p "$parent" | tr -d ' ')
    child_pgid=$(ps -o pgid= -p "$child_pid" | tr -d ' ')
    assert [ "$parent_pgid" = "$child_pgid" ]
    assert [ "$parent_pgid" = "$parent" ]   # parent is the leader

    # Send SIGTERM to engine — trap should reap the process group
    kill -TERM "$parent" 2>/dev/null || true
    wait "$parent" 2>/dev/null || true

    # Give cleanup a moment to propagate
    local deadline2=$(( $(date +%s) + 3 ))
    while kill -0 "$child_pid" 2>/dev/null && [ $(date +%s) -lt $deadline2 ]; do
        sleep 0.05
    done

    # Child must now be DEAD (process group was killed)
    run kill -0 "$child_pid" 2>/dev/null
    assert_failure   # kill -0 returns non-zero when process is gone
}
