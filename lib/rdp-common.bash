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
  [CLIENT]=1
  [USB_REDIRECT]=1
  [USB_DEVICE_IDS]=1
  [DRIVE_REDIRECT]=1
  [SHARE_DIR]=1
  [CLIPBOARD_SYNC]=1
  [WEBCAM_REDIRECT]=1
  [DISABLE_DPI]=1
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
#   DPI_FLAGS   — bash array, empty under 100%, else (/scale-desktop:N)
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
  
  # Respect DISABLE_DPI profile option
  if [[ "${DISABLE_DPI:-0}" == "1" ]]; then
    log_event "INFO" "DPI scaling disabled by profile (DISABLE_DPI=1)"
    return 0
  fi
  
  out=$(get_dpi_scale | jq -r '
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
    DPI_FLAGS=("/scale-desktop:${SCALE_PCT}")
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
# Peripheral flag builders (usb-redirect-clipboard-windowrules change)
# ---------------------------------------------------------------------------
# build_usb_flags / build_drive_flags / build_clipboard_flags — pure fns that
# read profile globals (set by parse_env_safe) and set a FLAGS array each.
# Mirror the build_mon_flags / compute_dpi_flags pattern: no args, read
# globals at call time, set a global array. Arrays are ALWAYS initialized
# (never unset) so "${ARR[@]}" expands cleanly under set -u without the
# phantom-empty-arg gotcha ("${ARR[@]-}" yields a single '' token).
#
# Capability gate globals (_HAS_USB / _HAS_DRIVE / _HAS_CLIPBOARD) are set
# by the engine's xfreerdp3 /help probes; the fns read them via ${var:-0}
# so unit tests can set them directly without the engine present.

# build_usb_flags — USB_REDIRECT=1 + USB_DEVICE_IDS=vid:pid[#vid:pid]
#   OFF (default)            → USB_FLAGS=()
#   ON + valid ids           → USB_FLAGS=("/usb:id:<vid:pid>#...")
#   ON + invalid ids         → return 1 (loud reject, never reaches xfreerdp3)
#   ON + build without /usb: → USB_FLAGS=() + log WARN (silent-skip)
build_usb_flags() {
  USB_FLAGS=()
  [ "${USB_REDIRECT:-0}" = "1" ] || return 0
  if [ "${_HAS_USB:-0}" != "1" ]; then
    log_event "WARN" "USB redirect requested but xfreerdp3 lacks /usb: (omitted)"
    return 0
  fi
  local val="${USB_DEVICE_IDS:-}"
  if [ -z "$val" ]; then
    log_event "WARN" "USB redirect requested but USB_DEVICE_IDS not set (omitted)"
    return 0
  fi
  if ! [[ "$val" =~ ^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})(#([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}))*$ ]]; then
    log_event "ERROR" "USB_DEVICE_IDS invalid: '$val' (expected vid:pid[#vid:pid])"
    return 1
  fi
  # shellcheck disable=SC2034  # USB_FLAGS consumed by engine/rdp-connect (sourced lib pattern)
  USB_FLAGS=("/usb:id:$val")
}

# build_drive_flags — DRIVE_REDIRECT (default 1), SHARE_DIR (default $HOME/Compartido)
#   ON  (default) → DRIVE_FLAGS=("/drive:compartido,<SHARE_DIR>")
#   OFF           → DRIVE_FLAGS=()
build_drive_flags() {
  DRIVE_FLAGS=()
  [ "${DRIVE_REDIRECT:-1}" = "1" ] || return 0
  # shellcheck disable=SC2034  # DRIVE_FLAGS consumed by engine/rdp-connect (sourced lib pattern)
  DRIVE_FLAGS=("/drive:compartido,${SHARE_DIR:-$HOME/Compartido}")
}

# build_webcam_flags — WEBCAM_REDIRECT=1
#   OFF (default)            → WEBCAM_FLAGS=()
#   ON + detected camera     → WEBCAM_FLAGS=("/usb:id:<vid:pid>")
#   ON + no camera found     → WEBCAM_FLAGS=() + log WARN
#   ON + build without /usb: → WEBCAM_FLAGS=() + log WARN
build_webcam_flags() {
  WEBCAM_FLAGS=()
  [ "${WEBCAM_REDIRECT:-0}" = "1" ] || return 0
  if [ "${_HAS_USB:-0}" != "1" ]; then
    log_event "WARN" "Webcam redirect requested but xfreerdp3 lacks /usb: (omitted)"
    return 0
  fi
  # Auto-detect camera via lsusb (look for common webcam vendors)
  local camera_id=""
  if command -v lsusb &>/dev/null; then
    # Try to find known webcam vendors: EMEET, Logitech, Microsoft, etc.
    camera_id=$(lsusb 2>/dev/null | grep -iE "emeet|logitech|microsoft.*camera|webcam|video" | head -1 | awk '{print $6}')
    if [ -n "$camera_id" ]; then
      # shellcheck disable=SC2034  # WEBCAM_FLAGS consumed by engine/rdp-connect
      WEBCAM_FLAGS=("/usb:id:$camera_id")
      log_event "INFO" "Webcam detected: $camera_id"
    else
      log_event "WARN" "Webcam redirect requested but no camera detected (omitted)"
    fi
  else
    log_event "WARN" "Webcam redirect requested but lsusb not available (omitted)"
  fi
}

# build_clipboard_flags — CLIPBOARD_SYNC (default 1)
#   ON  → CLIPBOARD_FLAGS=("+clipboard")
#   OFF → CLIPBOARD_FLAGS=()
build_clipboard_flags() {
  CLIPBOARD_FLAGS=()
  [ "${CLIPBOARD_SYNC:-1}" = "1" ] || return 0
  # shellcheck disable=SC2034  # CLIPBOARD_FLAGS consumed by engine/rdp-connect (sourced lib pattern)
  CLIPBOARD_FLAGS=("+clipboard")
}

# ---------------------------------------------------------------------------
# F9 — resolve_monitor_order: MONITOR_ORDER by numeric id OR description
# ---------------------------------------------------------------------------
# resolve_monitor_order <monitors_json> <selector>
#
# <selector> is a comma-separated list of tokens, same shape as
# MONITOR_ORDER/--monitor-order. Each token is EITHER a numeric hyprctl id
# (passed through unchanged) OR a case-insensitive substring matched against
# each monitor's `.description` (e.g. "Dell Inc. DELL U2417H XVNNT6BTAPBL") —
# port names/ids renumber across a reboot or replug (confirmed on real
# hardware: the same 3 monitors enumerated as DP-4/DP-9/DP-8 one session and
# DP-3/DP-5/DP-6 the next), description does not.
#
# Prints the resolved comma-separated id list on stdout, preserving the
# selector's original token order. Returns 1 (diagnostic on stderr, no
# stdout) if any description token matches zero or more than one monitor —
# an ambiguous/missing selector must hard-fail, not silently drop a monitor
# out of the canvas or resolve to the wrong physical output.
resolve_monitor_order() {
  local mon_json="$1" selector="$2"
  local -a tokens=() resolved=()
  local tok id_matches count
  IFS=',' read -ra tokens <<< "$selector"
  for tok in "${tokens[@]}"; do
    tok="${tok#"${tok%%[![:space:]]*}"}"   # trim leading whitespace
    tok="${tok%"${tok##*[![:space:]]}"}"   # trim trailing whitespace
    [ -z "$tok" ] && continue
    if [[ "$tok" =~ ^[0-9]+$ ]]; then
      resolved+=("$tok")
      continue
    fi
    id_matches=$(printf '%s' "$mon_json" | jq -r --arg q "$tok" \
      '[.[] | select((.description // "") != "" and ((.description | ascii_downcase) | contains($q | ascii_downcase)))] | .[].id' 2>/dev/null)
    count=$(printf '%s' "$id_matches" | grep -c . || true)
    if [ "$count" -ne 1 ]; then
      printf 'resolve_monitor_order: "%s" matched %d monitor(s) via description (need exactly 1)\n' "$tok" "$count" >&2
      return 1
    fi
    resolved+=("$id_matches")
  done
  ( IFS=,; printf '%s\n' "${resolved[*]}" )
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

# ---------------------------------------------------------------------------
# setup_colors — ANSI color globals for the colored --help (rich-like)
# ---------------------------------------------------------------------------
# Populates C_* globals. Colorize ONLY when:
#   - NO_COLOR is unset (respects https://no-color.org), AND
#   - stdout is a TTY, OR RDP_FORCE_COLOR=1 (lets tests/force force it).
# When disabled, every C_* is empty so callers can interpolate unconditionally
# ($C_TITLE text $C_R) and the output is plain. Pure logic over globals ->
# unit-testable (tests/ui-helpers.bats).
setup_colors() {
  if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ "${RDP_FORCE_COLOR:-0}" = "1" ]; }; then
    # shellcheck disable=SC2034  # C_* consumed by engine/rdp-connect (sourced-lib pattern)
    C_TITLE=$'\033[1;36m'   # bold cyan   — section titles
    C_CMD=$'\033[1;32m'     # bold green  — the rdp-connect command
    C_FLAG=$'\033[1;33m'    # bold yellow — CLI flags
    C_KEY=$'\033[1;35m'     # bold magenta— profile keys
    C_DIM=$'\033[2m'        # dim         — descriptions/paths
    C_BOLD=$'\033[1m'
    C_R=$'\033[0m'          # reset
  else
    # shellcheck disable=SC2034  # see above
    C_TITLE="" C_CMD="" C_FLAG="" C_KEY="" C_DIM="" C_BOLD="" C_R=""
  fi
}

# ---------------------------------------------------------------------------
# Profile migrator helpers (used by `rdp-connect --update-profiles`)
# ---------------------------------------------------------------------------
# Idempotently append a documented block listing EVERY tunable key (audio +
# monitor mode + monitor layout) to a profile, so profiles created before these
# features learn the full set as commented options. Never overwrites real
# values — keys are commented out, the user uncomments what they want.
PROFILE_TUNABLES_MARKER='# --- rdp-connect tunables'

profile_has_tunables_block() {
  [ -f "$1" ] || return 1
  grep -qF "$PROFILE_TUNABLES_MARKER" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# set_profile_key — idempotent single-key rewrite for a profile .env
# ---------------------------------------------------------------------------
# set_profile_key <file> <key> <value>
#
# Rewrites the first line whose TRIMMED start is exactly "<key>=" to
# `key="value"`, preserving every other line byte-for-byte (including
# commented-out example lines like `# MONITOR_ORDER=1,3,2` in the tunables
# block — the "<key>=" match requires the trimmed line to start with the key
# itself, so a leading `#` never matches). Appends `key="value"` at EOF if no
# such line exists. Returns 1 if <file> does not exist.
#
# Used by the engine's pre-connect checkbox menu to persist the user's
# monitor/audio selection so the NEXT launch pre-checks the same state
# ("recordar el ultimo estado"). Deliberately NOT built on parse_env_safe —
# this is a raw line rewrite, not a value read; it never sources/evals the
# file either way. Values are wrapped in double quotes verbatim: callers pass
# only the fixed, script-generated values this engine writes back
# (MONITOR_MODE/MONITOR_ORDER/MONITOR_ID/AUDIO_REDIRECT) — never raw user
# free text — so no quote-escaping is implemented.
set_profile_key() {
  local file="$1" key="$2" value="$3"
  [ -f "$file" ] || return 1
  local tmp found=0 line trimmed
  tmp="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [ "$found" -eq 0 ] && [[ "$trimmed" == "${key}="* ]]; then
      printf '%s="%s"\n' "$key" "$value" >> "$tmp"
      found=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$file"
  [ "$found" -eq 0 ] && printf '%s="%s"\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

append_tunables_block() {
  # Returns 0 whether the block was already present or just added, so the caller
  # treats any non-failure as success. Non-zero only on missing file.
  [ -f "$1" ] || return 1
  profile_has_tunables_block "$1" && return 0
  cat >> "$1" <<'EOF_TUNABLES_BLOCK'

# --- rdp-connect tunables (added by `rdp-connect --update-profiles`; all optional) ---
# Precedence: CLI flag > these > computed default. Uncomment & set what you need.
# MONITOR_<id> is 0-based (matches `hyprctl monitors` ids); per-monitor resolution
# is only honored in single mode (FreeRDP /multimon uses native res per monitor).
# AUDIO_REDIRECT=1            # 1=redirect audio to client (default); 0=play on remote
# MONITOR_MODE=multi          # multi (default) | single
# MONITOR_ID=0                # single: which monitor (0-based hyprctl id)
# MONITORS=3                  # multi: use first N detected monitors
# MONITOR_ORDER=1,3,2         # multi/span/expand: IDs in this order (-> /monitors:).
#                             # Tokens may also be a description substring
#                             # (hyprctl monitors -j .description, e.g. "ASUS" or
#                             # a serial to disambiguate identical models) —
#                             # survives port/id renumbering across reboots,
#                             # unlike numeric IDs. Mix freely: "ASUS,0".
# MONITOR_0=1920x1080         # single: resolution for monitor id 0
# MONITOR_1=1920x1080
# MONITOR_2=2560x1440
# DYNAMIC_RESOLUTION=1        # single: windowed, res follows window (Win8.1+ server)
# USB_REDIRECT=0              # 1=redirect USB device (opt-in); 0=off (default)
# USB_DEVICE_IDS=0781:5580    # vid:pid[#vid:pid] hex (required when USB_REDIRECT=1)
# DRIVE_REDIRECT=1            # 1=shared drive (default); 0=off
# SHARE_DIR=$HOME/Compartido  # local path shared to remote (default: $HOME/Compartido)
# CLIPBOARD_SYNC=1            # 1=clipboard sync (default); 0=off
EOF_TUNABLES_BLOCK
}

# ---------------------------------------------------------------------------
# Compositor backend layer — compositor-aware change (design D1–D6)
# ---------------------------------------------------------------------------
# One canonical monitor model + dispatch wrappers for hyprland / niri and a
# degraded `none` backend, so the engine can run under either compositor.
# Invariants (spec compositor-backends + engine-security):
#   - detection is PROBE-decided (env hints only ORDER candidates) and never
#     aborts the engine; every compositor query degrades with WARN;
#   - compositor-controlled strings enter jq ONLY via --arg; no eval;
#   - this layer NEVER interposes between the password pipe and the
#     xfreerdp3 argv (it is not part of the connection pipeline at all).

# detect_compositor (D4)
#
# Sets COMPOSITOR ∈ {hypr, niri, none} and caches the winning probe's JSON in
# _PROBE_JSON_HYPR / _PROBE_JSON_NIRI (consumed by the monitor adapters and
# get_dpi_scale — ≤1 IPC per query type per run).
#
# Candidates are hint-ORDERED but probe-DECIDED: exit code alone never
# decides, because BOTH CLIs answer rc=1 with plain text on the wrong
# compositor (live-probed). The probe is connectivity + JSON-validity:
#   timeout 2 hyprctl monitors -j | jq -e .
#   timeout 2 niri msg --json outputs  | jq -e .
# `timeout 2` bounds a hung socket; `jq -e .` rejects plain text; the rc is
# captured in an `if` (pipefail-safe, no `|| true` on the probe). A missing
# CLI is skipped via command -v.
#
# none → exactly ONE WARN naming the degraded mode, then return 0 — the
# engine continues (spec: detection MUST NOT abort). The message text comes
# from MSG_COMPOSITOR_NONE through the normal log_event pipeline (decision
# (b) in tasks.md: detection runs after load_language); the `:-` default
# only keeps `set -u` from aborting if i18n was never loaded.
detect_compositor() {
  local c _out='' _seen=''
  local -a _cands=() _ordered=()
  # env hints (ORDER only — never decide): strongest socket/signature hints
  # first, then the desktop-name hint, then both defaults.
  [ -n "${NIRI_SOCKET:-}" ] && _cands+=(niri)
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && _cands+=(hypr)
  case "${XDG_CURRENT_DESKTOP:-}" in
    *[Nn]iri*) _cands+=(niri) ;;
    *[Hh]ypr*) _cands+=(hypr) ;;
  esac
  _cands+=(hypr niri)
  for c in "${_cands[@]}"; do
    # dedupe, preserving hint order
    [[ ";${_seen};" == *";$c;"* ]] || { _ordered+=("$c"); _seen="${_seen};$c"; }
  done
  COMPOSITOR=none
  for c in "${_ordered[@]}"; do
    case "$c" in
      hypr)
        command -v hyprctl &>/dev/null || continue
        if _out=$(timeout 2 hyprctl monitors -j 2>/dev/null | jq -e . 2>/dev/null); then
          COMPOSITOR=hypr
          # shellcheck disable=SC2034  # probe cache read by _monitors_hypr / get_dpi_scale
          _PROBE_JSON_HYPR="$_out"
          return 0
        fi
        ;;
      niri)
        command -v niri &>/dev/null || continue
        if _out=$(timeout 2 niri msg --json outputs 2>/dev/null | jq -e . 2>/dev/null); then
          # shellcheck disable=SC2034  # COMPOSITOR is the engine/test-facing contract var
          COMPOSITOR=niri
          # shellcheck disable=SC2034  # probe cache read by _monitors_niri
          _PROBE_JSON_NIRI="$_out"
          return 0
        fi
        ;;
    esac
  done
  log_event "WARN" "${MSG_COMPOSITOR_NONE:-No compositor responded (Hyprland/Niri). Degraded mode: /f, DPI 100%, no workspace pinning or monitor menu.}"
  return 0
}

