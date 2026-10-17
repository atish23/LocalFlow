#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Building LocalFlow in release mode..."
swift build -c release

BIN_PATH="$(find .build -name "LocalFlow" -type f -perm +111 | grep "Release" | head -n 1)"
if [ -z "$BIN_PATH" ]; then
    BIN_PATH=".build/out/Products/Debug/LocalFlow"
fi

APP_DIR="LocalFlow.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH" "$MACOS/LocalFlow"

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
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>LocalFlow requires microphone access for on-device voice dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>LocalFlow requires speech recognition to transcribe speech locally.</string>
</dict>
</plist>
EOF

echo "Signing LocalFlow.app ad-hoc..."
codesign --force --deep --sign - "$APP_DIR"

echo "LocalFlow.app packaged successfully at: $DIR/LocalFlow.app"
