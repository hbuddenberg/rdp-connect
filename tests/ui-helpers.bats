#!/usr/bin/env bats
# tests/ui-helpers.bats — colored help + profile migrator.
#
# Two concerns, both extracted to lib so they're unit-testable (engine can't be
# sourced due to its setsid re-exec):
#   - setup_colors(): populates C_* ANSI globals only when output is a TTY (or
#     RDP_FORCE_COLOR=1) AND NO_COLOR is unset. Respects https://no-color.org.
#   - profile_has_monitor_block() / append_monitor_block(): idempotent migrator
#     that appends a documented monitor-layout block to a profile (used by the
#     `rdp-connect --update-profiles` subcommand).

load test_helper

# ============================================================================
# setup_colors
# ============================================================================

@test "setup_colors_disables_colors_when_NO_COLOR_set" {
    NO_COLOR=1 RDP_FORCE_COLOR=0 setup_colors
    [ -z "${C_R:-}" ] || fail "C_R should be empty when NO_COLOR is set (got '$C_R')"
    [ -z "${C_TITLE:-}" ] || fail "C_TITLE should be empty when NO_COLOR is set"
}

@test "setup_colors_enables_colors_when_forced" {
    # bats stdout is not a TTY, so force color on to test the colorized path.
    NO_COLOR="" RDP_FORCE_COLOR=1 setup_colors
    [ -n "${C_R:-}" ] || fail "C_R should be non-empty when RDP_FORCE_COLOR=1"
    [ -n "${C_TITLE:-}" ] || fail "C_TITLE should be non-empty when forced"
    # C_R must be a real ANSI reset (ESC [ 0 m).
    case "$C_R" in *$'\033'[0m) ;; *) fail "C_R is not an ANSI reset: '$C_R'" ;; esac
}

# ============================================================================
# profile_has_monitor_block / append_monitor_block
# ============================================================================

@test "profile_has_monitor_block_false_without_marker" {
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\n' > "$tmp"
    ! profile_has_monitor_block "$tmp" || fail "should report NO block when marker absent"
    rm -f "$tmp"
}

@test "profile_has_monitor_block_true_with_marker" {
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\n# --- monitor layout\n' > "$tmp"
    profile_has_monitor_block "$tmp" || fail "should report block present when marker exists"
    rm -f "$tmp"
}

@test "append_monitor_block_adds_block_with_new_keys" {
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\nUSER_RDP="u"\n' > "$tmp"
    append_monitor_block "$tmp"
    profile_has_monitor_block "$tmp" || fail "block not appended"
    grep -qF 'MONITORS=' "$tmp"      || fail "block missing MONITORS doc"
    grep -qF 'MONITOR_ORDER=' "$tmp" || fail "block missing MONITOR_ORDER doc"
    grep -qF 'MONITOR_0=' "$tmp"     || fail "block missing MONITOR_<id> doc"
    grep -qF 'DYNAMIC_RESOLUTION=' "$tmp" || fail "block missing DYNAMIC_RESOLUTION doc"
    rm -f "$tmp"
}

@test "append_monitor_block_is_idempotent" {
    local tmp before after
    tmp="$(mktemp)"; printf 'HOST="x"\n' > "$tmp"
    append_monitor_block "$tmp"
    before=$(wc -l < "$tmp")
    append_monitor_block "$tmp"   # second call must NOT duplicate
    after=$(wc -l < "$tmp")
    [ "$before" = "$after" ] || fail "append_monitor_block is not idempotent (before=$before after=$after)"
    rm -f "$tmp"
}

@test "append_monitor_block_preserves_existing_content" {
    local tmp
    tmp="$(mktemp)"; printf 'HOST="HB"\nPASS_RDP="secret"\n' > "$tmp"
    append_monitor_block "$tmp"
    # original key/values must be intact above the appended block
    grep -q '^HOST="HB"$' "$tmp"    || fail "original HOST line corrupted"
    grep -q '^PASS_RDP="secret"$' "$tmp" || fail "original PASS_RDP line corrupted"
    rm -f "$tmp"
}

# ============================================================================
# Structural — engine subcommand + colored help
# ============================================================================

@test "engine_handles_update_profiles_subcommand" {
    local engine="${REPO_ROOT}/engine/rdp-connect"
    [ -f "$engine" ] || fail "engine missing at $engine"
    run grep -cF -- '--update-profiles' "$engine"
    assert_success; [ "$output" != "0" ] || fail "--update-profiles subcommand not handled"
    run grep -cF 'append_monitor_block' "$engine"
    assert_success; [ "$output" != "0" ] || fail "engine doesn't call append_monitor_block"
}

@test "engine_help_uses_color_helpers" {
    local engine="${REPO_ROOT}/engine/rdp-connect"
    [ -f "$engine" ] || fail "engine missing at $engine"
    run grep -cF 'setup_colors' "$engine"
    assert_success; [ "$output" != "0" ] || fail "engine doesn't call setup_colors (no colored help)"
}
