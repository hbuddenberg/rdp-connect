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
#
# `declare -gA` (global associative array) instead of `declare -A`: when this
# file is sourced at top level (engine L45) the two forms are equivalent.
# When sourced inside a function context (bats `load` chains: every tests/*.bats
# `load test_helper` -> test_helper.bash `source "$LIB_FILE"` happens inside a
# bats-injected function frame), plain `declare -A` would scope the array
# LOCALLY to that frame and the allowlist would be empty by the time @test
# bodies run. `-g` forces global scope regardless of the source depth.
declare -gA _PROFILE_KEYS=(
  [HOST]=1
  [USER_RDP]=1
  [PASS_RDP]=1
  [DOMAIN]=1
  [VPN_CHECK]=1
  [PREFERRED_WS]=1
  [LANG_OVERRIDE]=1
  [AUDIO_REDIRECT]=1
  [MONITOR_MODE]=1
  [MONITOR_ID]=1
  [MONITORS]=1
  [MONITOR_ORDER]=1
  [DYNAMIC_RESOLUTION]=1
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
#   double-quote  → strip outer quotes; interior '#' preserved verbatim;
#                   tolerate trailing whitespace + optional `# comment` after
#                   the closing quote (T2.4: also tolerates CRLF line endings).
#   single-quote  → same as double-quote.
#   unquoted      → strip trailing ' # comment' (whitespace-then-#), trim ws.
#
# CRLF tolerance (T2.4): a trailing `\r` left by Windows-style `\r\n` line
# endings is stripped at the top of the loop, BEFORE any value inspection.
# Without this, `VPN_CHECK=""\r` was misreported as "unterminated quote".
#
# Augmentation beyond design.md (per task T1.2 prompt): an unquoted value
# containing '#' WITHOUT preceding whitespace (e.g. `KEY=value# x`) is
# rejected — it is ambiguous (typo'ed comment delimiter or leaky quote) and
# silently truncating it to `value#` would corrupt the data. Forces the user
# to be explicit. See apply-progress T1.2 deviations note.
#
# T2.4 diagnostic improvement: unterminated quotes and unexpected trailing
# content both include a 40-char sanitized preview of the offending raw value
# so users can see invisible whitespace / CRLF / stray characters.
parse_env_safe() {
  local file="$1" mode="${2:-profile}" line key raw value lineno=0 q rest closing_part tail
  # shellcheck disable=SC2094  # _reject writes stderr only; $file is read-only input
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    # T2.4: strip a trailing CR left by CRLF line endings (Windows-edited or
    # clipboard-mangled profiles). `read -r` on Linux splits on LF only, so a
    # CRLF file leaves a literal \r at the end of `line`. Without this strip,
    # `VPN_CHECK=""\r` failed the old "raw ends with quote" check and was
    # misreported as "unterminated quote".
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"              # trim leading whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue       # blank / full-line comment
    [[ "$line" != *=* ]] && { _reject "$file" "$lineno" "no '=' delimiter"; return 1; }
    key="${line%%=*}"; raw="${line#*=}"                  # split on FIRST '=' → preserves '=' in passwords
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _reject "$file" "$lineno" "invalid key '$key'"; return 1; }
    # allowlist BEFORE any assignment (spec: "no printf -v on unknown keys")
    # NOTE: `-v` (is-set) test, NOT `${arr[$k]}` — under `set -u` a missing assoc
    # key raises "unbound variable" before `[[ -n ]]` can return false. Verified
    # in design and re-verified by tests/parser-probe.sh (runs under `set -u`).
    case "$mode" in
      profile) [[ -v _PROFILE_KEYS[$key] || "$key" =~ ^MONITOR_[0-9]+$ ]] || { _reject "$file" "$lineno" "rejected key '$key'"; return 1; } ;;
      i18n)    [[ "$key" == MSG_* ]]         || { _reject "$file" "$lineno" "rejected i18n key '$key'"; return 1; } ;;
      *)        _reject "$file" "$lineno" "unknown mode '$mode'"; return 1 ;;
    esac
    # value normalization by leading char
    if   [[ "$raw" == \"* ]]; then q=\"                  # double-quoted
    elif [[ "$raw" == \'* ]]; then q=\'                  # single-quoted
    else q=                                              # unquoted
    fi
    if [[ -n "$q" ]]; then
      # T2.4: quoted-value handling. The OLD logic required `raw` to END with
      # the quote char, which misrejected legitimately-terminated values that
      # had trailing whitespace, a CRLF, or an inline `# comment` after the
      # closing quote — all reported as the misleading "unterminated quote".
      #
      # New approach: find the FIRST closing quote (so a '#' inside the quoted
      # value like PASS_RDP="p# x" is preserved verbatim), then validate that
      # whatever FOLLOWS the closing quote is empty, whitespace-only, or
      # whitespace + `# comment`. Anything else is rejected with a clearer
      # message naming the offending tail.
      rest="${raw:1}"                                    # raw minus the leading quote
      closing_part="${rest%%"$q"*}"                      # text before the first closing quote
      if [[ "$closing_part" == "$rest" ]]; then
        # No closing quote anywhere on the line → genuinely unterminated.
        # Include a 40-char sanitized preview of the raw value so the user can
        # SEE what's wrong (invisible whitespace / CRLF is otherwise hidden).
        _reject "$file" "$lineno" "unterminated quote (raw: '${raw:0:40}')"
        return 1
      fi
      value="$closing_part"
      tail="${rest#*"$q"}"                               # what follows the first closing quote
      # tail MUST be empty, whitespace-only, or whitespace + `# comment`.
      if [[ -n "$tail" && ! "$tail" =~ ^[[:space:]]*(#.*)?$ ]]; then
        _reject "$file" "$lineno" "unexpected content after closing quote: '${tail:0:40}'"
        return 1
      fi
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
# T2.1 — Post-parse whitespace trim for network-identifier fields
# ---------------------------------------------------------------------------
# trim_profile_fields
#
# Mutates the 5 network-identifier fields IN PLACE via printf -v: HOST,
# VPN_CHECK, DOMAIN, PREFERRED_WS, LANG_OVERRIDE. Uses the parameter-expansion
# trim idiom (no subshell, no set -e trap). NEVER touches PASS_RDP or
# USER_RDP — credentials MAY legally contain surrounding whitespace; the
# allowlist (5 trimmed, 2 excluded) is enforced by the loop list, NOT by
# conditional logic, so an accidental widening is impossible without editing
# this function (security-critical invariant — see engine-security spec).
#
# Caller contract: the 5 globals MUST already be set (by parse_env_safe or
# pre-init). The function does NOT take arguments and returns nothing.
#
# Extraction provenance: verbatim lift of engine/rdp-connect L178-186 (the
# `for _field in HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE` block).
# Parity is reverified by tests/vpn-trim.bats::trim_profile_fields_byte_identical_on_fixtures
# and by tests/engine-security.bats::trim_allowlist_is_five_trimmed_two_excluded.
trim_profile_fields() {
  local _field _val
  for _field in HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE; do
    # shellcheck disable=SC2229  # dynamic var name; values come from parse_env_safe allowlist
    _val="${!_field}"
    _val="${_val#"${_val%%[![:space:]]*}"}"   # strip leading whitespace
    _val="${_val%"${_val##*[![:space:]]}"}"   # strip trailing whitespace
    # shellcheck disable=SC2229  # see above
    printf -v "$_field" '%s' "$_val"          # indirect write to global
  done
}

# ---------------------------------------------------------------------------
# T3.1 — Per-session error extractor (lifted from engine cleanup() trap)
# ---------------------------------------------------------------------------
# extract_session_error <log_file> <pid>
#
# Outputs the LAST line written by <pid>'s session that matches
# /error|failed|status|connect/ (case-insensitive), scanning FORWARD from
# <pid>'s SESSION_START marker. Empty output if no marker exists for <pid>
# (legacy log), no matching line exists in this session, or <log_file> is
# missing/unreadable. PID matching is prefix-safe: pid=222 does NOT match a
# marker for pid=2222 (the `([^0-9]|$)` anchor demands a non-digit or EOL
# immediately after the pid digits).
#
# Pure text transformation over a file — NO external state, NO side effects,
# NO notify-send, NO exit. Safe to unit-test directly.
#
# Caller contract (engine cleanup trap):
#   LAST_ERROR="$(extract_session_error "$LOG_FILE" "$$")"
# The caller is responsible for the empty-output fallback message; this fn
# just returns the matched line (or empty).
#
# Extraction provenance: verbatim lift of engine/rdp-connect cleanup() awk
# extractor (engine L249-253 pre-T3.1). The file-existence guard moved INTO
# this fn; the engine's old `[ -n "${START_TIME:-}" ]` defensive guard is
# dropped at the call site (the EXIT trap registers AFTER START_TIME is
# assigned at engine L192, so the guard is statically true at every cleanup
# invocation). Parity is reverified by
# tests/cleanup-session.bats::extract_session_error_byte_identical_on_fixtures
# and the 4 fixture-driven @test blocks in that file.
#
# No associative arrays are declared here — the T2.5 `declare -gA` fix does
# NOT apply (only `local` scalars). Sourcing this fn from both top-level
# (engine) and function-context (bats `load` chain) is safe by construction.
extract_session_error() {
  local log_file="$1" pid="$2"
  [[ -f "$log_file" ]] || return 0
  # shellcheck disable=SC2012  # awk is the canonical line-scan here; $(<file) does not stream
  awk -v pid="$pid" '
    $0 ~ /\[SESSION_START\]/ && $0 ~ "pid="pid"([^0-9]|$)" { found=1; next }
    found && tolower($0) ~ /error|failed|status|connect/ { last=$0 }
    END { if (last) print last }
  ' "$log_file" 2>/dev/null || true
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

# ---------------------------------------------------------------------------
# log_event — timestamped log line + optional stderr tee (verbose mode)
# ---------------------------------------------------------------------------
# log_event <level> <message>
#
# Appends "[YYYY-MM-DD HH:MM:SS] [LEVEL] message" to LOG_FILE (caller-set
# global). When VERBOSE=1 (set by the engine's -v/--verbose flag), ALSO writes
# the same line to stderr so the user gets real-time terminal feedback instead
# of a silent run that only surfaces the opaque `setsid: child did not exit
# normally` message on failure.
#
# Reads globals at CALL time (LOG_FILE, VERBOSE): the engine sources the lib
# early (L67) and assigns LOG_FILE/VERBOSE later, so the function resolves them
# when invoked, not when defined — standard sourced-lib pattern.
#
# Extraction provenance: lifted from engine/rdp-connect (the 3-line log_event)
# with the verbose tee added. Same Extract-Before-Mock pattern as
# trim_profile_fields / extract_session_error: pure logic over globals → lib →
# unit-testable. See tests/verbose-mode.bats for the behavioral coverage.
log_event() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2"
  printf '%s\n' "$line" >> "${LOG_FILE:-/dev/null}"
  # if/then/fi (not `[ ] && printf`): the function MUST return 0 regardless of
  # VERBOSE — a non-zero return here would, under the engine's `set -e`, abort
  # on the very first log_event call. Caught by tests/verbose-mode.bats.
  if [ "${VERBOSE:-0}" = "1" ]; then
    printf '%s\n' "$line" >&2
  fi
}
