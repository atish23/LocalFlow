#!/bin/bash
set -e

# LocalFlow Notarization Script
# Submits a release artifact (DMG or ZIP) to Apple Notary Service and staples the ticket.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="${1:-${PROJECT_DIR}/build/LocalFlow-1.0.0.dmg}"
KEYCHAIN_PROFILE="${2:-AC_PASSWORD}"

echo "Starting Apple Notarization for: ${TARGET_FILE}"

if [ ! -f "${TARGET_FILE}" ]; then
    echo "Error: Target file ${TARGET_FILE} does not exist."
    echo "Usage: ./scripts/notarize.sh [path-to-dmg-or-zip] [keychain-profile-name]"
    echo ""
    echo "Tip: To set up a notarytool keychain profile, run:"
    echo "  xcrun notarytool store-credentials \"AC_PASSWORD\" \\"
    echo "    --apple-id \"your.apple.id@email.com\" \\"
    echo "    --team-id \"YOUR_TEAM_ID\" \\"
    echo "    --password \"app-specific-password\""
    exit 1
fi

echo "Submitting to Apple Notary Service using profile '${KEYCHAIN_PROFILE}'..."
xcrun notarytool submit "${TARGET_FILE}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait

echo "Stapling notarization ticket to artifact..."
xcrun stapler staple "${TARGET_FILE}"

echo "Verifying notarized signature..."
spctl -a -t open --context context:primary-signature -v "${TARGET_FILE}"

echo "Notarization and stapling complete!"
