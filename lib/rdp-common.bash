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
# F3 — Hardened profile/i18n parser
# ---------------------------------------------------------------------------
# parse_env_safe <file> [profile|i18n]
#
# Parses a KEY=value env file line-by-line and assigns allowlisted keys via
# `printf -v`. Never sources, evals, or execs file content. Returns 0 on
# success, 1 on the first rejected line (with a 'parse_env_safe: <file>:<line>:
# <reason>' diagnostic on stderr).
#
# Mode 'profile' (default): only the seven keys in _PROFILE_KEYS are accepted.
# Mode 'i18n': only keys matching the MSG_* prefix are accepted.
#
# Value normalization by leading character:
#   double-quote  → strip outer quotes; interior '#' preserved verbatim
#   single-quote  → strip outer quotes; interior '#' preserved verbatim
#   unquoted      → strip trailing ' # comment' (whitespace-then-#), trim ws
#
# Augmentation beyond design.md (per task T1.2 prompt): an unquoted value
# containing '#' WITHOUT preceding whitespace (e.g. `KEY=value# x`) is
# rejected — it is ambiguous (typo'ed comment delimiter or leaky quote) and
# silently truncating it to `value#` would corrupt the data. Forces the user
# to be explicit. See apply-progress T1.2 deviations note.
parse_env_safe() {
  local file="$1" mode="${2:-profile}" line key raw value lineno=0 q
  # shellcheck disable=SC2094  # _reject writes stderr only; $file is read-only input
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    line="${line#"${line%%[![:space:]]*}"}"           # trim leading whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue    # blank / full-line comment
    [[ "$line" != *=* ]] && { _reject "$file" "$lineno" "no '=' delimiter"; return 1; }
    key="${line%%=*}"; raw="${line#*=}"                # split on FIRST '=' → preserves '=' in passwords
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _reject "$file" "$lineno" "invalid key '$key'"; return 1; }
    # allowlist BEFORE any assignment (spec: "no printf -v on unknown keys")
    # NOTE: `-v` (is-set) test, NOT `${arr[$k]}` — under `set -u` a missing assoc
    # key raises "unbound variable" before `[[ -n ]]` can return false. Verified
    # in design and re-verified by tests/parser-probe.sh (runs under `set -u`).
    case "$mode" in
      profile) [[ -v _PROFILE_KEYS[$key] ]] || { _reject "$file" "$lineno" "rejected key '$key'"; return 1; } ;;
      i18n)    [[ "$key" == MSG_* ]]         || { _reject "$file" "$lineno" "rejected i18n key '$key'"; return 1; } ;;
      *)        _reject "$file" "$lineno" "unknown mode '$mode'"; return 1 ;;
    esac
    # value normalization by leading char
    if   [[ "$raw" == \"* ]]; then q=\"                  # double-quoted
    elif [[ "$raw" == \'* ]]; then q=\'                  # single-quoted
    else q=                                              # unquoted
    fi
    if [[ -n "$q" ]]; then
      [[ "$raw" != *"$q" ]] && { _reject "$file" "$lineno" "unterminated quote"; return 1; }
      value="${raw:1:${#raw}-2}"                         # strip outer quotes; interior '#' preserved verbatim
    else
      # augmentation: reject unquoted '#' without preceding whitespace
      if [[ "$raw" == *#* && "$raw" != *[[:space:]]#* ]]; then
        _reject "$file" "$lineno" "unquoted value contains '#' without preceding whitespace (quote the value or add whitespace before the comment)"
        return 1
      fi
      value="${raw%%[[:space:]]#*}"                      # strip unquoted inline comment (ws + '#')
      value="${value%"${value##*[![:space:]]}"}"         # trim trailing whitespace
    fi
    printf -v "$key" '%s' "$value"                       # key is charset+allowlist validated; format is literal %s → no execution of profile content
  done < "$file"
}

# ---------------------------------------------------------------------------
# F5 — uid-private PID path under XDG_RUNTIME_DIR
# ---------------------------------------------------------------------------
# compute_pid_path <profile>
#
# Returns the per-profile, uid-private lockfile path. Resolves to
#   /run/user/<uid>/rdp-<profile>-<uid>.pid   when XDG_RUNTIME_DIR is set
#   /tmp/rdp-<profile>-<uid>.pid              on the fallback (uid suffix
#                                              STILL present so two users on
#                                              the same host cannot collide).
# XDG_RUNTIME_DIR is 0700 and per-user on systemd distros; using it removes
# the symlink/DoS vector the legacy /tmp/rdp-<profile>.pid path exposed.
compute_pid_path() {
  printf '%s/rdp-%s-%s.pid' "${XDG_RUNTIME_DIR:-/tmp}" "$1" "$(id -u)"
}
