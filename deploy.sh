#!/bin/bash
set -e

APP_NAME="LocalFlow"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="/Applications/${APP_NAME}.app"

echo "🚀 Starting Clean Build & Deploy for ${APP_NAME}..."

# 1. Kill running instances
echo "🛑 Killing existing instances..."
pkill -f "${APP_NAME}" 2>/dev/null || true
sleep 1

# 2. Build in release mode
echo "🧹 Compiling Swift package..."
cd "${PROJECT_PATH}"
swift build -c release

BIN_PATH="$(find .build -name "LocalFlow" -type f -perm +111 | grep -i "Release" | head -n 1)"
if [ -z "$BIN_PATH" ]; then
    BIN_PATH=".build/out/Products/Debug/LocalFlow"
fi

# 3. Assemble temporary staging app bundle
STAGE_DIR="${PROJECT_PATH}/${APP_NAME}.app"
mkdir -p "${STAGE_DIR}/Contents/MacOS" "${STAGE_DIR}/Contents/Resources"
cp "${BIN_PATH}" "${STAGE_DIR}/Contents/MacOS/${APP_NAME}"

cat << 'EOF' > "${STAGE_DIR}/Contents/Info.plist"
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

# 4. Deploy to /Applications using rsync (preserving inodes for TCC)
echo "📦 Deploying to ${DESTINATION}..."
mkdir -p "${DESTINATION}"
rsync -a --delete "${STAGE_DIR}/" "${DESTINATION}/"

# 5. Sign with stable "LocalFlow Development" certificate (avoids CDHash invalidation on rebuild)
CERT_NAME="LocalFlow Development"
if ! security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "🔑 Setting up persistent code signing certificate (${CERT_NAME})..."
    CERT_DIR="/tmp/localflow_cert_gen"
    mkdir -p "${CERT_DIR}"
    cat << 'CERTEOF' > "${CERT_DIR}/cert.conf"
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
x509_extensions     = v3_req

[ req_distinguished_name ]
CN                  = LocalFlow Development

[ v3_req ]
keyUsage            = critical, digitalSignature
extendedKeyUsage    = critical, codeSigning
basicConstraints    = critical, CA:FALSE
CERTEOF
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "${CERT_DIR}/dev.key" -out "${CERT_DIR}/dev.crt" -days 3650 -config "${CERT_DIR}/cert.conf" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey "${CERT_DIR}/dev.key" -in "${CERT_DIR}/dev.crt" -out "${CERT_DIR}/dev.p12" -password pass:localflow -name "${CERT_NAME}" 2>/dev/null
    security import "${CERT_DIR}/dev.p12" -k ~/Library/Keychains/login.keychain-db -P localflow -T /usr/bin/codesign -T /usr/bin/security
    security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db "${CERT_DIR}/dev.crt" 2>/dev/null || true
    rm -rf "${CERT_DIR}"
fi

echo "🔏 Signing app with persistent identity '${CERT_NAME}' and entitlements..."
codesign --force --deep --sign "${CERT_NAME}" --entitlements "${PROJECT_PATH}/LocalFlow.entitlements" "${DESTINATION}"

# 6. Launch from /Applications
echo "🚀 Launching from /Applications..."
open "${DESTINATION}"

echo "✅ LocalFlow deployed and running from /Applications!"
