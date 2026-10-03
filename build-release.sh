#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${CODEX_BUILD_DIR:-$PROJECT_DIR/outputs/builds.noindex/$(date +%Y%m%d-%H%M%S)}"
APP_NAME="Quota Orbit"
EXECUTABLE_NAME="CodexMeter"
EXPECTED_TEAM_ID="4BHPD976HX"
EXPECTED_SIGNING_IDENTITY="Developer ID Application: ZEAN LI ($EXPECTED_TEAM_ID)"

# 版本号可在命令行注入，避免每次发版改脚本：
#   MARKETING_VERSION=1.2.0 CURRENT_PROJECT_VERSION=49 ./build.sh --dmg
# 不注入时用下面的默认值。CFBundleVersion 必须单调递增，不能回退。
MARKETING_VERSION="${MARKETING_VERSION:-1.3.0}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-60}"

# Preserve existing packages; use a fresh output directory for each release.
if [ -e "$BUILD_DIR" ]; then
    echo "输出目录已存在，请设置 CODEX_BUILD_DIR 为新目录，避免覆盖旧包。" >&2
    exit 1
fi
mkdir -p "$BUILD_DIR"

echo "🔨 Building CodexMeter..."

# Check for --dmg flag
BUILD_DMG=false
if [ "${1:-}" == "--dmg" ]; then
    BUILD_DMG=true
fi

# 本地构建允许 Ad-hoc；正式 DMG 必须精确使用更名后的 Developer ID 证书。
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [ "$BUILD_DMG" = true ]; then
    SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-$EXPECTED_SIGNING_IDENTITY}"
    if [ "$SIGNING_IDENTITY" != "$EXPECTED_SIGNING_IDENTITY" ]; then
        echo "❌ 正式构建拒绝：签名身份必须是 $EXPECTED_SIGNING_IDENTITY" >&2
        exit 1
    fi
    security find-identity -v -p codesigning | grep -Fq "\"$EXPECTED_SIGNING_IDENTITY\"" || {
        echo "❌ 未找到有效证书：$EXPECTED_SIGNING_IDENTITY" >&2
        exit 1
    }
fi

# Compile (output to temp name, will move into .app)
TMP_BINARY="$BUILD_DIR/${APP_NAME}_tmp"
swiftc -target arm64-apple-macos13.0 -parse-as-library -framework Cocoa -framework SwiftUI -framework UserNotifications -framework WebKit \
    -o "$TMP_BINARY" \
    "$PROJECT_DIR/Sources/CodexMeter/AppDelegate.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/UsageTracker.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/ContentView.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/Announcements.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/DemoSession.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/StorefrontPolicy.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/StoreAccountController.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/PetState.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/PetMessages.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/PetConstellation.swift" \
    "$PROJECT_DIR/Sources/CodexMeter/PetWindowController.swift"

# Create app bundle
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
cp "$TMP_BINARY" "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"

# Copy the approved product icon and generate the macOS icon family.
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"
cp -R "$PROJECT_DIR/Sources/CodexMeter/Pet" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/Pet"

ICON_PNG="$PROJECT_DIR/Sources/CodexMeter/BrandIcon.png"
test -f "$ICON_PNG"
cp "$ICON_PNG" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.png"
cp "$ICON_PNG" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/BrandIcon.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
xattr -cr "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"

MENU_ICON_PNG="$PROJECT_DIR/Sources/CodexMeter/appIcon2.png"
if [ -f "$MENU_ICON_PNG" ]; then
    cp "$MENU_ICON_PNG" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/appIcon2.png"
fi



# Remove temp binary (user should only use .app, not bare binary)
rm -f "$TMP_BINARY"

# Ensure Info.plist exists with app metadata
# 注意：此处用非引号 heredoc，才能展开版本变量；plist 正文里不得出现 $ 或反引号。
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents"
cat > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Quota Orbit</string>
    <key>CFBundleExecutable</key>
    <string>CodexMeter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.starshoreai.codexmeter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Quota Orbit</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${CURRENT_PROJECT_VERSION}</string>
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

# 版本号落地校验：防止 heredoc 被改回引号写法后 plist 里残留字面量。
BUILT_MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist")"
BUILT_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist")"
case "$BUILT_MARKETING_VERSION" in
    *'$'*) echo "❌ Info.plist 版本号未展开：$BUILT_MARKETING_VERSION" >&2; exit 1 ;;
esac
echo "   version: $BUILT_MARKETING_VERSION (build $BUILT_BUILD_VERSION)"

cp "$PROJECT_DIR/LICENSE" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/THIRD_PARTY_NOTICES.md"

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

codesign --verify --deep --strict "$BUILD_DIR/$APP_NAME.app"
if [ "$BUILD_DMG" = true ]; then
    SIGNATURE_DETAILS="$(codesign -dvvv "$BUILD_DIR/$APP_NAME.app" 2>&1)"
    grep -Fq "Authority=$EXPECTED_SIGNING_IDENTITY" <<<"$SIGNATURE_DETAILS" || {
        echo "❌ 正式构建拒绝：产物证书姓名不正确" >&2
        exit 1
    }
    grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$SIGNATURE_DETAILS" || {
        echo "❌ 正式构建拒绝：产物 Team ID 不正确" >&2
        exit 1
    }
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
    hdiutil create -volname "Codex Meter" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_FILE"

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
