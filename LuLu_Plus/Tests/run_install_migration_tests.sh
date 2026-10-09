#!/bin/bash
#
# file: run_install_migration_tests.sh
# description: builds and runs the takeover of a previous install's data directory against the
#              real source, not a copy of it
#
# usage: ./run_install_migration_tests.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_FILE="$SCRIPT_DIR/test_install_migration.m"
BUILD_DIR="${TMPDIR:-/tmp}/lulu_plus-tests-$$"
BINARY="$BUILD_DIR/test_install_migration"
BUILD_LOG="$BUILD_DIR/build.log"

#production sources under test
SOURCES=(
    "$PROJECT_DIR/Shared/InstallMigration.m"
    "$TEST_FILE"
)

echo "== LuLu_Plus: install-migration tests =="
echo "   project: $PROJECT_DIR"

missing=0
for source in "${SOURCES[@]}"; do
    if [ ! -f "$source" ]; then
        echo "ERROR: missing source: $source"
        missing=1
    fi
done

if [ $missing -ne 0 ]; then
    exit 1
fi

mkdir -p "$BUILD_DIR" || exit 1

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
    -Wno-deprecated-declarations -Wno-unused-variable \
    -o "$BINARY" \
    "${SOURCES[@]}" \
    -framework Foundation \
    > "$BUILD_LOG" 2>&1

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

"$BINARY"
test_exit=$?

echo
if [ $test_exit -eq 0 ]; then
    echo "RESULT: pass"
else
    echo "RESULT: fail (exit=$test_exit)"
fi

# leave the log behind only when something went wrong
if [ $test_exit -eq 0 ]; then
    rm -rf "$BUILD_DIR"
else
    echo "   log: $BUILD_LOG"
fi

exit $test_exit
