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

# Sign with the stable "LocalWillow Signing" identity when present so macOS
# permissions persist across rebuilds. Ad-hoc fallback changes the signature
# every build and therefore orphans grants — reset them so the app re-prompts.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "LocalWillow Signing"; then
  # Dedicated signing keychain (guards only this self-signed key, hence the
  # plaintext password) — pre-authorized for codesign so builds never prompt.
  security unlock-keychain -p localwillow-sign localwillow.keychain 2>/dev/null || true
  codesign --force --deep --sign "LocalWillow Signing" "$APP"
  SIGNED="stable identity (permissions persist across rebuilds)"
else
  codesign --force --deep --sign - "$APP"
  tccutil reset Accessibility dev.yun.localwillow >/dev/null || true
  SIGNED="ad-hoc (re-grant Accessibility after install)"
fi

# Install to /Applications (the app's permanent home for TCC purposes).
osascript -e 'tell application "LocalWillow" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/LocalWillow.app
ditto "$APP" /Applications/LocalWillow.app

echo "Built and installed /Applications/LocalWillow.app — signed: $SIGNED"
