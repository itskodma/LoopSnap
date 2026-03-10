#!/usr/bin/env bash
# bundle_app.sh - Build ScreenToGif and wrap it in a proper .app bundle.
# Usage:  chmod +x bundle_app.sh && ./bundle_app.sh
set -euo pipefail

APP="ScreenToGif"
BUNDLE="$APP.app"
BIN=".build/debug/$APP"

echo "Building..."
swift build

echo "Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Copy executable
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"

# Copy icon
RESOURCE_BUNDLE=".build/debug/${APP}_${APP}.bundle"
if [ -f "$RESOURCE_BUNDLE/AppIcon.icns" ]; then
    cp "$RESOURCE_BUNDLE/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
else
    # Fallback: copy directly from source
    cp "Sources/ScreenToGif/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Write Info.plist
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Screen to GIF</string>
    <key>CFBundleDisplayName</key><string>Screen to GIF</string>
    <key>CFBundleIdentifier</key><string>com.screentogif.app</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>ScreenToGif</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Screen to GIF needs screen recording permission to capture your screen.</string>
</dict>
</plist>
PLIST

# Touch so Finder refreshes the icon cache
touch "$BUNDLE"

echo "${BUNDLE} is ready. Open with:"
echo "   open $BUNDLE"
