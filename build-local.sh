#!/usr/bin/env bash
# build-local.sh — Build rdp-connect package locally for testing before AUR upload
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGBUILD_SRC="${SCRIPT_DIR}/PKGBUILD"

PKGNAME=$(grep "^pkgname=" "${PKGBUILD_SRC}" | cut -d= -f2)
VERSION=$(grep "^pkgver=" "${PKGBUILD_SRC}" | cut -d= -f2)
PKGREL=$(grep "^pkgrel=" "${PKGBUILD_SRC}" | cut -d= -f2)

TARBALL="${PKGNAME}-${VERSION}.tar.gz"

echo ""
echo "  🖥️  RDP Connect — Local Build v${VERSION}-${PKGREL}"
echo "  ──────────────────────────────────────────"
echo ""

BUILD_DIR="$(mktemp -d /tmp/rdp-build-XXXXXX)"
echo "  Build dir: ${BUILD_DIR}"
echo ""

trap 'echo ""; echo "  Build dir preserved: ${BUILD_DIR}"' EXIT

echo "  [1/4] Creating source tarball (current working tree)..."
tar czf "${BUILD_DIR}/${TARBALL}" \
    --directory="${SCRIPT_DIR}" \
    --transform "s|^\\./|${PKGNAME}-${VERSION}/|" \
    --exclude='./.git' \
    --exclude='./node_modules' \
    --exclude='./*.pkg.tar.*' \
    --exclude='./src' \
    --exclude='./pkg' \
    --exclude='./*.tar.gz' \
    .
echo "        ✅ ${TARBALL}"

echo "  [2/4] Computing sha256sum..."
CHECKSUM=$(sha256sum "${BUILD_DIR}/${TARBALL}" | awk '{print $1}')
echo "        ${CHECKSUM}"

echo "  [3/4] Patching PKGBUILD..."
cp "${PKGBUILD_SRC}" "${BUILD_DIR}/PKGBUILD"
cp "${SCRIPT_DIR}/rdp-connect.install" "${BUILD_DIR}/rdp-connect.install"

sed -i \
    -e "s|^pkgrel=.*|pkgrel=${PKGREL}|" \
    -e "s|^source=(.*)|source=(\"${TARBALL}\")|" \
    -e "s|^sha256sums=(.*)|sha256sums=(\"${CHECKSUM}\")|" \
    "${BUILD_DIR}/PKGBUILD"
echo "        ✅ Source and checksums patched"

echo "  [4/4] Running makepkg..."
cd "${BUILD_DIR}"
makepkg -s

PKG_FILE=$(ls "${BUILD_DIR}"/*.pkg.tar.* 2>/dev/null | head -1)
echo ""
echo "  ✅ Package built:"
echo "     ${PKG_FILE}"
echo ""
echo "  Install with: sudo pacman -U ${PKG_FILE}"
