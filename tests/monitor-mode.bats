#!/usr/bin/env bats
# tests/monitor-mode.bats — covers the single vs multi monitor mode toggle.
#
# Under Hyprland/XWayland, xfreerdp3 cannot span a single window across
# physical monitors — /multimon renders all remote monitors into ONE client
# window (cramped, non-resizable). The user wants to choose between that
# (multi) and single-monitor fullscreen (one remote monitor, fullscreened).
#
# Two control surfaces, same pattern as the audio toggle:
#   - Profile keys: MONITOR_MODE (multi [default] | single) + MONITOR_ID
#     (which remote monitor in single mode, default 0).
#   - CLI flags: --single-mon / --multi-mon (per-invocation override).
#
# Single mode always applies "+dynamic-resolution" (windowed, resizable RDP
# session — no more fixed /size+f) and the window is set floating +
# auto-fullscreened via the classic `setfloating` / `fullscreen "0"` hyprctl
# dispatchers (WM-level, not an xfreerdp3 flag — see hyprland-api.bats for
# why classic dispatch, not Lua hl.dsp.*, is correct here). This means
# un-fullscreening (or dragging) the floating window always leaves a freely
# resizable session whose RDP resolution follows the window live.
# Multi mode delegates to build_mon_flags (/multimon /monitors:<all>) —
# unchanged default behavior.
#
# Coverage:
#   - Behavioral (parse_env_safe): MONITOR_MODE and MONITOR_ID accepted in
#     profile mode (allowlist). Direct call (not `run`) so the printf -v global
#     assignment propagates to the assertion.
#   - Structural (engine): --single-mon/--multi-mon parsed, MON_FLAGS built
#     conditionally on mode, +dynamic-resolution used in single mode
#     unconditionally, --help documents it.

load test_helper

# ============================================================================
# Behavioral — parse_env_safe allowlist (lib unit tests)
# ============================================================================

@test "parse_env_safe_accepts_MONITOR_MODE_multi" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_MODE=multi\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_MODE=multi (rc=$_rc)"
  [ "${MONITOR_MODE:-}" = "multi" ] || fail "MONITOR_MODE not assigned to 'multi'"
}

@test "parse_env_safe_accepts_MONITOR_MODE_single" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_MODE=single\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_MODE=single (rc=$_rc)"
  [ "${MONITOR_MODE:-}" = "single" ] || fail "MONITOR_MODE not assigned to 'single'"
}

@test "parse_env_safe_accepts_MONITOR_ID" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'MONITOR_ID=2\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected MONITOR_ID=2 (rc=$_rc)"
  [ "${MONITOR_ID:-}" = "2" ] || fail "MONITOR_ID not assigned to '2'"
}

# ============================================================================
# Structural — engine arg parsing + MON_FLAGS construction (source-grep, -F)
# ============================================================================

@test "engine_parses_single_mon_and_multi_mon_flags" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--single-mon' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--single-mon not handled"
  run grep -cF -- '--multi-mon' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "--multi-mon not handled"
  run grep -cE 'MONITOR_MODE_OVERRIDE' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "MONITOR_MODE_OVERRIDE missing"
}

@test "engine_builds_MON_FLAGS_conditionally_on_monitor_mode" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Single mode: always +dynamic-resolution (windowed, resizable) — fullscreen
  # on launch comes from the classic `fullscreen "0"` hyprctl dispatcher, not
  # an xfreerdp3 /size+f flag, so leaving fullscreen always yields a live-
  # resizable session.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF '+dynamic-resolution'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode missing '+dynamic-resolution'"
  # MONITOR_MODE consulted in code.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'MONITOR_MODE'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "MONITOR_MODE not consulted in CODE"
}

@test "monitor_mode_flags_documented_in_help" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cF -- '--single-mon' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--single-mon should appear in parsing AND --help (found $output)"
  run grep -cF -- '--multi-mon' "$engine"
  assert_success
  [ "$output" -ge 2 ] || fail "--multi-mon should appear in parsing AND --help (found $output)"
}

