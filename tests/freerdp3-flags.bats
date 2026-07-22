#!/usr/bin/env bats
# tests/freerdp3-flags.bats — engine xfreerdp3 flag compatibility with FreeRDP 3
#
# Born from a real breakage: the engine's xfreerdp3 invocation used four flags
# that FreeRDP 3 no longer accepts. Against xfreerdp3 3.30.0 (Arch extra/freerdp
# 2:3.30.0-1) the command line was rejected with:
#     [WARN] Unsupported command line syntax!
#     [WARN] FreeRDP 1.0 style syntax was dropped with version 3!
# ...followed by exit 255, which the engine's setsid wrapper surfaced as the
# confusing "setsid: child N did not exit normally: Success".
#
# The four offenders (isolated empirically by appending each flag to a minimal
# known-good base and grepping xfreerdp3's stderr for "Unexpected keyword"):
#   /async-input            — removed in v3 (async input is now default)
#   /async-transport        — removed in v3
#   /camera                 — removed/renamed in v3
#   /reconnect-max-retries: — RENAMED to /auto-reconnect-max-retries: in v3
#
# The +/- boolean prefix (e.g. +grab-keyboard, +clipboard, +aero) is DEPRECATED
# in v3 but still accepted (not an error) — it is intentionally NOT asserted
# here, since flagging it would be a false positive against the current build.
#
# This file is a source-grep regression backstop: if a future change re-introduces
# any of the four removed/renamed flags, the @test fails loud. Per the repo's
# ci_xfreerdp3_strategy design decision, real xfreerdp3 execution stays
# manual-verify — this is the structural assertion that guards the contract.
#
# Compatibility note on grep -c: grep returns rc=1 when NO lines match and
# prints "0". `run` captures rc=1 into $status and "0" into $output. We assert
# BOTH $status -ne 0 (no match) AND $output == "0" (count) for robustness.

load test_helper

@test "engine_does_not_use_async_input_flag_dropped_in_freerdp3" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cE '^[[:space:]]*/async-input([[:space:]]|$)' "$engine"
  [ "$status" -ne 0 ] || fail "/async-input present — dropped in FreeRDP 3"
  assert_output "0"
}

@test "engine_does_not_use_async_transport_flag_dropped_in_freerdp3" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cE '^[[:space:]]*/async-transport([[:space:]]|$)' "$engine"
  [ "$status" -ne 0 ] || fail "/async-transport present — dropped in FreeRDP 3"
  assert_output "0"
}

@test "engine_does_not_use_camera_flag_dropped_in_freerdp3" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cE '^[[:space:]]*/camera([[:space:]]|$)' "$engine"
  [ "$status" -ne 0 ] || fail "/camera present — dropped/renamed in FreeRDP 3"
  assert_output "0"
}

@test "engine_uses_renamed_auto_reconnect_max_retries_flag" {
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Old name (renamed in v3) MUST be absent.
  run grep -cE '/reconnect-max-retries:' "$engine"
  [ "$status" -ne 0 ] || fail "old /reconnect-max-retries: present — renamed in v3"
  assert_output "0"
  # New name MUST be present.
  run grep -cE '/auto-reconnect-max-retries:' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "/auto-reconnect-max-retries: missing from engine"
}

@test "engine_does_not_pass_phantom_empty_arg_from_empty_flag_array" {
  # Bash gotcha: "${arr[@]-}" with a DECLARED-EMPTY array yields a single
  # empty-string token (argc=1), NOT zero tokens. xfreerdp3 3.30.0 rejects an
  # empty argument with the same "Unsupported command line syntax! / FreeRDP
  # 1.0 style syntax was dropped" warning as a genuinely bad flag.
  #
  # The engine's DPI_FLAGS is empty when monitor scale==1.0, so the form
  # "${DPI_FLAGS[@]-}" injected a phantom '' into the xfreerdp3 argv that broke
  # parsing on any non-HiDPI display — exactly the user's "setsid: child did
  # not exit normally" failure. The correct form is "${arr[@]}" (bash 4.4+ does
  # NOT trip set -u on an empty array, so the `-` default-on-unset guard is
  # both unnecessary and actively harmful here).
  #
  # This test fails if ANY "${...[@]-}" form reappears in the engine.
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # Strip comment lines first — the engine's own comment block DOCUMENTS this
  # gotcha using the literal bad form "${arr[@]-}", which is legitimate prose,
  # not a regression. Only actual invocation lines matter.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cE '\[@\]-'"
  [ "$status" -ne 0 ] || fail "found '\${arr[@]-}' in CODE — emits a phantom empty arg on an empty array (breaks xfreerdp3)"
  assert_output "0"
}

@test "engine_uses_pulse_sound_backend_not_pipewire" {
  # FreeRDP 3.30.0's pipewire sound addin fails to load on the Arch build
  # ("Failed to load channel rdpsnd [pipewire]" / error 1359 /
  # ERRCONNECT_POST_CONNECT_FAILED), tearing down the WHOLE session
  # post-connect — even though the pipewire daemon itself is healthy. The
  # pulse backend works via pipewire-pulse compat (the standard modern Linux
  # desktop: pipewire + pipewire-pulse). Verified empirically against
  # HB-TiPartner: sys:pipewire -> rc=138 (session died); sys:pulse -> rc=124
  # (alive 8s, gdi_init_ex clean).
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  # No pipewire backend in sound/microphone code lines.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cE 'sys:pipewire'"
  [ "$status" -ne 0 ] || fail "found 'sys:pipewire' in CODE — FreeRDP 3.30.0 pipewire addin fails to load (POST_CONNECT_FAILED)"
  assert_output "0"
  # Pulse backend present for both sound and microphone.
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cE '/sound:sys:pulse'"
  assert_success
  [ "$output" != "0" ] || fail "/sound:sys:pulse missing"
  run bash -c "grep -vE '^[[:space:]]*#' '$engine' | grep -cE '/microphone:sys:pulse'"
  assert_success
  [ "$output" != "0" ] || fail "/microphone:sys:pulse missing"
}

@test "engine_still_uses_valid_freerdp3_invocation_core" {
  # Sanity: the valid core of the invocation is intact (regression guard against
  # an over-aggressive edit that strips working flags along with the bad ones).
  local engine="${REPO_ROOT}/engine/rdp-connect"
  [ -f "$engine" ] || fail "engine missing at $engine"
  run grep -cE '/from-stdin:force' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "/from-stdin:force missing (credential pipe)"
  run grep -cE '/sec:nla' "$engine"
  assert_success
  [ "$output" != "0" ] || fail "/sec:nla missing"
}
