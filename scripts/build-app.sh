#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
signing_identity="${CODE_SIGN_IDENTITY:-Book Brain Local Development}"
if [[ "$signing_identity" != "-" ]] && ! security find-identity -v -p codesigning | grep -Fq -- "$signing_identity"; then
  printf 'Signing identity not found: %s\nRun ./scripts/setup-local-signing.sh, or set CODE_SIGN_IDENTITY to an existing code-signing identity.\n' "$signing_identity" >&2
  exit 1
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p build
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Book Brain.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/BookBrain" "$app/Contents/MacOS/BookBrain"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R "$binary_dir/swiftui-math_SwiftUIMath.bundle" "$app/Contents/Resources/"
cp -R "$binary_dir/BookBrain_BookBrain.bundle" "$app/Contents/Resources/"
iconset="$staging/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
licenses="$app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp LICENSE "$licenses/BookBrain.txt"
cp .build/checkouts/swift-markdown-ui/LICENSE "$licenses/MarkdownUI.txt"
cp .build/checkouts/NetworkImage/LICENSE "$licenses/NetworkImage.txt"
cp .build/checkouts/swift-cmark/COPYING "$licenses/cmark.txt"
cp .build/checkouts/swiftui-math/LICENSE "$licenses/SwiftUIMath.txt"
codesign --force --sign "$signing_identity" --timestamp=none "$app"
codesign --verify --strict "$app"
destination="build/Book Brain.app"
if [[ -d "$destination" ]]; then
  mv "$destination" "$staging/previous.app"
fi
if ! mv "$app" "$destination"; then
  if [[ -d "$staging/previous.app" ]]; then
    mv "$staging/previous.app" "$destination"
  fi
  exit 1
fi
codesign --verify --strict "$destination"
printf 'Built %s/%s\n' "$PWD" "$destination"
if [[ "$signing_identity" == "-" ]]; then
  printf 'Ad hoc signing: Kindle capture permission may need to be granted again after a rebuild.\n' >&2
fi
