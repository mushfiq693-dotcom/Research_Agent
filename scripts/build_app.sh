#!/bin/bash
set -e

echo "=== Building Personal Research Agent Release App Bundle ==="

APP_NAME="PersonalResearchAgent"
BUILD_DIR=".build/release"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS_FILE="entitlements.plist"

# 1. Compile Release Executable
swift build -c release

# 2. Prepare App Bundle Structure
rm -rf "${BUNDLE_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 3. Copy Binary
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 4. Generate Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PersonalResearchAgent</string>
    <key>CFBundleIdentifier</key>
    <string>com.personalresearchagent.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Personal Research Agent</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Personal Research Agent requires microphone access to listen to your voice commands.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Personal Research Agent requires speech recognition to understand research requests.</string>
</dict>
</plist>
EOF

# 5. Generate Entitlements
cat << 'EOF' > "${ENTITLEMENTS_FILE}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.personal-information.speech-recognition</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

# 6. Codesign the Application Bundle with Ad-Hoc Signature and Entitlements
echo "Signing ${BUNDLE_NAME} with entitlements..."
codesign --force --deep --sign - --entitlements "${ENTITLEMENTS_FILE}" "${BUNDLE_NAME}"

echo "✅ Successfully built and signed ${BUNDLE_NAME}!"
echo "To run, launch ./PersonalResearchAgent.app or copy to /Applications."
