#!/usr/bin/env bash
set -euo pipefail

# install-rdp-framework.sh — cross-distro deterministic installer for rdp-connect
#
# F10 (baseline-hardening T2.3): detects the host distro via /etc/os-release,
# installs missing dependencies via the right package manager, deploys engine /
# lib / i18n / template via idempotent `install -D`, runs a post-install smoke
# test (bash -n + shellcheck + --help + parser-probe), and writes a SHA-256
# checksum manifest for reproducibility.

# Resolve repo-relative source paths so the installer works from any CWD.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# F10 — Distro detection via /etc/os-release
# ---------------------------------------------------------------------------
# Returns one of: pacman | dnf | apt. Exits 1 (unsupported) if no match.
# Detection order per installer-delta spec: pacman → dnf → apt.
# Uses grep instead of sourcing to avoid set -u edge cases in os-release.
detect_pkgr() {
    [ -f /etc/os-release ] || return 1
    local id id_like tok
    id=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"' || true)
    id_like=$(grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"' || true)

    for tok in $id $id_like; do
        case "$tok" in
            arch|cachyos|garuda|endeavouros) echo pacman; return 0;;
        esac
    done
    for tok in $id $id_like; do
        case "$tok" in
            fedora|rhel|centos|rocky|alma) echo dnf; return 0;;
        esac
    done
    for tok in $id $id_like; do
        case "$tok" in
            debian|ubuntu|linuxmint|pop) echo apt; return 0;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------------------
# F10 — Dependency manifest (binary → package name per manager)
# ---------------------------------------------------------------------------
# Returns the package name for <binary> on <pkgr>. Empty string = not mapped.
pkg_for() {
    local pkgr="$1" binary="$2"
    case "$pkgr" in
        pacman)
            case "$binary" in
                xfreerdp3)   printf '%s' freerdp3 ;;
                jq)          printf '%s' jq ;;
                flock)       printf '%s' util-linux ;;
                notify-send) printf '%s' libnotify ;;
                wofi)        printf '%s' wofi ;;
                rofi)        printf '%s' rofi ;;
                hyprctl)     printf '%s' hyprland ;;
                shellcheck)  printf '%s' shellcheck ;;
            esac ;;
        apt)
            case "$binary" in
                xfreerdp3)   printf '%s' freerdp3-x11 ;;
                jq)          printf '%s' jq ;;
                flock)       printf '%s' util-linux ;;
                notify-send) printf '%s' libnotify-bin ;;
                wofi)        printf '%s' wofi ;;
                rofi)        printf '%s' rofi ;;
                hyprctl)     printf '%s' hyprland ;;
                shellcheck)  printf '%s' shellcheck ;;
            esac ;;
        dnf)
            case "$binary" in
                xfreerdp3)   printf '%s' freerdp ;;
                jq)          printf '%s' jq ;;
                flock)       printf '%s' util-linux ;;
                notify-send) printf '%s' libnotify ;;
                wofi)        printf '%s' wofi ;;
                rofi)        printf '%s' rofi ;;
                hyprctl)     printf '%s' hyprland ;;
                shellcheck)  printf '%s' shellcheck ;;
            esac ;;
    esac
}

# ---------------------------------------------------------------------------
# F10 — Install missing dependencies
# ---------------------------------------------------------------------------
install_deps() {
    local pkgr="$1" binary pkg
    local missing=()

    # Required binaries (hard deps)
    for binary in xfreerdp3 jq flock notify-send; do
        if ! command -v "$binary" &>/dev/null; then
            pkg=$(pkg_for "$pkgr" "$binary")
            [ -n "$pkg" ] && missing+=("$pkg")
        fi
    done

    # Launcher OR-check: wofi OR rofi satisfies the dependency.
    # If neither is present, install wofi by default.
    if ! command -v wofi &>/dev/null && ! command -v rofi &>/dev/null; then
        missing+=("$(pkg_for "$pkgr" wofi)")
    fi

    # hyprctl — hard requirement for the engine, but Debian main may not ship it.
    # On apt: warn loudly but don't fail the install (defer to F6 require_cmd
    # at engine startup). On pacman/dnf: install normally.
    if ! command -v hyprctl &>/dev/null; then
        if [ "$pkgr" == "apt" ]; then
            echo "⚠ WARNING: hyprctl (hyprland) is a HARD REQUIREMENT but may not be in Debian main."
            echo "  Install it manually: sudo apt install hyprland"
            echo "  (or build from source — see https://wiki.hyprland.org/)"
            echo "  The engine will refuse to start (exit 127) if hyprctl is absent."
        else
            missing+=("$(pkg_for "$pkgr" hyprctl)")
        fi
    fi

    # Install collected missing packages
    if [ ${#missing[@]} -gt 0 ]; then
        echo "📦 Installing missing dependencies via $pkgr: ${missing[*]}"
        case "$pkgr" in
            pacman) sudo pacman -Sy --noconfirm --needed "${missing[@]}" ;;
            apt)    sudo apt-get update && sudo apt-get install -y "${missing[@]}" ;;
            dnf)    sudo dnf install -y "${missing[@]}" ;;
        esac
    else
        echo "📦 All required dependencies already present."
    fi

    # The `shellcheck` binary is optional (smoke-test linter step). Offer but don't force.
    if ! command -v shellcheck &>/dev/null; then
        echo "💡 Optional: install shellcheck for the smoke-test linter step:"
        case "$pkgr" in
            pacman) echo "    sudo pacman -S shellcheck" ;;
            apt)    echo "    sudo apt install shellcheck" ;;
            dnf)    echo "    sudo dnf install shellcheck" ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# F10 — Idempotent file deployment
