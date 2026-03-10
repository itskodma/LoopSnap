#!/usr/bin/env bash
# bundle_app.sh - Build LoopSnap and wrap it in a proper .app bundle.
# Usage:  chmod +x bundle_app.sh && ./bundle_app.sh
set -euo pipefail

APP="LoopSnap"
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
    cp "Sources/LoopSnap/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Write Info.plist
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LoopSnap</string>
    <key>CFBundleDisplayName</key><string>LoopSnap</string>
    <key>CFBundleIdentifier</key><string>com.veilasius.loopsnap</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>LoopSnap</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>LoopSnap needs screen recording permission to capture your screen.</string>
</dict>
</plist>
PLIST

# Touch so Finder refreshes the icon cache
touch "$BUNDLE"

echo "${BUNDLE} is ready. Open with:"
echo "   open \"$BUNDLE\""
