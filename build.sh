#!/bin/bash
# Builds Recast.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Recast.app"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Recast"

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Recast"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Sign with the local "Recast Dev" certificate when present so the
# signature — and therefore the Accessibility grant — stays stable across
# rebuilds. Falls back to ad-hoc signing.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Recast Dev"; then
    codesign --force --deep --sign "Recast Dev" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

echo "Done → $(pwd)/$APP"
echo "Run with: open $APP"
