#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${CODEX_BUILD_DIR:-$ROOT/dist}"
if [[ -e "$OUT" ]]; then
  echo "Output exists; set CODEX_BUILD_DIR to a new directory." >&2
  exit 1
fi
APP="$OUT/Codex Meter Open Source.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -framework Cocoa -framework SwiftUI -framework UserNotifications -framework WebKit "$ROOT"/Sources/CodexMeter/*.swift -o "$APP/Contents/MacOS/CodexMeter"
cp -R "$ROOT/Sources/CodexMeter/Pet" "$APP/Contents/Resources/Pet"
cp "$ROOT"/Sources/CodexMeter/*.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexMeter</string>
<key>CFBundleIdentifier</key><string>com.starshoreai.codexmeter.opensource</string>
<key>CFBundleName</key><string>Codex Meter Open Source</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>20261002</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built local app: %s\n' "$APP"
