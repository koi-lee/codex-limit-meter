#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG="$PROJECT_DIR/dist/CodexLimitMeter.dmg"

: "${NOTARY_PROFILE:=codex-limit-meter}"

test -f "$DMG" || { echo "未找到 $DMG，请先运行 ./build.sh --dmg" >&2; exit 1; }

xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "✅ 公证完成：$DMG"
