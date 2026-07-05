#!/bin/zsh
# Build LocalWillow.app (native, no Xcode project needed).
set -e
cd "$(dirname "$0")"

APP=../LocalWillow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc Sources/*.swift \
  -o "$APP/Contents/MacOS/LocalWillow" \
  -O -swift-version 5 \
  -framework AppKit -framework SwiftUI -framework AVFoundation \
  -framework ServiceManagement -framework ApplicationServices

cp Info.plist "$APP/Contents/Info.plist"

# App icon (rendered once, then cached).
if [ ! -f AppIcon.icns ]; then
  swift make_icon.swift /tmp/willow_icon_1024.png
  ICONSET=/tmp/willow.iconset
  rm -rf "$ICONSET"; mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s /tmp/willow_icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) /tmp/willow_icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o AppIcon.icns
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough for local use; macOS permissions attach to it.
codesign --force --deep --sign - "$APP"

# Install to /Applications (the app's permanent home for TCC purposes).
# NOTE: every rebuild changes the ad-hoc signature, so Accessibility must be
# re-granted after installing: run  tccutil reset Accessibility dev.yun.localwillow
# then re-enable it in System Settings when the app prompts.
osascript -e 'tell application "LocalWillow" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/LocalWillow.app
ditto "$APP" /Applications/LocalWillow.app

echo "Built and installed /Applications/LocalWillow.app"
