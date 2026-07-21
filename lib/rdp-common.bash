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

# ---------------------------------------------------------------------------
# F1 — jq-native HiDPI scale math (replaces bc + python3)
# ---------------------------------------------------------------------------
# compute_dpi_flags
#
# Reads `.[0].scale` from `hyprctl monitors -j` via a SINGLE jq invocation and
# sets three globals:
#   DPI_FLAGS   — bash array, empty under 100%, else (/scale-desktop:N /smart-sizing)
#   IS_HIDPI    — "1" if scale > 1, else "0"
#   SCALE_PCT   — integer percentage (e.g. 150 for scale 1.5)
#
# Null / missing / non-numeric / malformed-JSON scale → IS_HIDPI=0 SCALE_PCT=100
# with a WARN log line naming the unparsable value. The engine MUST NOT abort
# on a scale-parse failure (spec: "Safe fallback when scale cannot be determined").
#
# jq notes:
#   - `tonumber` on null/missing/non-numeric throws → caught by `try/catch` →
#     lands in the WARN fallback branch. This is deliberately NOT using jq's `//`
#     alternative operator, which would silently substitute for null/missing and
#     mask the very "unparsable" case the spec requires to emit a WARN.
#   - `$n*100|round` produces the integer percentage without bc or python3.
compute_dpi_flags() {
  local raw scale_valid out
  IS_HIDPI=0
  SCALE_PCT=100
  DPI_FLAGS=()
  out=$(hyprctl monitors -j 2>/dev/null | jq -r '
      .[0].scale as $raw
    | (try ($raw | tonumber) catch null) as $n
    | if $n == null then "0\t100\tinvalid\t\($raw)"
      else (if $n > 1 then "1" else "0" end)
        + "\t" + (($n * 100) | round | tostring)
        + "\tvalid\t\($raw)"
      end
  ' 2>/dev/null) || out=""
  IFS=$'\t' read -r IS_HIDPI SCALE_PCT scale_valid raw <<<"$out"
  if [[ "$scale_valid" != "valid" ]]; then
    IS_HIDPI=0
    SCALE_PCT=100
    log_event "WARN" "unparsable monitor scale '${raw:-<missing>}'; defaulting to 100%"
  elif [[ "$IS_HIDPI" == "1" ]]; then
    # shellcheck disable=SC2034  # DPI_FLAGS consumed by engine/rdp-connect (sourced lib pattern)
    DPI_FLAGS=("/scale-desktop:${SCALE_PCT}" "/smart-sizing")
    log_event "INFO" "HiDPI scale ${raw} -> /scale-desktop:${SCALE_PCT}."
  fi
}

# ---------------------------------------------------------------------------
# F6 — require_cmd: startup dependency preflight
# ---------------------------------------------------------------------------
# require_cmd <name> [pkg_hint]
#
# Exits 127 with a clear message if <name> is not on PATH. The optional
# pkg_hint names the package the user should install. Called by the engine
# at startup — before any profile is loaded — so a missing binary never
# reaches a credential-adjacent code path.
require_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    printf 'missing required command: %s (install via your package manager, e.g. %s)\n' \
      "$cmd" "$pkg" >&2
    exit 127
  fi
}

# ---------------------------------------------------------------------------
# F8 — build_mon_flags: array-based monitor flags
# ---------------------------------------------------------------------------
# build_mon_flags <count> <ids>
#
# Sets MON_FLAGS[] as a bash array:
#   count > 1 → ("/multimon" "/monitors:<ids>")
#   count ≤ 1 → ("/f")
# Always initializes the array (never unset) so "${MON_FLAGS[@]-}" expands
# cleanly under set -u.
build_mon_flags() {
  local count="$1" ids="$2"
  MON_FLAGS=()
  if [ "$count" -gt 1 ]; then
    MON_FLAGS=("/multimon" "/monitors:$ids")
  else
    # shellcheck disable=SC2034  # MON_FLAGS consumed by engine/rdp-connect (sourced lib pattern)
    MON_FLAGS=("/f")
  fi
}
