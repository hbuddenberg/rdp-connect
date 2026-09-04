#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
#  RDP Connect — Robust Installer
#  Modern RDP Connection Manager for Hyprland, Niri & Wayland
# ─────────────────────────────────────────────────────────
set -euo pipefail

readonly RDP_VERSION="2.0.0"
readonly APP_NAME="RDP Connect"

# ── Catppuccin Mocha Colors (truecolor ANSI) ─────────────
readonly C_RED=$'\033[38;2;243;139;168m'      # #f38ba8
readonly C_PEACH=$'\033[38;2;250;179;135m'    # #fab387
readonly C_YELLOW=$'\033[38;2;249;226;175m'   # #f9e2af
readonly C_GREEN=$'\033[38;2;166;227;161m'    # #a6e3a1
readonly C_BLUE=$'\033[38;2;137;180;250m'     # #89b4fa
readonly C_MAUVE=$'\033[38;2;203;166;247m'    # #cba6f7
readonly C_TEAL=$'\033[38;2;148;226;213m'     # #94e2d5
readonly C_TEXT=$'\033[38;2;205;214;244m'     # #cdd6f4
readonly C_SURFACE0=$'\033[38;2;49;50;68m'    # #313244
readonly C_SUBTEXT=$'\033[38;2;166;173;200m'  # #a6adc8
readonly C_BOLD=$'\033[1m'
readonly C_DIM=$'\033[2m'
readonly C_RESET=$'\033[0m'

# ── Source Paths ─────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SRC_BIN="${SCRIPT_DIR}/engine/rdp-connect"
readonly SRC_LIB="${SCRIPT_DIR}/lib/rdp-common.bash"
readonly SRC_UI="${SCRIPT_DIR}/ui/shell.qml"
readonly SRC_TEMPLATE="${SCRIPT_DIR}/template/template.env"
readonly SRC_I18N="${SCRIPT_DIR}/i18n"

# ── User Config Path (always user-owned) ─────────────────
readonly CONFIG_DIR="${HOME}/.config/rdp"
readonly STATE_DIR="${HOME}/.local/state/rdp"
readonly SHARE_DIR="${HOME}/Compartido"

# ── Install Destinations ─────────────────────────────────
BIN_DIR=""
DATA_DIR=""
INSTALL_MODE=""   # "system" or "user"

# ── Logging Helpers ──────────────────────────────────────
info()    { echo -e "${C_BLUE}[INFO]${C_RESET}  ${C_TEXT}$*${C_RESET}"; }
success() { echo -e "${C_GREEN}[ OK ]${C_RESET}  ${C_TEXT}$*${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET}  ${C_TEXT}$*${C_RESET}"; }
error()   { echo -e "${C_RED}[ERR]${C_RESET}   ${C_TEXT}$*${C_RESET}" >&2; }
step()    { echo -e "  ${C_TEAL}➜${C_RESET}  ${C_TEXT}$*${C_RESET}"; }
header()  {
    echo -e ""
    echo -e "${C_MAUVE}${C_BOLD} 🖥️ $*${C_RESET}"
    echo -e "${C_SURFACE0}  ──────────────────────────────────────────${C_RESET}"
    echo -e ""
}
note()    { echo -e "  ${C_DIM}${C_SUBTEXT}$*${C_RESET}"; }

# ── Argument Parsing ─────────────────────────────────────
ARG_UNINSTALL=false
ARG_FORCE=false
ARG_USER=false
ARG_SYSTEM=false

show_usage() {
    cat <<EOF
${APP_NAME} Installer v${RDP_VERSION}

Usage:
  ./install.sh [OPTIONS]

Options:
  --uninstall, -u   Remove ${APP_NAME} from the system
  --system          Force system-wide install (/usr/local)
  --user            Force user-local install (~/.local)
  --force, -f       Overwrite existing files without prompting
  --help, -h        Show this help message
  --version, -v     Show installer version
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall|-u)   ARG_UNINSTALL=true; shift ;;
            --force|-f)       ARG_FORCE=true; shift ;;
            --user)           ARG_USER=true; shift ;;
            --system)         ARG_SYSTEM=true; shift ;;
            --help|-h)        show_usage; exit 0 ;;
            --version|-v)     echo "${APP_NAME} Installer v${RDP_VERSION}"; exit 0 ;;
            *)                error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done
}

# ── Dependency Check ─────────────────────────────────────
check_deps() {
    header "Checking Dependencies"

    local -a required=("xfreerdp3" "jq" "notify-send" "flock")
    local -a optional=("quickshell" "walker" "wofi" "rofi")
    local -a missing=()

    for dep in "${required[@]}"; do
        if command -v "$dep" &>/dev/null; then
            success "${dep} found"
        else
            error "${dep} NOT found"
            missing+=("$dep")
        fi
    done

    for dep in "${optional[@]}"; do
        if command -v "$dep" &>/dev/null; then
            success "${dep} found (UI launcher)"
            break
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        error "Missing required dependencies: ${missing[*]}"
        echo -e "  Install on Arch: sudo pacman -S freerdp jq libnotify util-linux"
        exit 1
    fi
}

