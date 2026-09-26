#!/bin/bash
# Assemble a real Presence.app bundle from the SwiftPM build.
# Usage: ./Scripts/make_app.sh [release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="debug"
if [[ "${1:-}" == "release" ]]; then CONFIG="release"; fi

BIN="PresenceApp"
BIN_PATH=".build/$CONFIG/$BIN"
APP_DIR="dist/Presence.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $CONFIG..."
swift build -c "$CONFIG"

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH" "$MACOS/$BIN"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Presence</string>
	<key>CFBundleDisplayName</key>
	<string>Presence</string>
	<key>CFBundleIdentifier</key>
	<string>com.krishna.presence</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>PresenceApp</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Presence listens for your phone's Bluetooth beacon in the background and locks your Mac when it goes out of range.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>Presence listens for your phone's Bluetooth beacon in the background.</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Sign with the stable self-signed identity when present (keeps Accessibility grants
# valid across rebuilds). Falls back to ad-hoc when the keychain is missing.
IDENTITY="Presence Code Signing"
KC="$HOME/Library/Keychains/presence-codesign.keychain-db"
if security find-certificate -c "$IDENTITY" -Z "$KC" >/dev/null 2>&1; then
	security unlock-keychain -p presence-codesign "$KC" >/dev/null 2>&1
	codesign --force --sign "$IDENTITY" --keychain "$KC" "$APP_DIR"
else
	codesign --force --sign - "$APP_DIR"
fi

echo "Done -> dist/Presence.app"
echo "Drag it into your Applications folder, or run: open dist/Presence.app"