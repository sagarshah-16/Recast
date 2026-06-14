#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Recast.app and zips it for
# distribution via GitHub Releases. The app is ad-hoc signed — see the
# README for the one-time Gatekeeper step users need after downloading.
set -euo pipefail
cd "$(dirname "$0")"

APP="Recast.app"
ARM=".build/arm64-apple-macosx/release/Recast"
X86=".build/x86_64-apple-macosx/release/Recast"

echo "Building arm64…"
swift build -c release --triple arm64-apple-macosx
echo "Building x86_64…"
swift build -c release --triple x86_64-apple-macosx

echo "Assembling universal $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Recast" "$ARM" "$X86"
cp Support/Info.plist "$APP/Contents/Info.plist"

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "Zipping → Recast.zip…"
rm -f Recast.zip
ditto -c -k --keepParent "$APP" Recast.zip

lipo -info "$APP/Contents/MacOS/Recast"
echo "Done → $(pwd)/Recast.zip"
