#!/bin/bash
set -e

# LocalFlow Standalone App Packaging Script

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

BUILD_DMG=false
for arg in "$@"; do
    if [ "$arg" == "--dmg" ]; then
        BUILD_DMG=true
    fi
done

echo "Building LocalFlow in release mode..."
swift build -c release

BIN_PATH="$(find .build -name "LocalFlow" -type f -perm +111 | grep -i "Release" | head -n 1)"
if [ -z "$BIN_PATH" ]; then
    echo "Error: LocalFlow release binary not found in .build directory."
    exit 1
fi

APP_DIR="LocalFlow.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Assembling bundle structure at ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH" "$MACOS/LocalFlow"

# Copy App Icon if available
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LocalFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.atish.LocalFlow</string>
    <key>CFBundleName</key>
    <string>LocalFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>LocalFlow requires microphone access for on-device voice dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>LocalFlow requires speech recognition to transcribe speech locally.</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/atish23/LocalFlow/main/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

CERT_NAME="LocalFlow Development"
if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "Signing LocalFlow.app with persistent identity '${CERT_NAME}' and entitlements..."
    codesign --force --deep --sign "${CERT_NAME}" --entitlements "LocalFlow.entitlements" "$APP_DIR"
else
    echo "Signing LocalFlow.app ad-hoc..."
    codesign --force --deep --sign - --entitlements "LocalFlow.entitlements" "$APP_DIR"
fi

echo "LocalFlow.app packaged successfully at: $DIR/LocalFlow.app"

if [ "$BUILD_DMG" = true ]; then
    ./scripts/create_dmg.sh
fi
