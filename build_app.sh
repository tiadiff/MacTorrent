#!/bin/bash
set -e

APP_NAME="MacTorrent"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
ICON_SOURCE="/Users/tiadiff/.gemini/antigravity/brain/4a8879c9-a173-4e8d-8d53-1c88ad7ef9f9/mactorrent_icon_1770162449512.png"

echo "🚀 Building ${APP_NAME} (Release)..."
swift build -c release

echo "📦 Creating .app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Helpers"

# Bundle transmission-daemon
if [ -f "/usr/local/bin/transmission-daemon" ]; then
    echo "📦 Bundling transmission-daemon..."
    cp /usr/local/bin/transmission-daemon "${APP_BUNDLE}/Contents/Helpers/"
    chmod +x "${APP_BUNDLE}/Contents/Helpers/transmission-daemon"
fi

echo "📜 Creating Info.plist..."
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "🎨 Generating AppIcon.icns..."
ICONSET_DIR="AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"

# Resize images
sips -s format png -z 16 16     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png"
sips -s format png -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png"
sips -s format png -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png"
sips -s format png -z 64 64     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png"
sips -s format png -z 128 128   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png"
sips -s format png -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png"
sips -s format png -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png"
sips -s format png -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png"
sips -s format png -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png"
sips -s format png -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png"

# Convert to icns
iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

echo "🚚 Copying binary..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

echo "🖊️ Signing app with entitlements..."
codesign --force --deep --sign - --entitlements "Entitlements.plist" "${APP_BUNDLE}"

echo "✅ Done! ${APP_BUNDLE} is ready."
open -R "${APP_BUNDLE}"
