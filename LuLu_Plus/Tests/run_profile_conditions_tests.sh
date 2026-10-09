#!/bin/bash
#
# file: run_profile_conditions_tests.sh
# description: builds and runs the add-profile wizard's network-conditions page against the real
#              conversion rules it is built on and the real interface types the extension reports,
#              in every language the fork translates
#
# usage: ./run_profile_conditions_tests.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TEST_FILE="$SCRIPT_DIR/test_profile_conditions.m"
CATALOG="$PROJECT_DIR/Shared/Localizable.xcstrings"

BUILD_DIR="${TMPDIR:-/tmp}/lulu_plus-profile-conditions-tests-$$"
BUNDLE="$BUILD_DIR/ConditionsTest.app"
BINARY="$BUNDLE/Contents/MacOS/test_profile_conditions"
BUILD_LOG="$BUILD_DIR/build.log"

#production sources under test
SOURCES=(
    "$PROJECT_DIR/Shared/ProfileConditions.m"
    "$PROJECT_DIR/App/ProfileConditionsViewController.m"
    "$PROJECT_DIR/Extension/NetworkContext.m"
    "$TEST_FILE"
)

for required in "${SOURCES[@]}" "$CATALOG"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: missing source: $required"
        exit 1
    fi
done

echo "== LuLu_Plus: profile network-condition tests =="
echo "   project: $PROJECT_DIR"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" || exit 1

#NSLocalizedString reads the main bundle, so the binary lives in one with the compiled strings
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>test_profile_conditions</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.profile-conditions-tests</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>ProfileConditionsTests</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
</dict>
</plist>
PLIST

#the strings the app ships, compiled from the real catalog
xcrun xcstringstool compile "$CATALOG" --output-directory "$BUNDLE/Contents/Resources" > "$BUILD_LOG" 2>&1
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

echo "   compiling $((${#SOURCES[@]} - 1)) production source(s) + the test"

xcrun clang \
    -fobjc-arc -fmodules \
    -isysroot "$SDK" \
    -mmacosx-version-min=12.0 \
    -I"$PROJECT_DIR/Shared" -I"$PROJECT_DIR/Extension" -I"$PROJECT_DIR/App" \
    -Wno-deprecated-declarations \
    -o "$BINARY" \
    "${SOURCES[@]}" \
    -framework Foundation -framework AppKit -framework SystemConfiguration \
    -framework CoreWLAN -framework CoreLocation \
    >> "$BUILD_LOG" 2>&1

build_exit=$?
error_count=$(grep -c 'error:' "$BUILD_LOG")

if [ $build_exit -ne 0 ] || [ "$error_count" != "0" ]; then
    echo "ERROR: build failed (exit=$build_exit, errors=$error_count)"
    cat "$BUILD_LOG"
    exit 1
fi

if [ ! -x "$BINARY" ]; then
    echo "ERROR: linker reported success but produced no binary"
    cat "$BUILD_LOG"
    exit 1
fi

echo "   build clean ($(wc -l < "$BUILD_LOG" | tr -d ' ') warning line(s))"
echo

overall=0

#the fork translates these three
for language in en zh-Hans zh-Hant; do
    "$BINARY" "$language"
    run_exit=$?

    if [ $run_exit -ne 0 ]; then
        overall=1
        echo "   ($language exit=$run_exit)"
    fi

    echo
done

if [ $overall -eq 0 ]; then
    echo "RESULT: pass"
    rm -rf "$BUILD_DIR"
else
    echo "RESULT: fail"
    echo "   bundle kept for inspection: $BUNDLE"
fi

exit $overall
