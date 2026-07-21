#!/usr/bin/env bash
# bootstrap.sh — cross-machine one-shot installer for rdp-connect.
#
# Usage (from any machine with bash + curl + git):
#   curl -fsSL https://raw.githubusercontent.com/hbuddenberg/rdp-connect/main/bootstrap.sh | bash
#
# Or, cloned already:
#   ./bootstrap.sh
#
# This script is DETERMINISTIC and REPRODUCIBLE by construction:
#   1. Always clones the same ref (default: main; override via RDP_CONNECT_REF=tag).
#   2. Delegates to install-rdp-framework.sh which deploys real files via `install -D`.
#   3. Verifies deployment via SHA-256 manifest written by the installer.
#   4. Exits non-zero on ANY missing required dep — no silent degradation.
#
# Re-running produces an identical end-state (idempotent deploy + checksum verify).

set -euo pipefail

REPO="https://github.com/hbuddenberg/rdp-connect.git"
REF="${RDP_CONNECT_REF:-main}"
CLONE_DIR=""

cleanup() {
    if [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ]; then
        rm -rf "$CLONE_DIR"
    fi
}
trap cleanup EXIT

err() {
    printf '\033[31m[bootstrap]\033[0m %s\n' "$*" >&2
    exit 1
}

log() {
    printf '\033[34m[bootstrap]\033[0m %s\n' "$*"
}

# --- Pre-flight: required tools ---------------------------------------------
for cmd in git bash install sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || err "missing required command: $cmd"
done
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || err "missing both curl and wget (need one)"

# Auth strategy: gh CLI (works for private repos via cached token) takes
# precedence; plain `git clone` works for public repos or hosts with a
# configured credential helper. If neither path succeeds, the error from git
# is descriptive enough (typically "could not read Username for 'https://...'").
USE_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    USE_GH=1
    log "gh CLI authenticated — using gh repo clone (supports private repo)"
else
    log "no gh auth — using plain git clone (requires public repo or cached credential helper)"
fi

# --- Clone ------------------------------------------------------------------
CLONE_DIR="$(mktemp -d -t rdp-connect-XXXXXX)"
log "cloning ref='$REF' to $CLONE_DIR"
if [ "$USE_GH" -eq 1 ]; then
    gh repo clone hbuddenberg/rdp-connect "$CLONE_DIR/repo" -- --depth 1 --branch "$REF" >/dev/null 2>&1 \
        || err "gh repo clone failed (check network, ref='$REF', repo accessibility for your gh account)"
else
    git clone --depth 1 --branch "$REF" "$REPO" "$CLONE_DIR/repo" >/dev/null 2>&1 \
        || err "git clone failed (if repo is private: install gh CLI and run 'gh auth login', or make the repo public)"
fi

# --- Verify clone integrity (recorded HEAD commit) --------------------------
HEAD_SHA="$(git -C "$CLONE_DIR/repo" rev-parse HEAD)"
log "cloned at commit $HEAD_SHA"

# --- Delegate to the deterministic installer --------------------------------
log "running install-rdp-framework.sh"
(
    cd "$CLONE_DIR/repo"
    # install-rdp-framework.sh exits non-zero on missing deps, unsupported distro,
    # failed smoke test, or manifest mismatch. We let that propagate up.
    ./install-rdp-framework.sh
)

# --- Post-install verification ----------------------------------------------
ENGINE_PATH="${HOME}/.local/bin/rdp-connect"
LIB_PATH="${HOME}/.local/lib/rdp/rdp-common.bash"
MANIFEST_PATH="${HOME}/.local/state/rdp/manifest.sha256"

[ -x "$ENGINE_PATH" ] || err "engine not deployed at $ENGINE_PATH"
[ -f "$MANIFEST_PATH" ] || err "manifest not written at $MANIFEST_PATH"

log "verifying deployment via SHA-256 manifest"
# Manifest lists paths relative to $HOME; run from $HOME so paths resolve.
( cd "$HOME" && sha256sum -c "$MANIFEST_PATH" >/dev/null 2>&1 ) \
    || err "manifest verification FAILED — deployed files do not match repo. Re-run bootstrap."

log "smoke test: rdp-connect --help"
"$ENGINE_PATH" --help >/dev/null 2>&1 \
    || err "smoke test FAILED — 'rdp-connect --help' did not exit 0"

cat <<EOF

\033[32m[bootstrap]\033[0m rdp-connect installed successfully.

  Engine      : $ENGINE_PATH
  Library     : $LIB_PATH
  Manifest    : $MANIFEST_PATH
  Profiles    : ~/.config/rdp/profiles/*.env
  Logs        : ~/.local/state/rdp/<profile>.log

Next steps:
  1. Create a profile:  rdp-connect --new myserver
  2. Edit credentials:  \$EDITOR ~/.config/rdp/profiles/myserver.env
  3. Connect:           rdp-connect myserver
  4. Graphical menu:    rdp-connect

Installed from: $REPO @ $HEAD_SHA (ref=$REF)

EOF
