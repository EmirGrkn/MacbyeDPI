#!/bin/bash
# MacbyeDPI Menu Bar App — build script (no sudo needed)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${DIR}/MacbyeDPI.app"

echo "=== MacbyeDPI App Builder ==="
echo ""

# Check swiftc
if ! command -v swiftc &>/dev/null; then
    echo "Error: swiftc not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

echo "[1/2] Compiling Swift..."
swiftc -framework Cocoa \
       -O \
       "${DIR}/app/MacbyeDPI.swift" \
       -o "${DIR}/app/MacbyeDPI_bin"

echo "[2/2] Assembling .app bundle..."

# Generate .icns from filled.png
ICONSET="${DIR}/MacbyeDPI.iconset"
rm -rf "${ICONSET}"
mkdir "${ICONSET}"
for size in 16 32 128 256 512; do
    sips -z ${size} ${size} "${DIR}/filled.png" \
         --out "${ICONSET}/icon_${size}x${size}.png"      >/dev/null
    double=$((size * 2))
    sips -z ${double} ${double} "${DIR}/filled.png" \
         --out "${ICONSET}/icon_${size}x${size}@2x.png"   >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${DIR}/app/MacbyeDPI.icns"
rm -rf "${ICONSET}"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${DIR}/app/MacbyeDPI_bin"   "${APP}/Contents/MacOS/MacbyeDPI"
cp "${DIR}/app/Info.plist"      "${APP}/Contents/Info.plist"
cp "${DIR}/app/MacbyeDPI.icns"  "${APP}/Contents/Resources/"

echo ""
echo "✓ Build complete: ${APP}"
echo ""
echo "Next: sudo ./install_app.sh"
