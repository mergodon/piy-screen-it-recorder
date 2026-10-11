#!/usr/bin/env zsh
# Build build/ScreenItRecorder.app. Signs ad-hoc unless SIGN_ID names a codesigning identity
# (e.g. SIGN_ID="Developer ID Application: …"), which also enables the hardened runtime.
set -euo pipefail
cd "${0:A:h}"

APP=build/ScreenItRecorder.app
swift build -c release

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp .build/release/ScreenItRecorder "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

swift tools/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --options runtime --entitlements Resources/ScreenItRecorder.entitlements \
    --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "Built $APP"
