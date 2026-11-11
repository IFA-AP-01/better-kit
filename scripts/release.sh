#!/bin/bash
# Archives BetterKit, exports it with Developer ID, notarizes and staples the app and the DMG.
# The DMG goes to build/release/<version>-<build>; the exported app stays in .build/export so
# Spotlight and Launchpad only list the installed copy. Nothing is uploaded.
#
# Usage: scripts/release.sh [options]
#   --archive PATH     use an existing .xcarchive instead of archiving
#   --no-notarize      skip notarization (local test build only)
#   --no-layout        skip the DMG Finder layout
#   --sparkle URL      also zip the update and write appcast.xml for this HTTPS download prefix
#
# Reads BETTERKIT_NOTARY_ISSUER_ID, BETTERKIT_NOTARY_KEY_ID and BETTERKIT_NOTARY_KEY_PATH from
# Config/Environment.xcconfig (environment variables of the same name win).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_CONFIG="$ROOT/Config/Environment.xcconfig"
ARCHIVE=""
NOTARIZE=1
DMG_FLAGS=()
SPARKLE_PREFIX=""

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="${2%/}"; shift 2 ;;
    --no-notarize) NOTARIZE=0; shift ;;
    --no-layout) DMG_FLAGS+=(--no-layout); shift ;;
    --sparkle) SPARKLE_PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

xcconfig_value() {
  awk -v name="$1" 'index($0, "=") {
    key = substr($0, 1, index($0, "=") - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
    if (key == name) { value = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", value); result = value }
  } END { print result }' "$ENV_CONFIG" 2>/dev/null
}

TEAM="${BETTERKIT_DEVELOPMENT_TEAM:-$(xcconfig_value BETTERKIT_DEVELOPMENT_TEAM)}"
NOTARY_ISSUER="${BETTERKIT_NOTARY_ISSUER_ID:-$(xcconfig_value BETTERKIT_NOTARY_ISSUER_ID)}"
NOTARY_KEY_ID="${BETTERKIT_NOTARY_KEY_ID:-$(xcconfig_value BETTERKIT_NOTARY_KEY_ID)}"
NOTARY_KEY="${BETTERKIT_NOTARY_KEY_PATH:-$(xcconfig_value BETTERKIT_NOTARY_KEY_PATH)}"
[[ -z "$NOTARY_KEY" || "$NOTARY_KEY" == /* ]] || NOTARY_KEY="$ROOT/$NOTARY_KEY"

[ -n "$TEAM" ] || fail "set BETTERKIT_DEVELOPMENT_TEAM in Config/Environment.xcconfig"
[[ "$(security find-identity -v -p codesigning)" == *"Developer ID Application"*"($TEAM)"* ]] \
  || fail "no 'Developer ID Application' certificate for team $TEAM in the keychain"
if [ "$NOTARIZE" = 1 ]; then
  [ -n "$NOTARY_ISSUER" ] && [ -n "$NOTARY_KEY_ID" ] && [ -f "$NOTARY_KEY" ] \
    || fail "set BETTERKIT_NOTARY_ISSUER_ID, BETTERKIT_NOTARY_KEY_ID and BETTERKIT_NOTARY_KEY_PATH, or pass --no-notarize"
fi

notarize() {
  local file="$1" result status
  echo "Notarizing $(basename "$file") (this can take a few minutes)…"
  result="$(xcrun notarytool submit "$file" --issuer "$NOTARY_ISSUER" --key-id "$NOTARY_KEY_ID" --key "$NOTARY_KEY" \
    --wait --timeout 1h --output-format plist)"
  status="$(plutil -extract status raw - <<<"$result")"
  [ "$status" = "Accepted" ] || { echo "$result" >&2; fail "notarization status: $status"; }
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -z "$ARCHIVE" ]; then
  command -v xcodegen >/dev/null && xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
  ARCHIVE="$ROOT/build/archives/BetterKit-$(date '+%Y%m%d-%H%M%S').xcarchive"
  echo "Archiving…"
  nice -n 10 xcodebuild -project "$ROOT/BetterKit.xcodeproj" -scheme BetterKit -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$ROOT/.build/release" -archivePath "$ARCHIVE" \
    "CODE_SIGN_IDENTITY=Developer ID Application: $(security find-identity -v -p codesigning \
      | sed -n "s/.*\"Developer ID Application: \([^\"]*($TEAM)\)\".*/\1/p" | head -1)" \
    archive -quiet
fi
[[ -d "$ARCHIVE" && "$ARCHIVE" == *.xcarchive ]] || fail "not an .xcarchive: $ARCHIVE"

PLIST="$ARCHIVE/Products/Applications/BetterKit.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
[ "$(sed -n '/[^[:space:]]/{p;q;}' "$ROOT/RELEASE_NOTES.md")" = "# BetterKit $VERSION" ] \
  || fail "RELEASE_NOTES.md must start with '# BetterKit $VERSION'"
echo "Releasing BetterKit $VERSION ($BUILD)"

OUT="$ROOT/build/release/$VERSION-$BUILD"
EXPORT="$ROOT/.build/export/$VERSION-$BUILD"
rm -rf "$OUT" "$EXPORT"
mkdir -p "$OUT"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
EOF
echo "Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$WORK/ExportOptions.plist" -quiet
APP="$EXPORT/BetterKit.app"
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(codesign -dvv "$APP/Contents/MacOS/BetterKitHelper" 2>&1)" == *"TeamIdentifier=$TEAM"* ]] || fail "helper is not signed by team $TEAM"

if [ "$NOTARIZE" = 1 ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
  notarize "$WORK/notarize.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

DMG="$("$ROOT/scripts/make-dmg.sh" "$APP" -o "$OUT" ${DMG_FLAGS[@]+"${DMG_FLAGS[@]}"} | tail -1)"
[ -f "$DMG" ] || fail "DMG was not created"
if [ "$NOTARIZE" = 1 ]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
fi

[ -z "$SPARKLE_PREFIX" ] || "$ROOT/scripts/make-sparkle-update.sh" --app "$APP" --download-url-prefix "$SPARKLE_PREFIX"

echo
echo "BetterKit $VERSION ($BUILD)"
echo "  App: $APP"
echo "  DMG: $DMG"
