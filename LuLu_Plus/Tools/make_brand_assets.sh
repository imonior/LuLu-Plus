#!/bin/bash
#
# Regenerates every shipped brand image from the master artwork at the repo root.
#
#   LuLu_Plus/App/Assets.xcassets/AppIcon.appiconset/       the app's icon, all ten sizes
#   DMG/LuLu_Plus.icns                                      the disk image's volume icon
#   LuLu_Plus/App/Assets.xcassets/Icon.imageset/            the icon the About and Alert windows show
#   LuLu_Plus/App/Assets.xcassets/LuLu_PlusText.imageset/   the "LuLu_Plus" wordmark
#   LuLu_Plus/App/Assets.xcassets/PrefsLanguage.imageset/   the Language tab's toolbar icon
#
# Usage: Tools/make_brand_assets.sh [master.png]
#
# The master has to be a square PNG, 1024x1024. Tools/AppIconRenderer.swift draws it on Apple's
# macOS icon grid and Tools/WordmarkRenderer.swift draws the wordmark; see those files for the
# geometry and the colours. Tools/PrefsIconRenderer.swift is independent of the master - it draws
# a toolbar glyph in the same colours as the catalog's other tab icons.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$PROJECT_DIR")"

SOURCE="${1:-$REPO_DIR/lulu_plus.png}"
ICONSET="$PROJECT_DIR/App/Assets.xcassets/AppIcon.appiconset"
GLYPH_SET="$PROJECT_DIR/App/Assets.xcassets/Icon.imageset"
TEXT_SET="$PROJECT_DIR/App/Assets.xcassets/LuLu_PlusText.imageset"
PREFS_SET="$PROJECT_DIR/App/Assets.xcassets/PrefsLanguage.imageset"
DMG_ICNS="$REPO_DIR/DMG/LuLu_Plus.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "ERROR: no master image at $SOURCE" >&2
    exit 1
fi

WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ {print $2}')
if [[ "$WIDTH" != "1024" || "$HEIGHT" != "1024" ]]; then
    echo "ERROR: master image is ${WIDTH}x${HEIGHT}, expected 1024x1024" >&2
    exit 1
fi

echo "master: $SOURCE"

#the app's icon set
swift "$SCRIPT_DIR/AppIconRenderer.swift" "$SOURCE" "$ICONSET"
if [[ $? -ne 0 ]]; then
    echo "ERROR: rendering the app icon failed" >&2
    exit 1
fi

#every name below has to exist, or Xcode flags the set as incomplete
for name in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
            icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
            icon_512x512.png icon_512x512@2x.png; do
    if [[ ! -f "$ICONSET/$name" ]]; then
        echo "ERROR: $name was not rendered" >&2
        exit 1
    fi
done

#the About and Alert windows show the icon itself, not a bare glyph
cp "$ICONSET/icon_512x512@2x.png" "$GLYPH_SET/lulu_plus_icon.png"

#the wordmark is drawn from the icon's own colours
swift "$SCRIPT_DIR/WordmarkRenderer.swift" "$TEXT_SET/lulu_plus_text.pdf"
if [[ $? -ne 0 ]]; then
    echo "ERROR: rendering the wordmark failed" >&2
    exit 1
fi

#the Language tab's toolbar glyph, one PDF per appearance
swift "$SCRIPT_DIR/PrefsIconRenderer.swift" "$PREFS_SET"
if [[ $? -ne 0 ]]; then
    echo "ERROR: rendering the prefs icon failed" >&2
    exit 1
fi

for name in "prefsLanguage Any.pdf" "prefsLanguage Light.pdf" "prefsLanguage Dark.pdf"; do
    if [[ ! -f "$PREFS_SET/$name" ]]; then
        echo "ERROR: $name was not rendered" >&2
        exit 1
    fi
done

#the disk image's volume icon is built from the same files
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
cp "$ICONSET"/icon_*.png "$ICONSET_DIR/"

iconutil -c icns "$ICONSET_DIR" -o "$DMG_ICNS"
if [[ $? -ne 0 || ! -f "$DMG_ICNS" ]]; then
    echo "ERROR: iconutil failed" >&2
    exit 1
fi

echo "app icon: $ICONSET"
echo "glyph: $GLYPH_SET/lulu_plus_icon.png"
echo "wordmark: $TEXT_SET/lulu_plus_text.pdf"
echo "prefs icon: $PREFS_SET"
echo "volume icon: $DMG_ICNS"
