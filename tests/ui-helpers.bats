#!/usr/bin/env bats
# tests/ui-helpers.bats — colored help + profile migrator (FULL tunables set).
#
# The migrator must bring an OLD profile up to parity with a complete one: it
# appends a documented block listing EVERY tunable key (audio + monitor mode +
# monitor layout), not just the monitor-layout subset. Keys are commented so the
# migration never changes behavior — the user uncomments what they want.
#
# setup_colors(): C_* ANSI globals only when stdout is a TTY (or RDP_FORCE_COLOR=1)
# AND NO_COLOR is unset (https://no-color.org).

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
    NO_COLOR="" RDP_FORCE_COLOR=1 setup_colors
    [ -n "${C_R:-}" ] || fail "C_R should be non-empty when RDP_FORCE_COLOR=1"
    [ -n "${C_TITLE:-}" ] || fail "C_TITLE should be non-empty when forced"
    case "$C_R" in *$'\033'[0m) ;; *) fail "C_R is not an ANSI reset: '$C_R'" ;; esac
}

# ============================================================================
# profile_has_tunables_block / append_tunables_block
# ============================================================================

@test "profile_has_tunables_block_false_without_marker" {
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\n' > "$tmp"
    ! profile_has_tunables_block "$tmp" || fail "should report NO block when marker absent"
    rm -f "$tmp"
}

@test "profile_has_tunables_block_true_with_marker" {
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\n# --- rdp-connect tunables\n' > "$tmp"
    profile_has_tunables_block "$tmp" || fail "should report block present when marker exists"
    rm -f "$tmp"
}

@test "append_tunables_block_adds_every_tunable_key" {
    # The migrator must document the FULL set, not just monitor-layout:
    # audio + monitor-mode + monitor-layout. This is the regression the user
    # flagged (the old block missed AUDIO_REDIRECT / MONITOR_MODE / MONITOR_ID).
    local tmp; tmp="$(mktemp)"; printf 'HOST="x"\nUSER_RDP="u"\n' > "$tmp"
    append_tunables_block "$tmp"
    profile_has_tunables_block "$tmp" || fail "block not appended"
    grep -qF 'AUDIO_REDIRECT='  "$tmp" || fail "block missing AUDIO_REDIRECT"
    grep -qF 'MONITOR_MODE='     "$tmp" || fail "block missing MONITOR_MODE"
    grep -qF 'MONITOR_ID='       "$tmp" || fail "block missing MONITOR_ID"
    grep -qF 'MONITORS='         "$tmp" || fail "block missing MONITORS"
    grep -qF 'MONITOR_ORDER='    "$tmp" || fail "block missing MONITOR_ORDER"
    grep -qF 'MONITOR_0='        "$tmp" || fail "block missing MONITOR_<id>"
    grep -qF 'DYNAMIC_RESOLUTION=' "$tmp" || fail "block missing DYNAMIC_RESOLUTION"
    rm -f "$tmp"
}

@test "append_tunables_block_is_idempotent" {
    local tmp before after
    tmp="$(mktemp)"; printf 'HOST="x"\n' > "$tmp"
    append_tunables_block "$tmp"
    before=$(wc -l < "$tmp")
    append_tunables_block "$tmp"
    after=$(wc -l < "$tmp")
    [ "$before" = "$after" ] || fail "not idempotent (before=$before after=$after)"
    rm -f "$tmp"
}

@test "append_tunables_block_preserves_existing_content" {
    local tmp
    tmp="$(mktemp)"; printf 'HOST="HB"\nPASS_RDP="secret"\nAUDIO_REDIRECT=0\n' > "$tmp"
    append_tunables_block "$tmp"
    grep -q '^HOST="HB"$' "$tmp"         || fail "original HOST line corrupted"
    grep -q '^PASS_RDP="secret"$' "$tmp" || fail "original PASS_RDP line corrupted"
    grep -q '^AUDIO_REDIRECT=0$' "$tmp"  || fail "existing AUDIO_REDIRECT value clobbered"
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
    run grep -cF 'append_tunables_block' "$engine"
    assert_success; [ "$output" != "0" ] || fail "engine doesn't call append_tunables_block"
}

@test "engine_help_uses_color_helpers" {
    local engine="${REPO_ROOT}/engine/rdp-connect"
    [ -f "$engine" ] || fail "engine missing at $engine"
    run grep -cF 'setup_colors' "$engine"
    assert_success; [ "$output" != "0" ] || fail "engine doesn't call setup_colors (no colored help)"
}
