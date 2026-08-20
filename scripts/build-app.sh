#!/usr/bin/env bash
# Build DuplicateFinderMac as a proper .app bundle so it launches with a window.
# Uses SwiftPM to compile the binary, then wraps it in a minimal .app.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="DuplicateFinder"
BUNDLE_ID="com.singhanoop.duplicatefinder"

echo "==> swift build -c $CONFIG --product DuplicateFinderMac"
cd "$ROOT"
swift build -c "$CONFIG" --product DuplicateFinderMac

BIN="$ROOT/.build/$CONFIG/DuplicateFinderMac"
APP="$ROOT/.build/$CONFIG/$APP_NAME.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><false/>
  <key>LSBackgroundOnly</key><false/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc code sign"
codesign --force --deep --sign - "$APP"

echo
echo "Built: $APP"
echo "Launch it with:  open \"$APP\""