# _monitors_hypr — canonical model from hypr raw JSON (D2)
#
# Input: `hyprctl monitors -j` array (probe cache if warm, else a plain
# fetch — the plain form keeps pre-migration callers and function-mock unit
# tests byte-compatible with the legacy compute_dpi_flags source). Output:
# canonical array [{id,desc,x,y,w,h,scale,ws_ref}] in LOGICAL px.
#
# The physical→logical `/scale` division lives HERE AND ONLY HERE (spec
# compositor-backends::hypr-owns-/scale; guarded structurally by
# compositor-backends.bats::scale_conversion_only_in_hypr_adapter). x/y pass
# through unconverted — hypr reports logical origins already. `sort_by(.x)`
# is verbatim engine semantics (detection-order ids are NOT left-to-right;
# see engine comments). Malformed input → jq fails → `[]` (value fallback,
# the engine's established monitor-query degrade — never an abort).
_monitors_hypr() {
  local raw
  if [ -n "${_PROBE_JSON_HYPR:-}" ]; then
    raw="$_PROBE_JSON_HYPR"
  else
    raw=$(hyprctl monitors -j 2>/dev/null) || raw=''
  fi
  printf '%s' "$raw" | jq -c '
    [ .[]
      | { id:   .id,
          desc: .description,
          x:    .x,
          y:    .y,
          w:    (.width  / .scale | round),
          h:    (.height / .scale | round),
          scale: .scale,
          ws_ref: .activeWorkspace.id } ]
    | sort_by(.x)
  ' 2>/dev/null || printf '[]'
}

