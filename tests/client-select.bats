#!/usr/bin/env bats
# tests/client-select.bats — CLIENT selection (x11 | sdl | wayland).
#
# The engine can use 3 FreeRDP clients:
#   x11 (default)  -> xfreerdp3   (XWayland, current, best for single-mon)
#   sdl            -> sdl-freerdp3 (SDL3, needs FREERDP_WLROOTS_HACK=force +
#                      SDL_VIDEODRIVER=wayland + grab flags for multimon input)
#   wayland        -> wlfreerdp3  (native Wayland, single-mon)
#
# CLIENT profile key + --client CLI flag override. The engine uses a variable
# binary (${_RDP_CLIENT}) instead of hardcoding xfreerdp3.

load test_helper

@test "parse_env_safe_accepts_CLIENT" {
  local tmp _rc
  tmp="$(mktemp)"; printf 'CLIENT=sdl\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "CLIENT rejected (rc=$_rc)"
  [ "${CLIENT:-}" = "sdl" ] || fail "CLIENT not assigned"
}

@test "engine_parses_client_flag" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing"
  run grep -cF -- '--client' "$engine"
  assert_success; [ "$output" != "0" ] || fail "--client not handled"
}

@test "engine_uses_variable_client_binary_not_hardcoded_xfreerdp3" {
  # The invocation must use ${_RDP_CLIENT} (or equivalent variable), not a
  # hardcoded 'xfreerdp3', so sdl-freerdp3 / wlfreerdp3 can be selected.
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'sdl-freerdp3'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "sdl-freerdp3 binary not referenced in CODE"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'wlfreerdp3'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "wlfreerdp3 binary not referenced in CODE"
}

@test "engine_sets_wlroots_hack_for_sdl" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'FREERDP_WLROOTS_HACK'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "FREERDP_WLROOTS_HACK not set for sdl client"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cF 'SDL_VIDEODRIVER'"
  [ "$status" -eq 0 ] || fail "grep failed"
  [ "$output" != "0" ] || fail "SDL_VIDEODRIVER=wayland not set for sdl client"
}
