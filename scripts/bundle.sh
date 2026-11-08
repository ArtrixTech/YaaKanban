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
if [ -n "${YAAK_APTABASE_APP_KEY:-}" ]; then
  plutil -replace YaakAptabaseAppKey -string "$YAAK_APTABASE_APP_KEY" "$APP/Contents/Info.plist"
fi
# Sign with the release team's certificate, so a local install and a release share one designated
# requirement. macOS grants Accessibility to that requirement, not to the bundle id: another team's
# cert (or ad-hoc signing, which changes every build) drops the grant on the next install.
# Picking "the first identity" did exactly that — the keychain holds a second, unrelated team.
TEAM="${YAAK_RELEASE_TEAM:-5KZD8GBF7G}"
# The team is the certificate's OU; the suffix in its name (7XZ34D8PVC) is the person's ID.
team_of() {
  security find-certificate -c "$1" -p 2>/dev/null |
    openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null |
    sed -n 's/.*OU=\([^,]*\).*/\1/p'
}
identity_for_team() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1|\2/p' |
    while IFS='|' read -r sha name; do
      [ -n "$sha" ] || continue
      if [ "$(team_of "$name")" = "$TEAM" ]; then printf '%s\n' "$sha"; break; fi
    done
}
# A SHA-1 names one certificate: a renewed cert keeps the name (CN) but changes the hash.
IDENTITY="${YAAK_SIGN_IDENTITY:-$(identity_for_team)}"
if [ -z "$IDENTITY" ]; then
  echo "bundle: no codesigning identity for team $TEAM" >&2
  echo "bundle: fix it in Xcode › Settings › Accounts, or set YAAK_SIGN_IDENTITY=<SHA-1>" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Resources/AgentIcons"
cp Resources/AgentIcons/*.svg "$APP/Contents/Resources/AgentIcons/"
cp Resources/Brand/logo.svg Resources/Brand/home.svg "$APP/Contents/Resources/"
# The app icon is rendered from the same mark (scripts/icon.swift).
ICONSET="$(dirname "$APP")/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/icon.swift Resources/Brand/logo.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/yaak"
codesign --force --sign "$IDENTITY" "$APP"
echo "signed with: $IDENTITY"
echo "built $APP"
