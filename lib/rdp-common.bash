# shellcheck shell=bash
# rdp-common.bash — pure-function library sourced by engine/rdp-connect
# and by the install-time smoke test (parser probe).
#
# This file is sourced, not executed. Functions are added incrementally per
# the baseline-hardening plan (see openspec/changes/baseline-hardening/):
#
#   parse_env_safe      — T1.2 (F3 hardened profile/i18n parser with allowlist)
#   compute_pid_path    — T1.4 (F5 uid-private PID path under XDG_RUNTIME_DIR)
#   compute_dpi_flags   — T2.1 (F1 jq-native HiDPI scale math)
#   build_mon_flags     — T2.2 (F8 array-based monitor flags)
#   require_cmd         — T2.2 (F6 startup dependency preflight)
#
# T1.1 ships ONLY the allowlist declaration, the _reject error reporter,
# and stub functions. The engine in T1.1 still defines its inline parse_env_safe
# (verbatim extraction); the lib is deployed but not yet sourced by the engine.
# T1.2 implements parse_env_safe in this file and flips the engine to source it.

# ---------------------------------------------------------------------------
# F3 — Profile key allowlist
# ---------------------------------------------------------------------------
# Keys accepted in profile files (~/.config/rdp/profiles/*.env). Any key
# outside this set is rejected by parse_env_safe before any assignment.
# Mode 'i18n' accepts keys matching the MSG_* prefix instead.
declare -A _PROFILE_KEYS=(
  [HOST]=1
  [USER_RDP]=1
  [PASS_RDP]=1
  [DOMAIN]=1
  [VPN_CHECK]=1
  [PREFERRED_WS]=1
  [LANG_OVERRIDE]=1
)

# ---------------------------------------------------------------------------
# F3 — Error reporter for parse_env_safe
# ---------------------------------------------------------------------------
# Emits 'parse_env_safe: <file>:<lineno>: <reason>' to stderr so callers and
# users can locate the offending line in the source profile/i18n file.
_reject() {
  printf 'parse_env_safe: %s:%d: %s\n' "$1" "$2" "$3" >&2
}

# ---------------------------------------------------------------------------
# F3 — Hardened profile/i18n parser (implementation lands in T1.2)
# ---------------------------------------------------------------------------
# parse_env_safe <file> [profile|i18n]
#
# T1.1 STUB: returns 0 without parsing. This is safe because the T1.1 engine
# still defines its own inline parse_env_safe (the verbatim heredoc body) and
# does not yet source this library. The full allowlist/quote/comment logic is
# implemented in T1.2 per design.md (parser decision section).
parse_env_safe() {
  return 0
}

# ---------------------------------------------------------------------------
# F5 — uid-private PID path (implementation lands in T1.4)
# ---------------------------------------------------------------------------
# compute_pid_path <profile>
#
# T1.1 STUB: returns 0 without printing a path. The T1.1 engine still hard-
# codes PID_FILE="/tmp/rdp-${PROFILE}.pid" (the verbatim heredoc body) and
# does not yet call this function. The XDG_RUNTIME_DIR + uid-suffix logic is
# implemented in T1.4 per design.md (PID path decision section).
compute_pid_path() {
  return 0
}
