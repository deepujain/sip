#!/bin/bash
# Builds Sip.app into ./build, signed ad hoc for local use.
# Release builds are universal (Apple silicon and Intel); debug builds are for this Mac only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sip.app"
CONFIG="${1:-release}"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin

swift build -c "$CONFIG" --product Sip
BIN=build/bin/Sip-native
cp "$(swift build -c "$CONFIG" --show-bin-path)/Sip" "$BIN"
if [ "$CONFIG" = release ]; then
  INTEL=x86_64-apple-macosx14.0
  swift build -c release --product Sip --triple "$INTEL"
  cp "$(swift build -c release --triple "$INTEL" --show-bin-path)/Sip" build/bin/Sip-x86_64
  lipo -create "$BIN" build/bin/Sip-x86_64 -output "$APP/Contents/MacOS/Sip"
else
  cp "$BIN" "$APP/Contents/MacOS/Sip"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"

"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime --timestamp=none "$APP"
echo "Built $APP"
