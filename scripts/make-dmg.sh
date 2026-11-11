#!/bin/bash
# Packages BetterKit.app into a drag-to-Applications DMG.
#
# Usage: scripts/make-dmg.sh BetterKit.app [options]
#   -o, --output DIR    output folder (default: build/)
#   --sign IDENTITY     codesign the DMG (default: Developer ID Application of BETTERKIT_DEVELOPMENT_TEAM, "-" to skip)
#   --no-layout         skip the Finder window layout (no Automation prompt)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BetterKit"
APP=""
OUTPUT_DIR="$ROOT/build"
SIGN_IDENTITY=""
LAYOUT=1

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --no-layout) LAYOUT=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) fail "unknown option $1" ;;
    *) APP="${1%/}"; shift ;;
  esac
done

[[ -d "$APP" && "$APP" == *.app ]] || fail "pass the path to $APP_NAME.app"
echo "App:      $APP" >&2

codesign --verify --deep --strict "$APP" || fail "code signature is invalid"
AUTHORITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
echo "Signed:   ${AUTHORITY:-ad-hoc}" >&2
case "$AUTHORITY" in
  "Developer ID Application"*) ;;
  *) echo "warning: not signed with Developer ID; Gatekeeper will block it on other Macs" >&2 ;;
esac
for required in Contents/MacOS/BetterKitHelper \
                Contents/Library/LaunchDaemons/dev.ifateam.betterkit.helper.plist \
                Contents/Frameworks/Sparkle.framework; do
  [ -e "$APP/$required" ] || fail "missing $required in the app bundle"
done
xcrun stapler validate -q "$APP" 2>/dev/null && echo "App:      notarization ticket stapled" >&2 \
  || echo "warning: app is not notarized" >&2

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUTPUT_DIR"
DMG="$OUTPUT_DIR/$APP_NAME-$VERSION-$BUILD.dmg"

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGING="$WORK/staging"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

RW="$WORK/rw.dmg"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW"

if [ "$LAYOUT" = 1 ]; then
  MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
  if [ -n "$MOUNT" ]; then
    DISK="$(basename "$MOUNT")"
    osascript >/dev/null <<EOF || echo "warning: Finder layout skipped (allow Terminal to control Finder, or use --no-layout)" >&2
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 480}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set position of item "$APP_NAME.app" of container window to {140, 170}
    set position of item "Applications" of container window to {400, 170}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
    sync
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -quiet -force
    MOUNT=""
  fi
fi

rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"

if [ -z "$SIGN_IDENTITY" ]; then
  TEAM="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Developer ID Application[^\"]*($TEAM)\)\".*/\1/p" | head -1)"
fi
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  echo "DMG signed: $SIGN_IDENTITY" >&2
fi

echo "$DMG"