detect_install_mode() {
    if [[ "${ARG_SYSTEM}" == true ]]; then
        INSTALL_MODE="system"
    elif [[ "${ARG_USER}" == true ]]; then
        INSTALL_MODE="user"
    elif [[ "$(id -u)" -eq 0 ]]; then
        INSTALL_MODE="system"
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        INSTALL_MODE="system"
    else
        INSTALL_MODE="user"
    fi

    case "${INSTALL_MODE}" in
        system)
            BIN_DIR="/usr/local/bin"
            DATA_DIR="/usr/local/share/rdp-connect"
            info "Install mode: ${C_BOLD}system-wide${C_RESET} (requires sudo)"
            ;;
        user)
            BIN_DIR="${HOME}/.local/bin"
            DATA_DIR="${HOME}/.local/share/rdp-connect"
            info "Install mode: ${C_BOLD}user-local${C_RESET}"
            ;;
    esac
}

elevated_cp() {
    if [[ "${INSTALL_MODE}" == "system" ]] && [[ "$(id -u)" -ne 0 ]]; then
        sudo cp "$@"
    else
        cp "$@"
    fi
}

elevated_mkdir() {
    local dir="$1"
    if [[ "${INSTALL_MODE}" == "system" ]] && [[ "$(id -u)" -ne 0 ]]; then
        sudo mkdir -p "$dir"
    else
        mkdir -p "$dir"
    fi
}

elevated_chmod() {
    local mode="$1" target="$2"
    if [[ "${INSTALL_MODE}" == "system" ]] && [[ "$(id -u)" -ne 0 ]]; then
        sudo chmod "$mode" "$target"
    else
        chmod "$mode" "$target"
    fi
}

elevated_rm() {
    local target="$1"
    if [[ "${INSTALL_MODE}" == "system" ]] && [[ "$(id -u)" -ne 0 ]]; then
        sudo rm -rf "$target"
    else
        rm -rf "$target"
    fi
}

do_install() {
    header "Installing ${APP_NAME}"

    # 1. Directories
    step "Creating directories..."
    elevated_mkdir "${BIN_DIR}"
    elevated_mkdir "${DATA_DIR}/lib"
    elevated_mkdir "${DATA_DIR}/ui"
    elevated_mkdir "${DATA_DIR}/i18n"
    elevated_mkdir "${DATA_DIR}/template"
    mkdir -p "${CONFIG_DIR}/profiles"
    mkdir -p "${CONFIG_DIR}/i18n"
    mkdir -p "${CONFIG_DIR}/ui"
    mkdir -p "${STATE_DIR}"
    mkdir -p "${SHARE_DIR}"
    mkdir -p "${HOME}/.local/lib/rdp"

    # 2. Binary
    step "Installing engine binary..."
    elevated_cp "${SRC_BIN}" "${BIN_DIR}/rdp-connect"
    elevated_chmod 755 "${BIN_DIR}/rdp-connect"
    cp "${SRC_BIN}" "${HOME}/.local/bin/rdp-connect" 2>/dev/null || true
    chmod 755 "${HOME}/.local/bin/rdp-connect" 2>/dev/null || true
    success "Binary installed → ${BIN_DIR}/rdp-connect"

    # 3. Libraries
    step "Installing libraries..."
    elevated_cp "${SRC_LIB}" "${DATA_DIR}/lib/rdp-common.bash"
    cp "${SRC_LIB}" "${HOME}/.local/lib/rdp/rdp-common.bash"
    success "Library installed → ${DATA_DIR}/lib/rdp-common.bash"

    # 4. Quickshell UI
    if [[ -f "${SRC_UI}" ]]; then
        step "Installing Quickshell modal UI..."
        elevated_cp "${SRC_UI}" "${DATA_DIR}/ui/shell.qml"
        cp "${SRC_UI}" "${CONFIG_DIR}/ui/shell.qml"
        success "Quickshell modal UI installed → ~/.config/rdp/ui/shell.qml"
    fi

    # 5. i18n & Template
    step "Installing templates and translations..."
    if [[ -d "${SRC_I18N}" ]]; then
        elevated_cp "${SRC_I18N}"/*.env "${DATA_DIR}/i18n/"
        cp "${SRC_I18N}"/*.env "${CONFIG_DIR}/i18n/"
    fi
    if [[ -f "${SRC_TEMPLATE}" ]]; then
        elevated_cp "${SRC_TEMPLATE}" "${DATA_DIR}/template/template.env"
        cp "${SRC_TEMPLATE}" "${CONFIG_DIR}/template.env"
    fi

    # Permissions
    chmod 700 "${CONFIG_DIR}" "${CONFIG_DIR}/profiles" "${STATE_DIR}"
    chmod 600 "${CONFIG_DIR}/template.env" "${CONFIG_DIR}/i18n"/*.env 2>/dev/null || true
    chmod 600 "${CONFIG_DIR}/profiles"/*.env 2>/dev/null || true

    echo ""
    echo -e "${C_GREEN}${C_BOLD}  ✅ ${APP_NAME} installed successfully!${C_RESET}"
    echo ""
    echo -e "  Run:    rdp-connect"
    echo -e "  New:    rdp-connect --new <nombre>"
    echo -e "  Help:   rdp-connect --help"
}

do_uninstall() {
    header "Uninstalling ${APP_NAME}"
    elevated_rm "/usr/local/bin/rdp-connect"
    elevated_rm "/usr/local/share/rdp-connect"
    rm -f "${HOME}/.local/bin/rdp-connect"
    rm -rf "${HOME}/.local/share/rdp-connect"
    rm -rf "${HOME}/.local/lib/rdp"
    success "Removed binary and libraries"
    echo -e "  Config preserved at ~/.config/rdp/"
}

main() {
    parse_args "$@"
    if [[ "${ARG_UNINSTALL}" == true ]]; then
        do_uninstall
    else
        check_deps
        detect_install_mode
        do_install
    fi
}

main "$@"
