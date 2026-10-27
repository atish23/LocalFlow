#!/bin/bash
set -e

# LocalFlow DMG Packaging Script
# Creates a clean, distributable macOS disk image with /Applications symlink.

APP_NAME="LocalFlow"
VERSION="1.0.0"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
OUTPUT_DIR="${PROJECT_DIR}/build"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
OUTPUT_DMG="${OUTPUT_DIR}/${DMG_NAME}"
STAGING_DIR="/tmp/localflow_dmg_staging"

echo "Creating distribution DMG for ${APP_NAME} v${VERSION}..."

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "App bundle not found at ${APP_BUNDLE}. Run ./package.sh first."
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rm -rf "${STAGING_DIR}" "${OUTPUT_DMG}"
mkdir -p "${STAGING_DIR}"

echo "Staging application bundle and Applications symlink..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Building compressed disk image..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}"

rm -rf "${STAGING_DIR}"

echo "Disk image created at: ${OUTPUT_DMG}"
echo "SHA-256 Checksum:"
shasum -a 256 "${OUTPUT_DMG}"

echo "DMG creation completed successfully."
