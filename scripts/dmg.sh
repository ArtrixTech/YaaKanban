#!/bin/sh
# Usage: dmg.sh <YaaKanban.app> <out.dmg>
# Builds the drag-to-install disk image: the app on the left, an Applications link on the right,
# the brand and an arrow on the background (scripts/dmg-background.swift), the app icon as the
# volume icon. Finder lays the window out, so this needs
# a logged-in session and permission for the terminal to control Finder.
set -eu
cd "$(dirname "$0")/.."
APP="$1"; OUT="$2"
VOLUME="YaaKanban"
WORK="build/dmg"

fail() { echo "dmg: $*" >&2; exit 1; }
[ -d "$APP" ] || fail "no app at $APP"
# A volume of the same name would get mounted as "YaaKanban 1" and miss the layout.
[ ! -e "/Volumes/$VOLUME" ] || fail "/Volumes/$VOLUME is already mounted; eject it first"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/root/.background"
ditto "$APP" "$WORK/root/YaaKanban.app"
ln -s /Applications "$WORK/root/Applications"
swift scripts/dmg-background.swift Resources/Brand/logo.svg "$WORK/bg.png" 1
swift scripts/dmg-background.swift Resources/Brand/logo.svg "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/root/.background/background.tiff" 2>/dev/null

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$WORK/root" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
trap 'hdiutil detach -quiet "/Volumes/$VOLUME" 2>/dev/null || true' EXIT

# Window content 640×400 (bounds add the 28 pt title bar); icon size and centres match scripts/dmg-background.swift.
osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 120
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "YaaKanban.app" of container window to {170, 210}
    set position of item "Applications" of container window to {470, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# Finder writes .DS_Store lazily; wait for it before detaching.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "/Volumes/$VOLUME/.DS_Store" ] && break
  sleep 1
done
[ -f "/Volumes/$VOLUME/.DS_Store" ] || fail "Finder did not save the window layout"
chflags hidden "/Volumes/$VOLUME/.background"
# After the layout: Finder drops a volume icon present while it lays the window out.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOLUME/.VolumeIcon.icns"
  chflags hidden "/Volumes/$VOLUME/.VolumeIcon.icns"
  SetFile -a C "/Volumes/$VOLUME"
fi
sync
hdiutil detach -quiet "/Volumes/$VOLUME"
trap - EXIT

hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf "$WORK"
echo "built $OUT"
