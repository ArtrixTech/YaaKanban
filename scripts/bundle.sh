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
# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc signing changes every build.
IDENTITY="${YAAK_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
mkdir -p "$APP/Contents/Resources/AgentIcons"
cp Resources/AgentIcons/*.svg "$APP/Contents/Resources/AgentIcons/"
cp Resources/Brand/logo.svg "$APP/Contents/Resources/logo.svg"
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/yaak"
codesign --force --sign "$IDENTITY" "$APP"
echo "signed with: $IDENTITY"
echo "built $APP"
