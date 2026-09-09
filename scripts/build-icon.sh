#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

APP="$1"
SRC="icon.png"
ICONSET="build/ToolsSpecter.iconset"

echo "==> Creating app icon ($SRC)"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$APP/Contents/Resources"

for spec in \
    "icon_16x16.png 16" \
    "icon_16x16@2x.png 32" \
    "icon_32x32.png 32" \
    "icon_32x32@2x.png 64" \
    "icon_128x128.png 128" \
    "icon_128x128@2x.png 256" \
    "icon_256x256.png 256" \
    "icon_256x256@2x.png 512" \
    "icon_512x512.png 512" \
    "icon_512x512@2x.png 1024"
do
    name="${spec%% *}"
    size="${spec##* }"
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ToolsSpecter.icns"
rm -rf "$ICONSET"