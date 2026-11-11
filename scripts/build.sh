#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="Debug"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    Debug|Release) CONFIG="$arg" ;;
    *) echo "usage: $0 [Debug|Release] [--install]" >&2; exit 2 ;;
  esac
done
command -v xcodegen >/dev/null && xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
nice -n 10 xcodebuild -project "$ROOT/BetterKit.xcodeproj" -scheme BetterKit -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/.build/app" build -quiet
APP="$ROOT/.build/app/Build/Products/$CONFIG/BetterKit.app"
if [ "$INSTALL" = 1 ]; then
  osascript -e 'tell application id "dev.ifateam.betterkit" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x BetterKit >/dev/null || break; sleep 0.5; done
  rm -rf /Applications/BetterKit.app
  cp -R "$APP" /Applications/
  echo "/Applications/BetterKit.app"
else
  echo "$APP"
fi
