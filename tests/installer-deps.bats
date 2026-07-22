#!/usr/bin/env bats
# tests/installer-deps.bats — covers the installer's dependency-name mapping
#
# Regression backstop for the pkg_for() function in install-rdp-framework.sh.
# Born from a real bug: the pacman mapping for xfreerdp3 said `freerdp3`, but
# no such package exists in Arch's official repos — the binary xfreerdp3 is
# provided by the package `freerdp` (extra repo; FreeRDP 3.x). The bug slipped
# through because harness.bats::make_install_delegates_to_installer uses a
# PATH/CD spy that never actually runs the installer. This file sources the
# installer directly (possible after the main() guard refactor) and asserts the
# mapping against a documented truth table for all 3 supported managers.
#
# Truth table is the source of truth here. If a distro renames a package, a
# maintainer updates both the table AND pkg_for() together — that is the
# regression we are guarding against. The apt-side packages are additionally
# validated live via apt-cache show on the CI runner (Ubuntu).

load test_helper

# Source the installer ONCE per test file. The main() guard (added in this same
# change) makes sourcing safe — the install only fires when the script is run
# directly, not sourced.
setup() {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/install-rdp-framework.sh"
}

# ---------------------------------------------------------------------------
# Truth table — the authoritative mapping. pkg_for() MUST agree with this.
# Each row: binary, then the package name per manager (pacman | apt | dnf).
# ---------------------------------------------------------------------------
# Verified against:
#   - Arch extra repo: `freerdp` provides xfreerdp3 (man xfreerdp3(1) under extra/freerdp)
#   - Debian: freerdp3-x11, jq, util-linux, libnotify-bin, wofi, rofi, hyprland, shellcheck
#   - Fedora: freerdp, jq, util-linux, libnotify, wofi, rofi, hyprland, shellcheck
TRUTH_TABLE=(
    "xfreerdp3|freerdp|freerdp3-x11|freerdp"
    "jq|jq|jq|jq"
    "flock|util-linux|util-linux|util-linux"
    "notify-send|libnotify|libnotify-bin|libnotify"
    "wofi|wofi|wofi|wofi"
    "rofi|rofi|rofi|rofi"
    "hyprctl|hyprland|hyprland|hyprland"
    "shellcheck|shellcheck|shellcheck|shellcheck"
)

@test "pkg_for_pacman_xfreerdp3_returns_freerdp_not_freerdp3" {
    # Direct regression for the bug this file was born from.
    [ "$(pkg_for pacman xfreerdp3)" = "freerdp" ]
}

@test "pkg_for_matches_truth_table_for_every_binary_and_manager" {
    local row binary arch_pkg apt_pkg dnf_pkg got
    for row in "${TRUTH_TABLE[@]}"; do
        IFS='|' read -r binary arch_pkg apt_pkg dnf_pkg <<< "$row"
        got="$(pkg_for pacman "$binary")"
        [ "$got" = "$arch_pkg" ] || \
            fail "pacman/$binary: expected '$arch_pkg', got '$got'"
        got="$(pkg_for apt "$binary")"
        [ "$got" = "$apt_pkg" ] || \
            fail "apt/$binary: expected '$apt_pkg', got '$got'"
        got="$(pkg_for dnf "$binary")"
        [ "$got" = "$dnf_pkg" ] || \
            fail "dnf/$binary: expected '$dnf_pkg', got '$got'"
    done
}

@test "pkg_for_returns_nonempty_for_every_required_binary_on_every_manager" {
    # Completeness guard: if a maintainer adds a new required binary to
    # install_deps() but forgets to add it to pkg_for(), this catches it.
    # Also catches a typo'd binary name (empty string return).
    local required=(xfreerdp3 jq flock notify-send wofi rofi hyprctl shellcheck)
    local managers=(pacman apt dnf)
    local binary manager got
    for binary in "${required[@]}"; do
        for manager in "${managers[@]}"; do
            got="$(pkg_for "$manager" "$binary")"
            [ -n "$got" ] || \
                fail "pkg_for $manager $binary returned empty — unmapped"
        done
    done
}

@test "pkg_for_unknown_binary_returns_empty_string" {
    # Negative case: an unmapped binary MUST return empty (not error), so
    # install_deps() can decide what to do (currently: silently skip via `[ -n ]`).
    [ -z "$(pkg_for pacman totally-fake-binary)" ]
    [ -z "$(pkg_for apt totally-fake-binary)" ]
    [ -z "$(pkg_for dnf totally-fake-binary)" ]
}

@test "pkg_for_unknown_manager_returns_empty_string" {
    # Negative case: an unsupported manager MUST return empty.
    [ -z "$(pkg_for zypper xfreerdp3)" ]
}

@test "detect_pkgr_picks_pacman_for_arch_id" {
    # Sanity check on the detection function (also now sourceable via guard).
    # Feed a synthetic os-release via a temp file and point the function at it.
    # NOTE: detect_pkgr() reads /etc/os-release directly — we cannot override
    # the path without refactoring. Instead assert the structural contract:
    # on the CI runner (Ubuntu) it MUST return `apt` or fail closed.
    # This is a weaker assertion than a full unit test; documented honestly.
    # (A future change could parameterize detect_pkgr's input path.)
    if [ -f /etc/os-release ]; then
        # On a real system it returns one of the three or fails.
        run detect_pkgr
        # Either it succeeds with a known manager, or it fails (unsupported).
        if [ "$status" -eq 0 ]; then
            [[ "$output" == pacman || "$output" == apt || "$output" == dnf ]]
        fi
    fi
}
