#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app="build/Book Brain.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/BookBrain" "$app/Contents/MacOS/BookBrain"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
