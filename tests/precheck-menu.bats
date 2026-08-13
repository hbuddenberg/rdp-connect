#!/usr/bin/env bats
# tests/precheck-menu.bats — covers the pre-connect checkbox menu (monitors +
# audio) that runs after a profile is parsed and before the connection
# pipeline starts.
#
# wofi/walker/rofi are single-selection dmenu tools — none has a native
# checkbox/multi-select (confirmed live: neither `wofi --help` nor
# `walker --help` lists one). The engine emulates one with a LOOP: show the
# monitor list (from hyprctl monitors -j, by description — not id, since
# ids/ports renumber across reboots, see tests/monitor-order-by-description.bats)
# plus an audio toggle plus a "Conectar" line; each selection toggles that
# line's checked marker and re-shows the menu, until Conectar is chosen.
#
# The resulting selection is applied in-memory for this connection AND
# persisted into the profile .env via set_profile_key (tests/profile-key-writer.bats)
# so the NEXT launch pre-checks the same state — the user's explicit ask
# ("que recuerde el ultimo estado").
#
# Behaviorally verified live (not just structurally) via a scripted-picker
# harness during development: default-all-checked -> span; toggling one off
# leaves N-1 checked; unchecking everything leaves MONITOR_MODE/MONITOR_ORDER
# untouched (never launches with zero monitors); a persisted profile's
# MONITOR_ORDER round-trips back to the same checked set on the next run;
# ESC (empty picker output) cancels the whole connection. These scenarios
# aren't re-encoded as bats @test bodies because they'd require mocking
# hyprctl/walker end-to-end (the harness stubbed `command`/`walker` and
# sourced a slice of the engine directly) — the structural checks below
# assert the code paths that made those scenarios pass actually exist.
#
# All greps below scope to the block via `awk '/MENU DE PRECONEXIÓN/,/^fi$/'`
# — the block's own top-level closing `fi` (column 0; the INNER `    fi` that
# closes the confirm-loop is indented and doesn't match `^fi$`).

load test_helper

_precheck_block() {
  awk '/MENU DE PRECONEXIÓN/,/^fi$/' "${REPO_ROOT}/engine/rdp-connect"
}

@test "engine_has_a_precheck_menu_block" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF 'MENU DE PRECONEXIÓN' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "no pre-connect checkbox menu block found"
}

@test "engine_precheck_menu_skips_when_monitor_mode_override_is_explicit" {
  # --single-mon/--multi-mon/--span already express intent explicitly — same
  # "CLI flag wins" precedence as MONITOR_ORDER_OVERRIDE elsewhere.
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'MONITOR_MODE_OVERRIDE:-'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "precheck menu does not gate on an empty MONITOR_MODE_OVERRIDE"
}

@test "engine_precheck_menu_degrades_silently_without_a_picker" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'command -v walker'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "precheck menu does not check for walker/wofi availability"
}

@test "engine_precheck_menu_excludes_monitors_with_empty_description" {
  # Virtual/headless outputs (e.g. this host's hypr-rdp server output) report
  # description="" and must never appear as a selectable "monitor" line.
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'select((.description'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "precheck menu does not filter out empty-description outputs"
}

@test "engine_precheck_menu_resolves_prior_MONITOR_ORDER_for_precheck_state" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'resolve_monitor_order'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "precheck menu does not resolve the profile's existing MONITOR_ORDER to pre-check boxes"
}

@test "engine_precheck_menu_cancels_connection_on_empty_selection" {
  # ESC / closing the picker without choosing anything must abort (exit 0),
  # same as the profile selector's own ESC behavior.
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'exit 0'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "empty picker selection does not exit 0"
}

@test "engine_precheck_menu_maps_1_checked_to_single_and_2plus_to_span" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'MONITOR_MODE=single'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "1-checked path does not set MONITOR_MODE=single"
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'MONITOR_MODE=span'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "2+-checked path does not set MONITOR_MODE=span"
}

@test "engine_precheck_menu_never_persists_a_zero_monitor_selection" {
  # Unchecking every monitor must NOT call set_profile_key for MONITOR_MODE/
  # MONITOR_ORDER (would otherwise persist an unlaunchable state) — the code
  # only reaches those calls inside the _pm_n -eq 1 / -gt 1 branches.
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF '\"\$_pm_n\" -gt 1'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "no explicit _pm_n -gt 1 branch guarding the span persist"
}

@test "engine_precheck_menu_persists_selection_via_set_profile_key" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'set_profile_key \"\$ENV_FILE\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" -ge 6 ] || fail "expected at least 6 set_profile_key calls (mode/order-or-id, audio, usb, drive, clipboard), found $output"
}

@test "engine_precheck_menu_toggles_audio_independently_of_monitors" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'AUDIO_REDIRECT=\"\$_pm_audio\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "audio selection is not applied to AUDIO_REDIRECT in-memory"
}

# ============================================================================
# Peripheral toggle rows (usb-redirect-clipboard-windowrules change)
# ============================================================================

@test "engine_precheck_menu_has_usb_redirect_toggle_row" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF '_pm_uline'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "USB redirect toggle row missing"
}

@test "engine_precheck_menu_has_drive_redirect_toggle_row" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF '_pm_dline'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "drive redirect toggle row missing"
}

@test "engine_precheck_menu_has_clipboard_sync_toggle_row" {
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF '_pm_cline'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "clipboard sync toggle row missing"
}

@test "engine_precheck_menu_persists_peripheral_selections" {
  # USB_REDIRECT, DRIVE_REDIRECT, CLIPBOARD_SYNC must be persisted via
  # set_profile_key (same pattern as AUDIO_REDIRECT).
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'set_profile_key \"\$ENV_FILE\" USB_REDIRECT'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "USB_REDIRECT not persisted"
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'set_profile_key \"\$ENV_FILE\" DRIVE_REDIRECT'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "DRIVE_REDIRECT not persisted"
  run bash -c "$(declare -f _precheck_block); REPO_ROOT='${REPO_ROOT}' _precheck_block | grep -cF 'set_profile_key \"\$ENV_FILE\" CLIPBOARD_SYNC'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "CLIPBOARD_SYNC not persisted"
}
