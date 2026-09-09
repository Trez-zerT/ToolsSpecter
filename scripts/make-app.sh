#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building (release)"
swift build -c release

BIN=".build/release/ToolsSpecter"
APP="build/ToolsSpecter.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ToolsSpecter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Ad-hoc codesigning"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> Done: $APP"
echo "    Run with: open $APP"
