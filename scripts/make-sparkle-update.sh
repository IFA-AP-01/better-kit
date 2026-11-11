#!/bin/bash
# Zips a signed, notarized BetterKit.app for Sparkle and regenerates the appcast locally.
#
# Usage: scripts/make-sparkle-update.sh --app BetterKit.app --download-url-prefix URL [options]
#   --app PATH                 exported, notarized BetterKit.app
#   --download-url-prefix URL  where the zips will be served, e.g. https://updates.example.com/betterkit/releases/
#   --archives-dir DIR         update history; every zip in it stays in the appcast (default: build/sparkle-releases)
#   --release-notes FILE       Markdown notes embedded in the appcast (default: RELEASE_NOTES.md)
#   --keychain-account NAME    login Keychain account of the EdDSA private key (default: betterkit)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=""
PREFIX=""
ARCHIVES_DIR="$ROOT/build/sparkle-releases"
NOTES="$ROOT/RELEASE_NOTES.md"
ACCOUNT="betterkit"

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2%/}"; shift 2 ;;
    --download-url-prefix) PREFIX="$2"; shift 2 ;;
    --archives-dir) ARCHIVES_DIR="$2"; shift 2 ;;
    --release-notes) NOTES="$2"; shift 2 ;;
    --keychain-account) ACCOUNT="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

[[ -d "$APP" && "$APP" == *.app ]] || fail "--app must point to BetterKit.app"
[[ "$PREFIX" == https://* ]] || fail "--download-url-prefix must be an HTTPS URL"
[[ "$PREFIX" == */ ]] || PREFIX="$PREFIX/"
[ -f "$NOTES" ] || fail "release notes not found: $NOTES"

GENERATE_APPCAST="$(find "$ROOT/.build" "$HOME/Library/Developer/Xcode/DerivedData" -type f -perm -111 \
  -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null || true)"
[ -x "$GENERATE_APPCAST" ] || fail "generate_appcast not found; build the app once first"

PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$PLIST" 2>/dev/null || true)"
KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
[[ "$FEED" == https://* ]] || fail "SUFeedURL is empty; set BETTERKIT_SU_FEED_URL in Config/Environment.xcconfig and rebuild"
[ -n "$KEY" ] || fail "SUPublicEDKey is empty; set BETTERKIT_SU_PUBLIC_ED_KEY in Config/Environment.xcconfig and rebuild"
[ "$(sed -n '/[^[:space:]]/{p;q;}' "$NOTES")" = "# BetterKit $VERSION" ] \
  || fail "$(basename "$NOTES") must start with '# BetterKit $VERSION'"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

mkdir -p "$ARCHIVES_DIR"
ZIP="$ARCHIVES_DIR/BetterKit-$VERSION.zip"
[ ! -e "$ZIP" ] || fail "$ZIP already exists; bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cp "$NOTES" "$ARCHIVES_DIR/BetterKit-$VERSION.md"

"$GENERATE_APPCAST" --account "$ACCOUNT" --download-url-prefix "$PREFIX" --embed-release-notes \
  --maximum-deltas 0 -o "$ARCHIVES_DIR/appcast.xml" "$ARCHIVES_DIR"

echo "$ZIP"
echo "$ARCHIVES_DIR/appcast.xml"
