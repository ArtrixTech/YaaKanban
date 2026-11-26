#!/bin/sh
# Usage: release.sh
# Publishes the version in Resources/Info.plist as GitHub release v<version>: checks the tree and
# CHANGELOG.md, tests, builds and signs the app, zips it (for in-app updates) and makes the
# drag-to-install DMG (for people), tags HEAD and creates the release with
# the changelog section as notes. Run on main after the release PR is merged.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
# The app only accepts an update signed by the team that signed it (Updater.verify).
# Every release so far is team 5KZD8GBF7G; do not override this (see AGENTS.md, Release signing).
TEAM="${YAAK_RELEASE_TEAM:-5KZD8GBF7G}"
ZIP="build/YaaKanban-$VERSION.zip"
DMG="build/YaaKanban-$VERSION.dmg"
NOTES="build/release-notes.md"

fail() { echo "release: $*" >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || fail "working tree not clean"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = main ] || [ "${YAAK_RELEASE_ANY_BRANCH:-}" = 1 ] || fail "on $BRANCH, not main"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ] || fail "HEAD differs from origin/$BRANCH"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG exists"
gh release view "$TAG" >/dev/null 2>&1 && fail "release $TAG exists"

# The section of this version, without its heading, up to the next one.
mkdir -p build
awk -v v="$VERSION" '
  /^## / { if (inside) exit; h = $2; gsub(/[][]/, "", h); inside = (h == v); next }
  inside { print }
' CHANGELOG.md | sed -e '/./,$!d' > "$NOTES.body"
grep -q '[^[:space:]]' "$NOTES.body" || fail "CHANGELOG.md has no notes for $VERSION"

make test
make l10n
make app
SIGNED_TEAM=$(codesign -dv build/YaaKanban.app 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$SIGNED_TEAM" = "$TEAM" ] || fail "app signed by team '$SIGNED_TEAM', expected $TEAM (set YAAK_SIGN_IDENTITY)"
codesign --verify --deep --strict build/YaaKanban.app
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/YaaKanban.app/Contents/Info.plist)
[ "$BUILT" = "$VERSION" ] || fail "built $BUILT, expected $VERSION"
MIN_LINKED_SDK=26
for BIN_PATH in build/YaaKanban.app/Contents/MacOS/YaaKanban build/YaaKanban.app/Contents/Helpers/yaak; do
  LINKED_SDKS=$(otool -l "$BIN_PATH" | awk '
    /cmd LC_BUILD_VERSION/ { in_bv = 1; next }
    in_bv && /cmd / { in_bv = 0 }
    in_bv && $1 == "sdk" { print $2 }
  ')
  [ -n "$LINKED_SDKS" ] || fail "could not read LC_BUILD_VERSION sdk from $BIN_PATH"
  for LINKED_SDK in $LINKED_SDKS; do
    LINKED_MAJOR="${LINKED_SDK%%.*}"
    case "$LINKED_MAJOR" in
      ''|*[!0-9]*) fail "invalid LC_BUILD_VERSION sdk '$LINKED_SDK' in $BIN_PATH" ;;
    esac
    [ "$LINKED_MAJOR" -ge "$MIN_LINKED_SDK" ] || fail "$BIN_PATH linked against sdk $LINKED_SDK (< $MIN_LINKED_SDK)"
  done
done

rm -f "$ZIP"
ditto -c -k --keepParent build/YaaKanban.app "$ZIP"
scripts/dmg.sh build/YaaKanban.app "$DMG"

# The app shows the notes above the rule when it offers the update.
{
  cat "$NOTES.body"
  echo
  echo "---"
  echo
  echo "**Install**: open \`YaaKanban-$VERSION.dmg\` and drag YaaKanban into Applications. It is not notarized yet, so the first time macOS blocks it: open System Settings › Privacy & Security and click Open Anyway. Later versions update from inside the app."
} > "$NOTES"
rm -f "$NOTES.body"

git tag -a "$TAG" -m "YaaKanban $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" "$DMG" "$ZIP" --title "YaaKanban $VERSION" --notes-file "$NOTES" --verify-tag
echo "released $TAG"
