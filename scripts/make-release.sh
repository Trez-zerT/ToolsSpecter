#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building arm64 (release)"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build-arm64

echo "==> Building x86_64 (release)"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build-x64

APP="build/ToolsSpecter.app"
VERSION="1.0.0"
ZIP="build/ToolsSpecter-${VERSION}-macOS.zip"

echo "==> Assembling universal $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
lipo -create \
    .build-arm64/release/ToolsSpecter \
    .build-x64/release/ToolsSpecter \
    -output "$APP/Contents/MacOS/ToolsSpecter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Ad-hoc codesigning"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> Verifying architectures"
lipo -info "$APP/Contents/MacOS/ToolsSpecter"
codesign -dv "$APP" 2>&1 | grep -E 'Format|Signature'

echo "==> Packaging $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"
