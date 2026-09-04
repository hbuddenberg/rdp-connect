#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  rdp-connect — Direct Sync & Dotfiles Deployment Pipeline
#  Deploys local rdp-connect changes to ~/.local & ~/.config, then syncs Chezmoi.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${HOME}/.dotfiles"
CHEZMOI="${HOME}/.local/bin/chezmoi"

if [ ! -x "$CHEZMOI" ]; then
    CHEZMOI="chezmoi"
fi

show_help() {
    cat <<EOF
Usage: ./sync-system.sh [OPTIONS]

Options:
  -p, --pull     Pull latest git changes in this repository before deploying
  --no-push      Do not push dotfiles git repository to remote
  -h, --help     Show this help message
EOF
}

DO_PULL=false
DO_PUSH=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pull)
            DO_PULL=true
            shift
            ;;
        --no-push)
            DO_PUSH=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

echo "======================================================="
echo "   rdp-connect — Sync & Dotfiles Pipeline              "
echo "======================================================="

# 1. Optionally pull repo updates
if [[ "$DO_PULL" == true ]]; then
    echo "==> Pulling latest changes from git remote..."
    git -C "$SCRIPT_DIR" pull --ff-only
fi

# 2. Deploy locally via install.sh
echo "==> Deploying engine, UI, and templates locally..."
"${SCRIPT_DIR}/install.sh" --user --force

# 3. Synchronize with Chezmoi
if command -v "$CHEZMOI" &>/dev/null; then
    echo "==> Synchronizing changes into Chezmoi dotfiles..."
    "$CHEZMOI" re-add

    # Ensure optional and profile files are tracked
    "$CHEZMOI" add \
        "${HOME}/.config/rdp/ui/shell.qml" \
        "${HOME}/.config/freerdp/sdl-freerdp.json" \
        "${HOME}/.config/rdp/profiles"/*.env 2>/dev/null || true

    # Commit and push dotfiles repository if changes are present
    if [ -d "$DOTFILES_DIR/.git" ] && [ -n "$(git -C "$DOTFILES_DIR" status --porcelain)" ]; then
        echo "==> Dotfiles changes detected, committing..."
        git -C "$DOTFILES_DIR" add -A
        COMMIT_HASH=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")
        git -C "$DOTFILES_DIR" commit -m "feat(rdp-connect): sync engine, ui, and configs (${COMMIT_HASH})"

        if [[ "$DO_PUSH" == true ]]; then
            echo "==> Pushing dotfiles to remote..."
            git -C "$DOTFILES_DIR" push origin main 2>/dev/null || git -C "$DOTFILES_DIR" push origin master 2>/dev/null || true
        fi
    else
        echo "==> Chezmoi dotfiles repository is already up to date."
    fi
else
    echo "==> Warning: chezmoi not found, skipping dotfiles sync." >&2
fi

# 4. Refresh Omarchy plugins if running
if command -v omarchy-shell &>/dev/null; then
    echo "==> Rescanning Omarchy shell plugins..."
    omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "======================================================="
echo "   ¡Sync completado con éxito!                        "
echo "======================================================="
