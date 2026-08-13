#!/usr/bin/env bats
# tests/peripheral-flags.bats — pure-fn coverage for the three peripheral
# flag builders (USB / drive / clipboard) and the allowlist extension that
# admits the 5 new profile keys.
#
# Change: usb-redirect-clipboard-windowrules
# Spec provenance:
#   - peripheral-redirect (USB / drive / clipboard toggle requirements)
#   - engine-security (allowlist; non-peripheral key still rejected)
#   - engine-robustness (FLAGS-array contract — no phantom empty arg)
#
# Strict TDD: this file is written BEFORE the production code. The @tests
# fail (RED) until lib/rdp-common.bash ships build_usb_flags /
# build_drive_flags / build_clipboard_flags and the 5-key allowlist
# extension.

load test_helper

# ============================================================================
# Phase 1 — allowlist extension (5 new keys)
# ============================================================================

@test "parse_env_safe_accepts_USB_REDIRECT" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'USB_REDIRECT=1\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected USB_REDIRECT=1 (rc=$_rc)"
  [ "${USB_REDIRECT:-}" = "1" ] || fail "USB_REDIRECT not assigned to '1'"
}

@test "parse_env_safe_accepts_USB_DEVICE_IDS" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'USB_DEVICE_IDS=0781:5580\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected USB_DEVICE_IDS (rc=$_rc)"
  [ "${USB_DEVICE_IDS:-}" = "0781:5580" ] || fail "USB_DEVICE_IDS not assigned"
}

@test "parse_env_safe_accepts_DRIVE_REDIRECT" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'DRIVE_REDIRECT=0\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected DRIVE_REDIRECT=0 (rc=$_rc)"
  [ "${DRIVE_REDIRECT:-}" = "0" ] || fail "DRIVE_REDIRECT not assigned to '0'"
}

@test "parse_env_safe_accepts_SHARE_DIR" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'SHARE_DIR=/data/shared\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected SHARE_DIR (rc=$_rc)"
  [ "${SHARE_DIR:-}" = "/data/shared" ] || fail "SHARE_DIR not assigned"
}

@test "parse_env_safe_accepts_CLIPBOARD_SYNC" {
  local tmp _rc
  tmp="$(mktemp)"
  printf 'CLIPBOARD_SYNC=1\n' > "$tmp"
  parse_env_safe "$tmp" profile && _rc=0 || _rc=$?
  rm -f "$tmp"
  [ "$_rc" -eq 0 ] || fail "parse_env_safe rejected CLIPBOARD_SYNC=1 (rc=$_rc)"
  [ "${CLIPBOARD_SYNC:-}" = "1" ] || fail "CLIPBOARD_SYNC not assigned to '1'"
}

@test "parse_env_safe_still_rejects_non_allowlisted_key" {
  parse_env_safe_under_setu 'NOT_A_REAL_KEY=whatever\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "1" ]
}

@test "legacy_profile_without_peripheral_keys_parses_cleanly_under_setu" {
  # A profile that only has the pre-existing keys must still parse (zero
  # regression). The engine pre-inits the 5 new keys to "" so set -u won't
  # abort on a legacy profile that omits them.
  parse_env_safe_under_setu 'HOST=h\nUSER_RDP=u\nPASS_RDP=p\n' profile
  assert_success
  [ "${lines[0]%$'\t'*}" = "0" ]
}

# ============================================================================
# Phase 2 — build_usb_flags
# ============================================================================

@test "usb_default_off_emits_no_flag" {
  USB_REDIRECT="" USB_DEVICE_IDS="" _HAS_USB=1
  build_usb_flags
  [ "${#USB_FLAGS[@]}" -eq 0 ] || fail "USB_FLAGS should be empty when USB_REDIRECT unset/0"
}

@test "usb_redirect_zero_emits_no_flag" {
  USB_REDIRECT=0 USB_DEVICE_IDS="0781:5580" _HAS_USB=1
  build_usb_flags
  [ "${#USB_FLAGS[@]}" -eq 0 ] || fail "USB_FLAGS should be empty when USB_REDIRECT=0"
}

@test "usb_single_vid_pid_emits_usb_id_flag" {
  USB_REDIRECT=1 USB_DEVICE_IDS="0781:5580" _HAS_USB=1
  build_usb_flags
  [ "${#USB_FLAGS[@]}" -eq 1 ] || fail "expected 1 USB flag, got ${#USB_FLAGS[@]}"
  [ "${USB_FLAGS[0]}" = "/usb:id:0781:5580" ] || fail "wrong flag: ${USB_FLAGS[0]}"
}

