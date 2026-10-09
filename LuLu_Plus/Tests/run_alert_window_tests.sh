#!/bin/bash
#
# file: run_alert_window_tests.sh
# description: compiles the real AlertWindow.xib and the real string catalog, loads them through
#              the app's AlertWindowController, and checks what an inbound prompt says (and hands
#              back to the extension) in every language the fork translates
#
# usage: ./run_alert_window_tests.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TEST_FILE="$SCRIPT_DIR/test_alert_window_direction.m"
XIB="$PROJECT_DIR/App/Base.lproj/AlertWindow.xib"
CATALOG="$PROJECT_DIR/Shared/Localizable.xcstrings"

BUILD_DIR="${TMPDIR:-/tmp}/lulu_plus-alert-tests-$$"
BUNDLE="$BUILD_DIR/AlertTest.app"
BUILD_LOG="$BUILD_DIR/build.log"

for required in "$TEST_FILE" "$XIB" "$CATALOG"; do
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
	<string>test_alert_window_direction</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.alert-window-tests</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>AlertTests</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
</dict>
</plist>
PLIST

echo "== LuLu_Plus: alert window direction tests =="
echo "   project: $PROJECT_DIR"

#the nib the app ships, compiled from the real xib
ibtool --compile "$BUNDLE/Contents/Resources/Base.lproj/AlertWindow.nib" "$XIB" > "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: ibtool failed to compile the xib"
    cat "$BUILD_LOG"
    exit 1
fi

#the strings the app ships, compiled from the real catalog
xcrun xcstringstool compile "$CATALOG" --output-directory "$BUNDLE/Contents/Resources" >> "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: could not compile the string catalog"
    cat "$BUILD_LOG"
    exit 1
fi

SDK="$(xcrun --show-sdk-path --sdk macosx)"
if [ -z "$SDK" ]; then
    echo "ERROR: could not locate the macOS SDK"
    exit 1
fi

echo "   compiling AlertWindowController (+ its popover controllers) and the test"

xcrun clang \
    -fobjc-arc -fmodules \
    -isysroot "$SDK" \
    -mmacosx-version-min=12.0 \
    -I"$PROJECT_DIR/Shared" -I"$PROJECT_DIR/App" \
    -Wno-deprecated-declarations \
    -o "$BUNDLE/Contents/MacOS/test_alert_window_direction" \
    "$PROJECT_DIR/App/AlertWindowController.m" \
    "$PROJECT_DIR/App/ParentsWindowController.m" \
    "$PROJECT_DIR/App/SigningInfoViewController.m" \
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

NIB="$BUNDLE/Contents/Resources/Base.lproj/AlertWindow.nib"
overall=0

#the fork translates these three
for language in en zh-Hans zh-Hant; do
    "$BUNDLE/Contents/MacOS/test_alert_window_direction" "$NIB" "$language"
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
