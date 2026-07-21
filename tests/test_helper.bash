# shellcheck shell=bash
# tests/test_helper.bash — sourced by every tests/*.bats
#
# Spec: openspec/changes/strict-tdd-enable/specs/test-harness-delta.md
# Requirement: Shared test helper (tests/test_helper.bash)
#
# Provides:
#   - bats_require_minimum_version 1.5.0  (R1 mitigation — clear abort on bats
#     < 1.5.0; ubuntu-latest ships 1.5.0+ via apt, but distro skew is real)
#   - LIB_FILE path resolution + sourcing of lib/rdp-common.bash
#   - setup_test_home()                  (R4 isolation — no test touches real HOME)
#   - parse_env_safe_under_setu()        (F14 probe idiom — child bash with set -u)
#   - assert_probes_pass()               (shared fail-on-nonzero assertion alias)
#
# This file is SOURCED, not executed. bats injects $BATS_TEST_FILENAME,
# $BATS_TEST_DIRNAME, $BATS_TMPDIR, $BATS_RUN_TMPDIR at runtime before any
# @test body runs; the SC2154 disables below acknowledge those injections.

# R1 mitigation: fail loud and early on bats < 1.5.0 (released 2019-12-30).
# 1.5.0 is the floor for `bats_require_minimum_version` itself AND for the
# `run --keep-empty-lines` / improved TAP formatter the migrated .bats files
# rely on. Older bats (1.1.0 ships on some long-term distros) silently misparses
# multi-line `run` captures.
bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Load bats-support + bats-assert (provides assert_success, assert_output,
# assert_equal, assert_failure, assert_empty — used by assert_probes_pass
# below and by every .bats file in PR2). These are NOT part of bats-core
# proper; they ship as separate repos in the bats-core org and as separate
# apt/dnf packages.
#
# Search order (first match wins):
#   1. $BATS_LIB_PATH (colon-separated — bats-native search path)
#   2. /usr/lib/bats    (system install: apt install bats-assert bats-support)
#   3. ~/.local/lib/bats (user-local source install — README pattern)
#
# Bails with a clear install hint if not found, so `make test` failures point
# at the missing dep instead of cascading into "command not found" inside the
# first @test that calls an assert_*.
# ---------------------------------------------------------------------------
_load_bats_assert() {
  local -a _roots=()
  local _lib_path="${BATS_LIB_PATH:-}"
  if [ -n "${_lib_path}" ]; then
    # shellcheck disable=SC2206  # word-splitting is intentional here
    IFS=':' read -ra _parts <<< "${_lib_path}"
    _roots+=("${_parts[@]}")
  fi
  _roots+=(/usr/lib/bats "${HOME}/.local/lib/bats")
  local _root _support="" _assert=""
  for _root in "${_roots[@]}"; do
    if [ -f "${_root}/bats-support/load.bash" ] && [ -f "${_root}/bats-assert/load.bash" ]; then
      _support="${_root}/bats-support/load.bash"
      _assert="${_root}/bats-assert/load.bash"
      break
    fi
  done
  if [ -z "${_support}" ] || [ -z "${_assert}" ]; then
    {
      printf 'tests/test_helper.bash: bats-support/bats-assert not found.\n'
      printf 'Searched roots: %s\n' "${_roots[*]}"
      printf 'Install one of:\n'
      printf '  Debian/Ubuntu: sudo apt-get install -y bats-assert bats-support\n'
      printf '  Fedora:        sudo dnf install -y bats-assert bats-support\n'
      printf '  Source (any):  git clone https://github.com/bats-core/bats-support ~/.local/lib/bats/bats-support\n'
      printf '                 git clone https://github.com/bats-core/bats-assert  ~/.local/lib/bats/bats-assert\n'
      printf '  Or set BATS_LIB_PATH to a colon-separated list of roots.\n'
    } >&2
    exit 2
  fi
  # shellcheck disable=SC1090,SC1091  # paths resolved at runtime by _load_bats_assert
  load "${_support}"
  # shellcheck disable=SC1090,SC1091
  load "${_assert}"
}
_load_bats_assert

# Path resolution — robust to bats being invoked from any CWD.
# $BATS_TEST_FILENAME is the absolute path of the .bats file that sourced us;
# its dirname is always tests/, and the repo root is one level up.
TESTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
LIB_FILE="${REPO_ROOT}/lib/rdp-common.bash"

# Source the production pure-function library so every @test can call
# parse_env_safe, compute_pid_path, compute_dpi_flags directly. trim_profile_fields
# and extract_session_error land here in PR3 (T3.1) — the source statement stays.
# shellcheck source=../lib/rdp-common.bash
# shellcheck disable=SC1091
source "${LIB_FILE}"

# ---------------------------------------------------------------------------
# setup_test_home — R1 mitigation: no test touches real $HOME.
#
# Creates a per-test throwaway HOME under $BATS_TMPDIR, exports it, and prints
# the path for tests that want to reference it directly. Per-test isolation
# comes from bats giving each .bats file its own $BATS_TMPDIR; tests in the
# same file share a HOME (intentional — they're testing the same surface).
# Returns: prints the new HOME path.
# Side effect: mutates $HOME for the rest of the calling test's execution.
# ---------------------------------------------------------------------------
setup_test_home() {
  # shellcheck disable=SC2154  # bats injects BATS_TMPDIR before @test bodies run
  HOME="${BATS_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
  printf '%s' "${HOME}"
}

# ---------------------------------------------------------------------------
# parse_env_safe_under_setu <fixture_content> <mode>
#
# Writes fixture_content to a tmp file, spawns a CHILD bash under `set -u`,
# sources lib/rdp-common.bash, runs parse_env_safe, and prints
#   "<rc>\t<ok>"
# to stdout. The <ok> sentinel proves the child bash survived `set -u` past
# the parser call; if parse_env_safe had aborted on an unbound variable, the
# printf would never run and the child would exit non-zero with an unbound-
# variable diagnostic on stderr.
#
# Why a child bash instead of running parse_env_safe in-process under set -u?
# The F14 case (parser-probe F14, carried into parser.bats in PR2) verifies
# that a non-allowlisted key returns rc=1 *cleanly* — no "unbound variable"
# abort from the assoc-array membership test under set -u. bats @test blocks
# run in-process; an abort would tear down the whole bats run. The child-bash
# idiom contains the failure mode to a single `run` capture.
#
# Sets the standard bats $status, $output, $lines, $stderr for assertions:
#   - $status == 0  AND  $output == "<rc>\t<ok>"   → parse_env_safe returned cleanly
#   - $status != 0  AND  $output contains "unbound variable"  → R1 regression
#
# After the call: rc column is `${output%$'\t'*}`; value column not used by
# parse_env_safe (it doesn't return a value — parse_env_safe_under_setu
# exists to assert rc-only parity).
# ---------------------------------------------------------------------------
parse_env_safe_under_setu() {
  local fixture="$1" mode="${2:-profile}"
  local fixture_file
  fixture_file="$(mktemp)"
  printf '%b' "${fixture}" > "${fixture_file}"
  # `run --separate-stderr` (bats 1.5.0+) splits parse_env_safe's stderr
  # diagnostic ($stderr/$stderr_lines) from our rc-marker stdout
  # ($output/$lines). Without this, the _reject diagnostic on stderr would
  # mix into $output ahead of the "<rc>\t<ok>" line and break rc parsing.
  # This flag is one of the reasons bats_require_minimum_version 1.5.0 is set.
  # shellcheck disable=SC2154  # `run` is a bats builtin
  run --separate-stderr bash -c '
    set -u
    # shellcheck source=/dev/null  # path resolved at runtime via "$1"
    source "$1"
    parse_env_safe "$2" "$3"
    printf "%d\t%s\n" "$?" "<ok>"
  ' _ "${LIB_FILE}" "${fixture_file}" "${mode}"
  rm -f "${fixture_file}"
}

# ---------------------------------------------------------------------------
# assert_probes_pass — shared fail-on-nonzero assertion (spec test-harness-delta
# Requirement: Shared test helper). Thin alias to the standard bats idiom so
# the spec's naming is honored.
#
# NOTE (open question Q2 in design.md): the spec's name is identical in
# semantics to bats's built-in `assert_success`. PR1 ships it as a thin alias
# to satisfy the spec contract verbatim; it can be removed if the spec is
# amended to drop the redundant name.
# ---------------------------------------------------------------------------
assert_probes_pass() {
  # shellcheck disable=SC2154  # assert_success is a bats-assert builtin
  assert_success
}
