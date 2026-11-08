#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app="build/Book Brain.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/BookBrain" "$app/Contents/MacOS/BookBrain"
cp Resources/Info.plist "$app/Contents/Info.plist"
iconset="build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
licenses="$app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp .build/checkouts/swift-markdown-ui/LICENSE "$licenses/MarkdownUI.txt"
cp .build/checkouts/NetworkImage/LICENSE "$licenses/NetworkImage.txt"
cp .build/checkouts/swift-cmark/COPYING "$licenses/cmark.txt"
codesign --force --sign - "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