@test "usb_multi_vid_pid_hash_separator" {
  USB_REDIRECT=1 USB_DEVICE_IDS="0781:5580#046d:c52b" _HAS_USB=1
  build_usb_flags
  [ "${#USB_FLAGS[@]}" -eq 1 ] || fail "expected 1 USB flag, got ${#USB_FLAGS[@]}"
  [ "${USB_FLAGS[0]}" = "/usb:id:0781:5580#046d:c52b" ] || fail "wrong flag: ${USB_FLAGS[0]}"
}

@test "usb_malformed_vid_pid_rejected_loudly" {
  USB_REDIRECT=1 USB_DEVICE_IDS="0781:558" _HAS_USB=1
  run build_usb_flags
  assert_failure
  [ "${#USB_FLAGS[@]}" -eq 0 ] || fail "USB_FLAGS must be empty on reject"
}

@test "usb_missing_device_ids_when_on_silent_skip" {
  # USB_REDIRECT=1 but USB_DEVICE_IDS empty -> silent-skip + WARN (not fatal).
  USB_REDIRECT=1 USB_DEVICE_IDS="" _HAS_USB=1
  LOG_FILE="$(mktemp)"
  build_usb_flags
  [ "${#USB_FLAGS[@]}" -eq 0 ] || fail "USB_FLAGS must be empty when USB_DEVICE_IDS not set"
  rm -f "$LOG_FILE"
}

@test "usb_unsupported_build_silent_skip_with_warn" {
  # USB_REDIRECT=1 but xfreerdp3 build lacks /usb: -> silent-skip + WARN log.
  USB_REDIRECT=1 USB_DEVICE_IDS="0781:5580" _HAS_USB=0
  LOG_FILE="$(mktemp)"
  build_usb_flags
  rm -f "$LOG_FILE"
   [ "${#USB_FLAGS[@]}" -eq 0 ] || fail "USB_FLAGS must be empty when /usb: unsupported"
}

# ============================================================================
# Phase 2 — build_webcam_flags
# ============================================================================

@test "webcam_default_off_emits_no_flag" {
  WEBCAM_REDIRECT="" _HAS_USB=1
  build_webcam_flags
  [ "${#WEBCAM_FLAGS[@]}" -eq 0 ] || fail "WEBCAM_FLAGS should be empty by default"
}

@test "webcam_off_emits_no_flag" {
  WEBCAM_REDIRECT=0 _HAS_USB=1
  build_webcam_flags
  [ "${#WEBCAM_FLAGS[@]}" -eq 0 ] || fail "WEBCAM_FLAGS should be empty when WEBCAM_REDIRECT=0"
}

@test "webcam_on_with_no_camera_silent_skip" {
  # WEBCAM_REDIRECT=1 but no camera detected -> silent-skip + WARN
  WEBCAM_REDIRECT=1 _HAS_USB=1
  # Mock lsusb to return empty (no camera)
  lsusb() { echo ""; }
  build_webcam_flags
  [ "${#WEBCAM_FLAGS[@]}" -eq 0 ] || fail "WEBCAM_FLAGS must be empty when no camera detected"
}

@test "webcam_on_with_unsupported_build_silent_skip" {
  # WEBCAM_REDIRECT=1 but xfreerdp3 lacks /usb: -> silent-skip + WARN
  WEBCAM_REDIRECT=1 _HAS_USB=0
  build_webcam_flags
  [ "${#WEBCAM_FLAGS[@]}" -eq 0 ] || fail "WEBCAM_FLAGS must be empty when /usb: unsupported"
}

@test "webcam_on_with_camera_detected_emits_flag" {
  # WEBCAM_REDIRECT=1 and camera detected -> emits /usb:id:<vid:pid>
  WEBCAM_REDIRECT=1 _HAS_USB=1
  # Mock lsusb to return a camera
  lsusb() { echo "Bus 001 Device 005: ID 328f:00c0 EMEET EMEET PIXY"; }
  build_webcam_flags
  [ "${#WEBCAM_FLAGS[@]}" -eq 1 ] || fail "expected 1 WEBCAM flag, got ${#WEBCAM_FLAGS[@]}"
  [[ "${WEBCAM_FLAGS[0]}" == /usb:id:328f:00c0 ]] || fail "wrong flag: ${WEBCAM_FLAGS[0]}"
}

# ============================================================================
# Phase 2 — build_drive_flags
# ============================================================================

@test "drive_default_on_emits_drive_flag" {
  DRIVE_REDIRECT="" SHARE_DIR=""
  build_drive_flags
  [ "${#DRIVE_FLAGS[@]}" -eq 1 ] || fail "expected 1 DRIVE flag (default on), got ${#DRIVE_FLAGS[@]}"
  [[ "${DRIVE_FLAGS[0]}" == /drive:compartido,* ]] || fail "wrong flag: ${DRIVE_FLAGS[0]}"
}

