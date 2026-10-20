#!/bin/sh
# Usage: bundle.sh <debug|release> <out.app>
set -eu
CONFIG="$1"; APP="$2"
swift build -c "$CONFIG" --product YaaKanban
swift build -c "$CONFIG" --product yaak
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/YaaKanban" "$APP/Contents/MacOS/YaaKanban"
cp "$BIN/yaak" "$APP/Contents/Helpers/yaak"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/Helpers/yaak"
codesign --force --sign - "$APP"
echo "built $APP"