# _monitors_niri — canonical model from niri object-keyed outputs (D2)
#
# Input: `niri msg --json outputs` (object keyed by output NAME — probe cache
# if warm, else plain fetch) joined with `niri msg --json workspaces`.
# Output: canonical array in LOGICAL px — niri's logical.* is already logical
# and passes through UNCONVERTED (no /scale anywhere). Mapping per D2:
#   id   = output name (stable selection token, e.g. "DP-2")
#   desc = "make model serial" (identical models disambiguate by serial)
#   scale = logical.scale (effective) — NEVER top-level `scale`, which is the
#          *configured* scale and MAY be null (live-probed)
#   ws_ref = name of the output's active workspace
#          (.output==$key and (.is_active // .is_focused) — resolved decision
#          (a) in tasks.md; null-tolerant: no active ws → null, unmapped
#          workspaces (output:null) never match)
# Ordering: sort_by(logical.x, logical.y) — the documented deterministic
# order for niri's object-keyed shape.
_monitors_niri() {
  local out_raw ws_raw
  if [ -n "${_PROBE_JSON_NIRI:-}" ]; then
    out_raw="$_PROBE_JSON_NIRI"
  else
    out_raw=$(niri msg --json outputs 2>/dev/null) || out_raw=''
  fi
  ws_raw=$(niri msg --json workspaces 2>/dev/null) || ws_raw='[]'
  printf '%s' "$out_raw" | jq -c --arg ws "$ws_raw" '
    ($ws | fromjson) as $wsj
    | [ to_entries[]
        | . as $e
        | { id:   $e.key,
            desc: (($e.value.make   // "")
                 + " " + ($e.value.model  // "")
                 + " " + ($e.value.serial // "")),
            x: $e.value.logical.x,
            y: $e.value.logical.y,
            w: $e.value.logical.width,
            h: $e.value.logical.height,
            scale: $e.value.logical.scale,
            ws_ref: ( [ $wsj[]
                        | select(.output == $e.key
                                 and ((.is_active // .is_focused) // false)) ]
                      | .[0].name // null ) } ]
    | sort_by(.x, .y)
  ' 2>/dev/null || printf '[]'
}

# get_monitors_json (D1) — ONE canonical logical array, any backend
#
# Prints the canonical array and caches it in _CANON_MONITORS (lazy — D4:
# ≤1 IPC per query type per run). COMPOSITOR='' (unset) behaves as hypr so
# pre-migration engine callers and unit tests keep legacy byte-parity.
get_monitors_json() {
  if [ -n "${_CANON_MONITORS:-}" ]; then
    printf '%s' "$_CANON_MONITORS"
    return 0
  fi
  local canon=''
  case "${COMPOSITOR:-}" in
    niri)    canon=$(_monitors_niri) || canon='' ;;
    none)    canon='[]' ;;
    ''|hypr) canon=$(_monitors_hypr) || canon='' ;;
    *)       canon='[]' ;;
  esac
  # shellcheck disable=SC2034  # canonical cache read on every later call
  _CANON_MONITORS="${canon:-[]}"
  printf '%s' "$_CANON_MONITORS"
}

# get_dpi_scale (D5) — backend-internal DPI scale source
#
# Prints a monitors JSON ARRAY whose .[0].scale is the DPI scale, so the
# consumer jq program stays byte-identical across backends:
#   hypr (or unset — pre-migration legacy parity) → the RAW hyprctl monitors
#     array, probe cache if warm (detection ORDER .[0], exactly what the
#     engine read before this layer existed);
#   niri → the canonical array (leftmost = sort_by x,y; scale is the
#     effective logical.scale);
#   none → empty output (consumer lands in the existing 100% WARN path).
# The empty/failed fetch case propagates rc to the caller's `|| out=""`
# guard (compute_dpi_flags) — this fn adds no cosmetic guards of its own.
get_dpi_scale() {
  case "${COMPOSITOR:-}" in
    niri) get_monitors_json ;;
    none) printf '' ;;
    ''|hypr)
      if [ -n "${_PROBE_JSON_HYPR:-}" ]; then
        printf '%s' "$_PROBE_JSON_HYPR"
      else
        hyprctl monitors -j 2>/dev/null
      fi
      ;;
  esac
}

# compositor_find_window <class> (D6) — window-existence poll / token lookup
#
# hypr: byte-identical to the engine's poll (engine:1094) — `clients -j`
# piped through `jq -e any(.[]; .class==$c)`; rc decides, args travel via
# --arg, the whole call sits in the caller's poll `if` (no cosmetic guards).
# niri: looks the window up in `niri msg --json windows` by app_id and
# caches its numeric id in _WIN_TOKEN (the --window-id token the dispatch
# wrappers need). XWayland app_id↔/wm-class mapping is D8-gated (PR3).
# none: rc 1 (window can never appear — the engine's expand path already
# fails with its existing "no active session" message, D9).
compositor_find_window() {
  local class="$1" id
  case "${COMPOSITOR:-}" in
    niri)
      id=$(niri msg --json windows 2>/dev/null | jq -r --arg c "$class" \
        '[.[] | select(.app_id == $c) | .id][0] // empty' 2>/dev/null) || id=''
      if [ -n "$id" ]; then
        # shellcheck disable=SC2034  # token read by the niri dispatch wrappers
        _WIN_TOKEN="$id"
        return 0
      fi
      return 1
      ;;
    ''|hypr)
      hyprctl clients -j 2>/dev/null | jq -e --arg c "$class" 'any(.[]; .class==$c)' >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# _hypr_dispatch / _niri_dispatch — argv emission for compositor mutations
#
# `&>/dev/null || true` is the documented-cosmetic class (engine-robustness
# spec: hyprctl/niri DISPATCH calls only — a lost cosmetic dispatch must
# never abort the launch pipeline). The engine-robustness invariant holds:
# NO cosmetic guard is ever added around jq, file tests, or anything
# security-relevant — those live in the callers above.
_hypr_dispatch() {
  hyprctl "$@" &>/dev/null || true
}

_niri_dispatch() {
  niri "$@" &>/dev/null || true
}

# _dispatch_noop — COMPOSITOR=none behavior (D6/D9): one WARN through the
# normal MSG pipeline, zero IPC, rc 0.
_dispatch_noop() {
  log_event "WARN" "${MSG_DISPATCH_NOOP:-No compositor available: window operation skipped (degraded mode).}"
  return 0
}

# _niri_window_id — ensure _WIN_TOKEN is set (auto-lookup via WM_CLASS so
# wrappers stay callable without an explicit find-window poll first).
_niri_window_id() {
  if [ -z "${_WIN_TOKEN:-}" ]; then
    compositor_find_window "${WM_CLASS:-}" || return 1
  fi
  return 0
}

# --- Dispatch wrappers (D6) — window ref via WM_CLASS global + LOGICAL px ---
# hypr argv is byte-identical to today's engine forms (regression-locked by
# compositor-backends.bats::dispatch_golden_argv_hypr_forms); niri mappings
# per design D6 (`--window-id` flag — verified live, NOT `--id`; workspace
# moves also focus the target workspace). Resize/move positioning semantics
# under niri are gated on the D8 live verification (PR3).

dispatch_move_to_ws() {
  local ws="$1"
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action move-window-to-workspace "$ws" --window-id "$_WIN_TOKEN"
      _niri_dispatch msg action focus-workspace "$ws"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      _hypr_dispatch dispatch movetoworkspacesilent "${ws},class:${WM_CLASS:-}"
      ;;
  esac
  return 0
}

dispatch_focus() {
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action focus-window --id "$_WIN_TOKEN"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      _hypr_dispatch dispatch focuswindow "class:${WM_CLASS:-}"
      ;;
  esac
  return 0
}

dispatch_float() {
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action move-window-to-floating --id "$_WIN_TOKEN"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      _hypr_dispatch dispatch setfloating "class:${WM_CLASS:-}"
      ;;
  esac
  return 0
}

dispatch_fullscreen() {
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action fullscreen-window --id "$_WIN_TOKEN"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      # mode "0" = true edge-to-edge fullscreen; no window arg — acts on the
      # focused window, which is why dispatch_focus runs first (engine:1121).
      _hypr_dispatch dispatch fullscreen "0"
      ;;
  esac
  return 0
}

dispatch_resize() {
  local w="$1" h="$2"
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action set-window-width --id "$_WIN_TOKEN" "$w"
      _niri_dispatch msg action set-window-height --id "$_WIN_TOKEN" "$h"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      _hypr_dispatch dispatch resizewindowpixel "exact ${w} ${h},class:${WM_CLASS:-}"
      ;;
  esac
  return 0
}

dispatch_move() {
  local x="$1" y="$2"
  case "${COMPOSITOR:-}" in
    niri)
      _niri_window_id || { _dispatch_noop; return 0; }
      _niri_dispatch msg action move-floating-window --id "$_WIN_TOKEN" -x "$x" -y "$y"
      ;;
    none)
      _dispatch_noop
      ;;
    ''|hypr)
      _hypr_dispatch dispatch movewindowpixel "exact ${x} ${y},class:${WM_CLASS:-}"
      ;;
  esac
  return 0
}