@test "drive_explicit_on_emits_flag" {
  DRIVE_REDIRECT=1 SHARE_DIR=""
  build_drive_flags
  [ "${#DRIVE_FLAGS[@]}" -eq 1 ] || fail "expected 1 DRIVE flag, got ${#DRIVE_FLAGS[@]}"
}

@test "drive_off_emits_no_flag" {
  DRIVE_REDIRECT=0 SHARE_DIR=""
  build_drive_flags
  [ "${#DRIVE_FLAGS[@]}" -eq 0 ] || fail "DRIVE_FLAGS should be empty when DRIVE_REDIRECT=0"
}

@test "drive_custom_share_dir_honored" {
  DRIVE_REDIRECT=1 SHARE_DIR="/data/shared"
  build_drive_flags
  [ "${#DRIVE_FLAGS[@]}" -eq 1 ] || fail "expected 1 DRIVE flag"
  [ "${DRIVE_FLAGS[0]}" = "/drive:compartido,/data/shared" ] || fail "wrong flag: ${DRIVE_FLAGS[0]}"
}

# ============================================================================
# Phase 2 — build_clipboard_flags
# ============================================================================

@test "clipboard_default_on_emits_plus_clipboard" {
  CLIPBOARD_SYNC=""
  build_clipboard_flags
  [ "${#CLIPBOARD_FLAGS[@]}" -eq 1 ] || fail "expected 1 CLIPBOARD flag (default on)"
  [ "${CLIPBOARD_FLAGS[0]}" = "+clipboard" ] || fail "wrong flag: ${CLIPBOARD_FLAGS[0]}"
}

@test "clipboard_explicit_on_emits_flag" {
  CLIPBOARD_SYNC=1
  build_clipboard_flags
  [ "${#CLIPBOARD_FLAGS[@]}" -eq 1 ] || fail "expected 1 CLIPBOARD flag"
  [ "${CLIPBOARD_FLAGS[0]}" = "+clipboard" ]
}

@test "clipboard_off_emits_no_flag" {
  CLIPBOARD_SYNC=0
  build_clipboard_flags
  [ "${#CLIPBOARD_FLAGS[@]}" -eq 0 ] || fail "CLIPBOARD_FLAGS should be empty when CLIPBOARD_SYNC=0"
}

# ============================================================================
# Engine-robustness: FLAGS-array contract
# ============================================================================

@test "empty_peripheral_arrays_no_phantom_arg" {
  # "${ARR[@]-}" on a declared-empty array yields a single empty-string token
  # (argc=1), NOT zero tokens. The correct form is "${ARR[@]}" (bash 4.4+
  # does NOT trip set -u on empty arrays). Verify the arrays are DECLARED
  # (so "${ARR[@]}" is safe) after each fn runs with OFF inputs.
  USB_REDIRECT=0 USB_DEVICE_IDS="" _HAS_USB=1
  DRIVE_REDIRECT=0 SHARE_DIR=""
  CLIPBOARD_SYNC=0
  build_usb_flags
  build_drive_flags
  build_clipboard_flags
  # All three are declared (even if empty) — this is the contract.
  declare -p USB_FLAGS >/dev/null || fail "USB_FLAGS not declared"
  declare -p DRIVE_FLAGS >/dev/null || fail "DRIVE_FLAGS not declared"
  declare -p CLIPBOARD_FLAGS >/dev/null || fail "CLIPBOARD_FLAGS not declared"
}

@test "build_fns_are_pure_no_engine_globals_required" {
  # The 3 fns must not require any engine-only globals (no _RDP_CLIENT,
  # no LOG_FILE for their core logic — log_event is best-effort). Run them
  # in a clean subshell with only the explicit inputs set.
  (
    unset _RDP_CLIENT MON_FLAGS DPI_FLAGS SOUND_FLAGS
    USB_REDIRECT=1 USB_DEVICE_IDS="0781:5580" _HAS_USB=1
    DRIVE_REDIRECT=1 SHARE_DIR="/tmp/x"
    CLIPBOARD_SYNC=1
    LOG_FILE="/dev/null"
    build_usb_flags
    build_drive_flags
    build_clipboard_flags
    [ "${#USB_FLAGS[@]}" -eq 1 ]
    [ "${#DRIVE_FLAGS[@]}" -eq 1 ]
    [ "${#CLIPBOARD_FLAGS[@]}" -eq 1 ]
  ) || fail "build fn required an engine global it should not"
}