# ---------------------------------------------------------------------------
deploy_files() {
    mkdir -p ~/.config/rdp/profiles
    mkdir -p ~/.config/rdp/i18n
    mkdir -p ~/.local/bin
    mkdir -p ~/.local/lib/rdp
    mkdir -p ~/.local/state/rdp
    mkdir -p ~/Compartido

    # i18n + template (overwrite every run — idempotent)
    install -D -m 600 "$SCRIPT_DIR/i18n/es.env" ~/.config/rdp/i18n/es.env
    install -D -m 600 "$SCRIPT_DIR/i18n/en.env" ~/.config/rdp/i18n/en.env
    install -D -m 600 "$SCRIPT_DIR/template/template.env" ~/.config/rdp/template.env

    # User-edited profiles are preserved ([ -f ] guard — existing partner.env pattern)
    if [ ! -f ~/.config/rdp/profiles/partner.env ]; then
        cat << 'PROFILE_PARTNER' > ~/.config/rdp/profiles/partner.env
HOST="hb-tipartner"
DOMAIN="MicrosoftAccount"
USER_RDP="h.buddenberg@tipartner.cl"
PASS_RDP="INGRESA_TU_PASSWORD_AQUI"
VPN_CHECK=""
PREFERRED_WS="3"
LANG_OVERRIDE="es"
PROFILE_PARTNER
    fi

    # Lib + engine (overwrite every run — idempotent)
    install -D -m 644 "$SCRIPT_DIR/lib/rdp-common.bash" ~/.local/lib/rdp/rdp-common.bash
    install -D -m 700 "$SCRIPT_DIR/engine/rdp-connect" ~/.local/bin/rdp-connect

    # Restrict permissions
    chmod 700 ~/.local/bin/rdp-connect ~/.config/rdp ~/.config/rdp/profiles
    chmod 600 ~/.config/rdp/template.env
    chmod 600 ~/.config/rdp/i18n/*.env
    # Profile .env files may not exist yet (clean HOME) — tolerate glob no-match
    chmod 600 ~/.config/rdp/profiles/*.env 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# F10 — Post-install smoke test
# ---------------------------------------------------------------------------
# (a) bash -n syntax check, (b) shellcheck at warning severity if available,
# (c) rdp-connect --help exits 0, (d) parser probe rejects a hostile profile.
# Any failure → return 1 (caller aborts the install).
run_smoke_test() {
    local engine=~/.local/bin/rdp-connect
    local lib=~/.local/lib/rdp/rdp-common.bash

    # (a) bash -n — syntax validation
    bash -n "$engine" || { echo "❌ smoke: bash -n failed (syntax error in engine)"; return 1; }

    # (b) shellcheck — warning severity (info-level findings are acceptable)
    if command -v shellcheck &>/dev/null; then
        shellcheck --severity=warning "$engine" "$lib" \
            || { echo "❌ smoke: shellcheck failed (warning-level findings in engine/lib)"; return 1; }
    else
        echo "⚠ smoke: shellcheck not installed — skipping linter step"
    fi

    # (c) --help exits 0 (engine must be runnable post-deploy)
    "$engine" --help >/dev/null \
        || { echo "❌ smoke: rdp-connect --help exited non-zero"; return 1; }

    # (d) parser probe — hostile profile (PATH=/x) MUST be rejected
    if bash -c "source '$lib'; parse_env_safe <(printf 'PATH=/x\n') profile" 2>/dev/null; then
        echo "❌ smoke: parser-probe failed (hostile profile PATH=/x was NOT rejected)"
        return 1
    fi
    # Reaching here = parser correctly rejected the hostile profile (non-zero exit)
    echo "✅ smoke: all checks passed (bash -n + shellcheck + --help + parser-probe)"
    return 0
}

# ---------------------------------------------------------------------------
# F10 — SHA-256 checksum manifest (reproducible)
# ---------------------------------------------------------------------------
write_manifest() {
    local manifest=~/.local/state/rdp/manifest.sha256
    {
        cd "$HOME" && sha256sum \
            .local/bin/rdp-connect \
            .local/lib/rdp/rdp-common.bash \
            .config/rdp/i18n/es.env \
            .config/rdp/i18n/en.env \
            .config/rdp/template.env
    } | LC_ALL=C sort > "$manifest"
    echo "📋 Manifest written to $manifest"
}

# ===========================================================================
# MAIN
# ===========================================================================
echo "🚀 Desplegando RDP Master Framework en el sistema..."

# --- F10: detect distro ---
if ! PKGR=$(detect_pkgr); then
    cat >&2 << 'UNSUPPORTED'
❌ Unsupported distribution. /etc/os-release did not match pacman/dnf/apt.

Required binaries: xfreerdp3 jq flock notify-send wofi|rofi hyprctl

Manual install commands for reference (run the one matching your distro):

  pacman:  sudo pacman -S freerdp3 jq util-linux libnotify wofi hyprland shellcheck
  apt:     sudo apt install freerdp3-x11 jq util-linux libnotify-bin wofi hyprland shellcheck
  dnf:     sudo dnf install freerdp jq util-linux libnotify wofi hyprland shellcheck

No files were written. Install the dependencies manually, then re-run this script.
UNSUPPORTED
    exit 1
fi
echo "📦 Detected package manager: $PKGR"

# --- F10: install missing deps ---
install_deps "$PKGR"

# --- F10: deploy files (idempotent) ---
deploy_files

# --- F10: smoke test ---
echo ""
echo "🔍 Running post-install smoke test..."
run_smoke_test || { echo "❌ Smoke test failed — aborting install."; exit 1; }

# --- F10: checksum manifest ---
write_manifest

echo ""
echo "✅ Framework RDP desplegado exitosamente."
echo "   Edit ~/.config/rdp/profiles/<name>.env to set real credentials."
