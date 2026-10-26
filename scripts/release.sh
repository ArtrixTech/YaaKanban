#!/bin/sh
# Usage: release.sh
# Publishes the version in Resources/Info.plist as GitHub release v<version>: checks the tree and
# CHANGELOG.md, tests, builds and signs the app, zips it, tags HEAD and creates the release with
# the changelog section as notes. Run on main after the release PR is merged.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
# The app only accepts an update signed by the team that signed it (Updater.verify).
TEAM="${YAAK_RELEASE_TEAM:-5KZD8GBF7G}"
ZIP="build/YaaKanban-$VERSION.zip"
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

rm -f "$ZIP"
ditto -c -k --keepParent build/YaaKanban.app "$ZIP"

# The app shows the notes above the rule when it offers the update.
{
  cat "$NOTES.body"
  echo
  echo "---"
  echo
  echo "**Install**: download \`YaaKanban-$VERSION.zip\`, unzip, move YaaKanban.app to Applications. It is not notarized yet, so the first time run \`xattr -dr com.apple.quarantine /Applications/YaaKanban.app\` (or allow it in System Settings › Privacy & Security). Later versions update from inside the app."
} > "$NOTES"
rm -f "$NOTES.body"

git tag -a "$TAG" -m "YaaKanban $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" "$ZIP" --title "YaaKanban $VERSION" --notes-file "$NOTES" --verify-tag
echo "released $TAG"