@test "engine_single_mode_overrides_PREFERRED_WS_workspace_for_the_target_monitor" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # A user's hyprland.conf can pin a workspace to a SPECIFIC monitor
  # (`workspace=N,monitor:desc:...`). Confirmed live: with PREFERRED_WS
  # statically pinned to monitor B, selecting monitor A via MONITOR_ID moved
  # the window there for an instant, then `fullscreen` snapped it back onto
  # workspace PREFERRED_WS's bound monitor (B) — the checkbox's monitor
  # choice was silently overridden. Fix: _EFF_WS (defaults to PREFERRED_WS)
  # is overridden to the TARGET monitor's own activeWorkspace when MONITOR_ID
  # resolves one, and the background dispatcher moves to $_EFF_WS instead of
  # the raw $PREFERRED_WS.
  run bash -c "awk '/^    single\\)/,/^        ;;/' '$engine' | grep -cF '_EFF_WS='"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode does not override _EFF_WS from the target monitor's activeWorkspace"
  # compositor-aware PR2: the dispatcher calls the lib wrapper; the emitted
  # hyprctl argv (movetoworkspacesilent "<ws>,class:...") is byte-identical,
  # locked by compositor-backends.bats::dispatch_golden_argv_hypr_forms.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch_move_to_ws \"\$_EFF_WS\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "background dispatcher still moves to raw \$PREFERRED_WS instead of \$_EFF_WS"
}

@test "engine_single_mode_caps_canvas_via_MONITOR_id_override" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # MONITOR_<id> (e.g. MONITOR_2="2560x1080") revived: caps the RDP canvas
  # below the monitor's real size WITHOUT touching the monitor's own
  # Hyprland resolution — e.g. matching a shorter neighboring monitor's
  # content height on a taller panel, without cropping the panel's real
  # desktop for everything else.
  run bash -c "awk '/^    single\\)/,/^        ;;/' '$engine' | grep -cF 'MONITOR_\${MONITOR_ID}'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode does not look up MONITOR_<id> via indirect expansion"
  run bash -c "awk '/^    single\\)/,/^        ;;/' '$engine' | grep -cF '/size:\${_SINGLE_W}x\${_SINGLE_H}'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode does not build /size: from the MONITOR_<id> override"
}

@test "engine_single_mode_skips_fullscreen_dispatch_when_canvas_is_capped" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # `fullscreen` always fills the WHOLE monitor — it must be skipped (in
  # favor of an exact resizewindowpixel) whenever MONITOR_<id> capped the
  # canvas below the monitor's real size, or the cap would be silently
  # overridden on every dispatch pass (initial AND settle retry).
  # (PR2: exact resize now via the lib wrapper — same argv, locked by the
  # golden-argv test in compositor-backends.bats.)
  run bash -c "grep -A5 'silently override the cap' '$engine' | grep -cF 'dispatch_resize'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "capped-canvas branch does not use exact resize (dispatch_resize)"
}

@test "engine_single_mode_re_dispatches_geometry_after_a_settle_delay" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Same defensive pattern as span mode's settle retry (tests/span-mode.bats)
  # — added after "still doesn't work" reports for the target-monitor path
  # even after the PREFERRED_WS/_EFF_WS fix, suggesting a timing race on the
  # first dispatch pass rather than a pure logic bug.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -A20 'fullscreen (single-mon)' | grep -cF 'sleep'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode has no settle-retry sleep after the initial dispatch"
  # PR2: exact move now via the dispatch_move wrapper (byte-identical argv).
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -A20 'fullscreen (single-mon)' | grep -cF 'dispatch_move'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode does not re-dispatch the exact move in the settle retry"
}

@test "engine_single_mode_positions_window_on_MONITOR_ID_when_set" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Revived MONITOR_ID (writer: the pre-connect checkbox menu) — single mode
  # must compute an origin from it and the background dispatcher must move
  # the window there before fullscreening.
  run bash -c "awk '/^    single\\)/,/^        ;;/' '$engine' | grep -cF 'MONITOR_ID'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "single mode case arm does not consult MONITOR_ID"
  # PR2: the dispatcher's exact move goes through dispatch_move (the wrapper
  # emits the byte-identical `movewindowpixel "exact <x> <y>,class:..."`).
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'dispatch_move \"\$_SINGLE_X\"'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "background dispatcher does not move the window to _SINGLE_X/_SINGLE_Y"
}
