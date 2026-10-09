#!/bin/bash
#
# file: run_language_tests.sh
# description: builds a throwaway bundle around the real Settings window nib, the real string
#              catalogs and the real asset catalog, and drives the language picker in every
#              language the app ships
#
# usage: ./run_language_tests.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TEST_FILE="$SCRIPT_DIR/test_language.m"
XIB="$PROJECT_DIR/App/Base.lproj/Preferences.xib"
CATALOG="$PROJECT_DIR/Shared/Localizable.xcstrings"
MUL_CATALOG="$PROJECT_DIR/App/mul.lproj/Preferences.xcstrings"
INFO_CATALOG="$PROJECT_DIR/App/InfoPlist.xcstrings"
ASSETS="$PROJECT_DIR/App/Assets.xcassets"

BUILD_DIR="${TMPDIR:-/tmp}/lulu_plus-language-tests-$$"
BUNDLE="$BUILD_DIR/LanguageTest.app"
BUILD_LOG="$BUILD_DIR/build.log"

for required in "$TEST_FILE" "$XIB" "$CATALOG" "$MUL_CATALOG" "$INFO_CATALOG"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: missing input: $required"
        exit 1
    fi
done

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Base.lproj" || exit 1

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>test_language</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.language-tests</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>LanguageTests</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
</dict>
</plist>
PLIST

echo "== LuLu_Plus: language picker tests =="
echo "   project: $PROJECT_DIR"

#the nib the app ships, compiled from the real xib
ibtool --compile "$BUNDLE/Contents/Resources/Base.lproj/Preferences.nib" "$XIB" > "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: ibtool failed to compile the xib"
    cat "$BUILD_LOG"
    exit 1
fi

#the strings the app ships: the code catalog, and the nib's own
xcrun xcstringstool compile "$CATALOG" --output-directory "$BUNDLE/Contents/Resources" >> "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: could not compile the code string catalog"
    cat "$BUILD_LOG"
    exit 1
fi

xcrun xcstringstool compile "$MUL_CATALOG" --output-directory "$BUNDLE/Contents/Resources" >> "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: could not compile the window's string catalog"
    cat "$BUILD_LOG"
    exit 1
fi

#the images the toolbar's tabs ask for, built the way the app builds them
xcrun actool --compile "$BUNDLE/Contents/Resources" --platform macosx --minimum-deployment-target 12.0 "$ASSETS" >> "$BUILD_LOG" 2>&1
if [ $? -ne 0 ] || [ ! -f "$BUNDLE/Contents/Resources/Assets.car" ]; then
    echo "ERROR: could not compile the asset catalog"
    cat "$BUILD_LOG"
    exit 1
fi

SDK="$(xcrun --show-sdk-path --sdk macosx)"
if [ -z "$SDK" ]; then
    echo "ERROR: could not locate the macOS SDK"
    exit 1
fi

echo "   compiling the preferences window, the language model and the test"

xcrun clang \
    -fobjc-arc -fmodules \
    -isysroot "$SDK" \
    -mmacosx-version-min=12.0 \
    -I"$PROJECT_DIR/Shared" -I"$PROJECT_DIR/App" \
    -Wno-deprecated-declarations \
    -o "$BUNDLE/Contents/MacOS/test_language" \
    "$PROJECT_DIR/App/PrefsWindowController.m" \
    "$PROJECT_DIR/App/PrefsWindowController+Language.m" \
    "$PROJECT_DIR/App/Update.m" \
    "$PROJECT_DIR/App/UpdateWindowController.m" \
    "$PROJECT_DIR/Shared/Language.m" \
    "$PROJECT_DIR/Shared/ReleaseFeed.m" \
    "$PROJECT_DIR/Shared/utilities.m" \
    "$TEST_FILE" \
    -framework Foundation -framework AppKit \
    >> "$BUILD_LOG" 2>&1

build_exit=$?
error_count=$(grep -c 'error:' "$BUILD_LOG")

if [ $build_exit -ne 0 ] || [ "$error_count" != "0" ]; then
    echo "ERROR: build failed (exit=$build_exit, errors=$error_count)"
    cat "$BUILD_LOG"
    exit 1
fi

#every language the app ships is what the code catalog carries
LANGUAGES=$(python3 - "$CATALOG" <<'PY'
import json
import sys

strings = json.load(open(sys.argv[1]))["strings"]

languages = set()
for entry in strings.values():
    languages.update(entry.get("localizations", {}).keys())

print(" ".join(sorted(languages)))
PY
)

if [ -z "$LANGUAGES" ]; then
    echo "ERROR: the code catalog carries no languages"
    exit 1
fi

NIB="$BUNDLE/Contents/Resources/Base.lproj/Preferences.nib"
overall=0

for language in $LANGUAGES; do
    "$BUNDLE/Contents/MacOS/test_language" "$NIB" "$language" "$CATALOG" "$MUL_CATALOG" "$INFO_CATALOG"
    run_exit=$?

    if [ $run_exit -ne 0 ]; then
        overall=1
        echo "   ($language exit=$run_exit)"
    fi
done

echo
if [ $overall -eq 0 ]; then
    echo "RESULT: pass"
    rm -rf "$BUILD_DIR"
else
    echo "RESULT: fail"
    echo "   bundle kept for inspection: $BUNDLE"
fi

exit $overall
