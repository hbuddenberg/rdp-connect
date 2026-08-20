#!/usr/bin/env bats
# tests/installer-backends.bats — compositor-aware change, task 2.7.
#
# Spec: openspec/changes/compositor-aware/specs/installer/spec.md
# (modified requirement "Declared dependency list with missing-dep install"):
#   - "Niri-only host satisfies the compositor dependency" → no hyprland
#     install attempt (@test niri_only_satisfies_compositor_dep)
#   - "Neither compositor CLI still installs with a warning" → deploy+
#     smoke+manifest complete, none-mode warning printed
#     (@test no_compositor_installs_with_warn)
#
# Strategy: PATH-shadowed fake BINARIES control what `command -v` sees
# (presence/absence of hyprctl / niri / the hard deps), and a PATH-shadowed
# `sudo` SPY records any package-manager invocation without running it.
# install_deps() is exercised in a child bash (set -euo pipefail, matching
# the installer's own mode) with the installer sourced via its main guard.
# pkg_for mappings are covered separately by installer-deps.bats.

load test_helper

# _fake_env <bin...> — write fake (exit-0) binaries for each name into a
# fresh FAKEBIN. The child bash runs with PATH=FAKEBIN EXCLUSIVELY (not
# prepended): this host HAS a real hyprctl, and a prepended PATH would let
# `command -v hyprctl` see it through the tail — the "absent" scenarios
# would pass vacuously. Absolute /bin/bash shebangs keep the fakes runnable
# with no other PATH entries.
_fake_env() {
  FAKEBIN="${BATS_TEST_TMPDIR}/fakebin"
  rm -rf "$FAKEBIN"
  mkdir -p "$FAKEBIN"
  local b
  for b in "$@"; do
    printf '#!/bin/bash\nexit 0\n' > "${FAKEBIN}/${b}"
    chmod +x "${FAKEBIN}/${b}"
  done
  # Minimal dirname fake: the installer resolves SCRIPT_DIR at SOURCE time
  # (`dirname -- "$BASH_SOURCE"`), and BATS hands it an absolute path —
  # ${1%/*} is exact for that case. The `--` guard mirrors dirname(1).
  printf '#!/bin/bash\n[ "$1" = "--" ] && shift\nprintf "%%s\\n" "${1%%/*}"\n' > "${FAKEBIN}/dirname"
  chmod +x "${FAKEBIN}/dirname"
}

# _sudo_spy — write a `sudo` fake that appends its argv to SPYLOG and
# exits 0 (the package manager itself never runs).
_sudo_spy() {
  SPYLOG="${BATS_TEST_TMPDIR}/spy.log"
  : > "$SPYLOG"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$SPYLOG" \
    > "${FAKEBIN}/sudo"
  chmod +x "${FAKEBIN}/sudo"
}

@test "niri_only_satisfies_compositor_dep" {
  # Spec: host with niri installed and hyprland absent → the compositor OR
  # is satisfied by niri; the installer must NOT attempt to install hyprland
  # (no sudo invocation carrying a compositor package at all).
  _fake_env xfreerdp3 jq flock notify-send wofi niri   # hyprctl deliberately ABSENT
  _sudo_spy
  run bash -c '
    set -euo pipefail
    export PATH="'"${FAKEBIN}"'"
    # shellcheck source=/dev/null
    source "'"$REPO_ROOT"'/install-rdp-framework.sh"
    install_deps pacman
  '
  [ "$status" -eq 0 ] || fail "install_deps failed on a niri-only host: $output"
  [ ! -s "$SPYLOG" ] || fail "package manager invoked on niri-only host: $(cat "$SPYLOG")"
  if [[ "$output" == *"hyprland"* ]]; then
    fail "hyprland install attempt on niri-only host: $output"
  fi
}

@test "no_compositor_installs_with_warn" {
  # Spec: neither hyprctl nor niri installed or installable (apt: hyprland
  # not in Debian main, niri not packaged) → the install still completes
  # (install_deps returns 0) AND a warning naming the degraded none mode is
  # printed. No package-manager invocation.
  _fake_env xfreerdp3 jq flock notify-send wofi   # hyprctl + niri ABSENT
  _sudo_spy
  run bash -c '
    set -euo pipefail
    export PATH="'"${FAKEBIN}"'"
    # shellcheck source=/dev/null
    source "'"$REPO_ROOT"'/install-rdp-framework.sh"
    install_deps apt
  '
  [ "$status" -eq 0 ] || fail "install_deps must complete (none-mode fallback), got rc=$status: $output"
  [[ "$output" == *"none mode"* ]] || fail "warning must name the degraded none mode: $output"
  [[ "$output" == *"WARNING"* ]] || fail "warning must be loud (WARNING): $output"
  [ ! -s "$SPYLOG" ] || fail "apt invoked where spec says warn-only: $(cat "$SPYLOG")"
}

@test "neither_compositor_on_pacman_installs_hyprland" {
  # Triangulation — the "or installable" arm: on pacman (hyprland packaged),
  # a host with NEITHER CLI gets hyprland installed via the normal missing
  # list (exactly one package-manager invocation).
  _fake_env xfreerdp3 jq flock notify-send wofi   # hyprctl + niri ABSENT
  _sudo_spy
  run bash -c '
    set -euo pipefail
    export PATH="'"${FAKEBIN}"'"
    # shellcheck source=/dev/null
    source "'"$REPO_ROOT"'/install-rdp-framework.sh"
    install_deps pacman
  '
  [ "$status" -eq 0 ] || fail "install_deps failed: $output"
  [ -s "$SPYLOG" ] || fail "expected a package-manager invocation installing a compositor"
  grep -q "hyprland" "$SPYLOG" || fail "expected hyprland in the install list: $(cat "$SPYLOG")"
  [ "$(grep -c '' "$SPYLOG")" = "1" ] || fail "expected exactly one invocation: $(cat "$SPYLOG")"
}
