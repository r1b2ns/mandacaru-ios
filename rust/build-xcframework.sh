#!/usr/bin/env bash
# Builds floresta-ffi as an XCFramework for iOS (device + simulator).
#
# Output: ../Floresta/FlorestaFFI.xcframework
#
# Slices:
#   - ios-arm64           (device)
#   - ios-arm64_x86_64-simulator   (fat: Apple Silicon + Intel sim)
#
# Requirements:
#   - rustup targets: aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios
#   - cbindgen on PATH
#   - Xcode command-line tools (xcodebuild, lipo)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CRATE_NAME="floresta-ffi"
LIB_NAME="libfloresta_ffi.a"
FRAMEWORK_NAME="FlorestaFFI"
OUT_DIR="$SCRIPT_DIR/../Floresta"
HEADER_DIR="$SCRIPT_DIR/include"
SIM_FAT_DIR="$SCRIPT_DIR/target/sim-universal/release"

echo "==> Regenerating C header via cbindgen..."
cbindgen --config "$CRATE_NAME/cbindgen.toml" --crate "$CRATE_NAME" --output "$HEADER_DIR/floresta_ffi.h" --quiet

echo "==> Building for aarch64-apple-ios (device)..."
cargo build -p "$CRATE_NAME" --release --target aarch64-apple-ios

echo "==> Building for aarch64-apple-ios-sim (simulator arm64)..."
cargo build -p "$CRATE_NAME" --release --target aarch64-apple-ios-sim

echo "==> Building for x86_64-apple-ios (simulator x86_64)..."
cargo build -p "$CRATE_NAME" --release --target x86_64-apple-ios

DEVICE_LIB="$SCRIPT_DIR/target/aarch64-apple-ios/release/$LIB_NAME"
SIM_ARM_LIB="$SCRIPT_DIR/target/aarch64-apple-ios-sim/release/$LIB_NAME"
SIM_X86_LIB="$SCRIPT_DIR/target/x86_64-apple-ios/release/$LIB_NAME"

for lib in "$DEVICE_LIB" "$SIM_ARM_LIB" "$SIM_X86_LIB"; do
    [ -f "$lib" ] || { echo "Error: missing $lib" >&2; exit 1; }
done

mkdir -p "$SIM_FAT_DIR"
SIM_FAT_LIB="$SIM_FAT_DIR/$LIB_NAME"

echo "==> Lipo'ing simulator slices (arm64 + x86_64)..."
lipo -create "$SIM_ARM_LIB" "$SIM_X86_LIB" -output "$SIM_FAT_LIB"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$FRAMEWORK_NAME.xcframework"

echo "==> Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB"  -headers "$HEADER_DIR" \
    -library "$SIM_FAT_LIB" -headers "$HEADER_DIR" \
    -output "$OUT_DIR/$FRAMEWORK_NAME.xcframework"

echo
echo "==> Done."
echo "    Device   : $(du -h "$DEVICE_LIB"  | cut -f1)  $DEVICE_LIB"
echo "    Sim arm  : $(du -h "$SIM_ARM_LIB" | cut -f1)  $SIM_ARM_LIB"
echo "    Sim x86  : $(du -h "$SIM_X86_LIB" | cut -f1)  $SIM_X86_LIB"
echo "    Sim fat  : $(du -h "$SIM_FAT_LIB" | cut -f1)  $SIM_FAT_LIB"
echo "    Output   : $OUT_DIR/$FRAMEWORK_NAME.xcframework"
