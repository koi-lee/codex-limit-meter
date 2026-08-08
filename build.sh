#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/dist"
APP_NAME="CodexLimitMeter"

# Clean and create output directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "🔨 Building CodexLimitMeter..."

# Check for --dmg flag
BUILD_DMG=false
if [ "$1" == "--dmg" ]; then
    BUILD_DMG=true
fi

# For GitHub distribution, use a Developer ID Application certificate when
# available. Keep ad-hoc signing as a local fallback so development builds
# remain possible before the certificate is installed.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1 || true)
fi

# Compile (output to temp name, will move into .app)
TMP_BINARY="$BUILD_DIR/${APP_NAME}_tmp"
swiftc -parse-as-library -framework Cocoa -framework SwiftUI \
    -o "$TMP_BINARY" \
    "$PROJECT_DIR/Sources/CodexLimitMeter/AppDelegate.swift" \
    "$PROJECT_DIR/Sources/CodexLimitMeter/UsageTracker.swift" \
    "$PROJECT_DIR/Sources/CodexLimitMeter/ContentView.swift"

# Create app bundle
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
cp "$TMP_BINARY" "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
chmod +x "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Copy icon to Resources (PNG only, no .icns)
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

ICON_PNG="$PROJECT_DIR/Sources/CodexLimitMeter/AppIcon.png"
if [ -f "$ICON_PNG" ]; then
    cp "$ICON_PNG" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.png"
fi

MENU_ICON_PNG="$PROJECT_DIR/Sources/CodexLimitMeter/appIcon2.png"
if [ -f "$MENU_ICON_PNG" ]; then
    cp "$MENU_ICON_PNG" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/appIcon2.png"
fi

# Remove any stale .icns to ensure PNG icon is used
rm -f "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"

# Remove temp binary (user should only use .app, not bare binary)
rm -f "$TMP_BINARY"

# Ensure Info.plist exists with app metadata
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents"
cat > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Codex Limit Meter</string>
    <key>CFBundleExecutable</key>
    <string>CodexLimitMeter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.codex.limit-meter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codex Limit Meter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.3</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Remove local download/source metadata before signing and packaging.
# This prevents quarantine and provenance URLs from leaking into release builds.
xattr -cr "$BUILD_DIR/$APP_NAME.app"

# Sign for distribution when Developer ID is installed; otherwise use ad-hoc
# signing for local builds. Hardened Runtime is required for notarization.
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" "$BUILD_DIR/$APP_NAME.app"
    echo "✅ Signed with: $SIGNING_IDENTITY"
else
    codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"
    echo "⚠️ No Developer ID Application certificate found; using ad-hoc signing"
fi

echo "✅ Build complete: $BUILD_DIR/$APP_NAME.app"
echo ""

if [ "$BUILD_DMG" == true ]; then
    echo "📦 Creating DMG installer..."

    DMG_STAGING="$BUILD_DIR/dmg-staging"
    DMG_FILE="$BUILD_DIR/${APP_NAME}.dmg"

    # Clean previous
    rm -rf "$DMG_STAGING"
    rm -f "$DMG_FILE"

    # Stage .app + Applications symlink (for drag-to-install)
    mkdir -p "$DMG_STAGING"
    cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create DMG (UDZO = compressed, read-only)
    hdiutil create -volname "Codex Limit Meter" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_FILE"

    # Clean staging
    rm -rf "$DMG_STAGING"

    echo "✅ DMG created: $DMG_FILE"
    echo ""
    echo "分发方式："
    echo "  将 ${APP_NAME}.dmg 发给用户，双击挂载后拖拽安装即可"
    echo "  首次打开如被拦截：系统设置 → 隐私与安全性 → 仍要打开"
else
    echo "使用方式："
    echo "  open $BUILD_DIR/$APP_NAME.app"
    echo ""
    echo "或拖拽到 Applications 文件夹后双击打开"
    echo ""
    echo "打包 DMG 分发：./build.sh --dmg"
fi
