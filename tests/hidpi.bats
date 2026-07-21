# tests/hidpi.bats — bats migration of tests/hidpi-probe.sh (S1–S8)
#
# Spec provenance: openspec/specs/hidpi-scaling/spec.md (5 spec scenarios
# S1–S5) + 3 robustness cases from hidpi-probe.sh (S6 malformed JSON, S7 empty
# monitors array, S8 scale field missing). 8 @test blocks, one per probe case.
#
# Per design.md Decision: migration_pattern — mechanical 1:1 translation.
# Per design.md Decision: ci_xfreerdp3_strategy — every test is lib-boundary
# (sources lib/rdp-common.bash, exercises compute_dpi_flags with a mocked
# hyprctl). NO real hyprctl invocation. NO xfreerdp3.
#
# Mock strategy: each @test exports a function named `hyprctl` in the bats
# shell before calling compute_dpi_flags. The lib calls `hyprctl monitors -j`
# via command substitution, so the function shadows the real binary on PATH
# (bash function lookup precedes PATH lookup). A `log_event` stub captures
# WARN lines so fallback cases can assert on the diagnostic.

load test_helper

# ----------------------------------------------------------------------------
# Per-test setup: clear state, install fresh stubs. compute_dpi_flags sets
# DPI_FLAGS (array), IS_HIDPI, SCALE_PCT globals. The WARN-line capture array
# is per-test (declared local in each @test body to avoid cross-test leakage).
# ----------------------------------------------------------------------------
setup() {
  unset IS_HIDPI SCALE_PCT DPI_FLAGS
}

# _run_dpi_case <json> <stub_log_array_name>
# Exports `hyprctl` to emit $1, exports `log_event` to append WARN lines to the
# array named by $2, then calls compute_dpi_flags. The caller MUST declare the
# array (typically `local -a warn_lines=()`) BEFORE calling this helper.
_run_dpi_case() {
  local json="$1"
  # shellcheck disable=SC2154  # warn_lines is declared by the caller
  hyprctl() { printf '%s' "$json"; }
  # shellcheck disable=SC2329  # invoked indirectly by compute_dpi_flags in sourced lib
  # IMPORTANT: must return 0 unconditionally. compute_dpi_flags calls
  # log_event for INFO lines too; bats treats any non-zero return inside an
  # @test body as failure. The `&&` short-circuit form `[[ WARN ]] && arr+=`
  # returns 1 on a non-WARN line; the `if` form returns 0 either way.
  log_event() {
    local level="$1" msg="$2"
    if [[ "$level" == "WARN" ]]; then
      warn_lines+=("$msg")
    fi
  }
  compute_dpi_flags
}

# ============================================================================
# S1 (spec): scale 2.0 → HiDPI, 200%, /scale-desktop:200 /smart-sizing
# ============================================================================
@test "S1: scale=2.0 -> HiDPI flags (/scale-desktop:200 /smart-sizing)" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"scale":2.0}]'
  [ "$IS_HIDPI" = "1" ]
  [ "$SCALE_PCT" = "200" ]
  [ "${DPI_FLAGS[*]}" = "/scale-desktop:200 /smart-sizing" ]
  [ "${#warn_lines[@]}" = "0" ]
}

# ============================================================================
# S2 (spec): scale 1.5 → fractional, rounds to 150
# ============================================================================
@test "S2: scale=1.5 -> fractional 150 (/scale-desktop:150 /smart-sizing)" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"scale":1.5}]'
  [ "$IS_HIDPI" = "1" ]
  [ "$SCALE_PCT" = "150" ]
  [ "${DPI_FLAGS[*]}" = "/scale-desktop:150 /smart-sizing" ]
  [ "${#warn_lines[@]}" = "0" ]
}

# ============================================================================
# S3 (spec): scale 1.0 → no DPI flags (not HiDPI)
# ============================================================================
@test "S3: scale=1.0 -> empty flags (IS_HIDPI=0 SCALE_PCT=100)" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"scale":1.0}]'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" = "0" ]
}

# ============================================================================
# S4 (spec): scale null → WARN fallback, empty DPI_FLAGS
# ============================================================================
@test "S4: scale=null -> WARN fallback + empty flags" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"scale":null}]'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" -ge 1 ]
}

# ============================================================================
# S5 (spec): non-numeric scale "auto" → WARN fallback
# ============================================================================
@test "S5: scale=auto -> WARN fallback + empty flags" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"scale":"auto"}]'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" -ge 1 ]
}

# ============================================================================
# S6 (robustness): malformed JSON → WARN fallback
# ============================================================================
@test "S6: malformed JSON -> WARN fallback + empty flags" {
  local -a warn_lines=()
  _run_dpi_case 'this-is-not-json'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" -ge 1 ]
}

# ============================================================================
# S7 (robustness): empty monitors array (no .[0]) → WARN fallback
# ============================================================================
@test "S7: empty monitors [] -> WARN fallback + empty flags" {
  local -a warn_lines=()
  _run_dpi_case '[]'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" -ge 1 ]
}

# ============================================================================
# S8 (robustness): scale field missing entirely → WARN fallback
# ============================================================================
@test "S8: scale missing -> WARN fallback + empty flags" {
  local -a warn_lines=()
  _run_dpi_case '[{"id":0,"name":"DP-1"}]'
  [ "$IS_HIDPI" = "0" ]
  [ "$SCALE_PCT" = "100" ]
  [ "${DPI_FLAGS[*]:-}" = "" ]
  [ "${#warn_lines[@]}" -ge 1 ]
}
