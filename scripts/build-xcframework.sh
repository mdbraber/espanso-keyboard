#!/usr/bin/env bash
# Builds the core for the iPhone and the iPhone Simulator, generates the Swift bindings
# with UniFFI, and assembles EspansoKeyboardCoreFFI.xcframework inside the Swift package
# at swift/EspansoKeyboardCore/. Both outputs are generated, so git ignores them.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$repo/swift/EspansoKeyboardCore"
lib=libespanso_keyboard_core.a
targets=(aarch64-apple-ios aarch64-apple-ios-sim)

# Matches the Swift package's platforms in Package.swift.
export IPHONEOS_DEPLOYMENT_TARGET=17.0

cd "$repo/core"
rustup target add "${targets[@]}" >/dev/null
for target in "${targets[@]}"; do
  cargo build --release --target "$target"
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Bindings: the Swift file, plus a C header and module map for the XCFramework.
cargo run --quiet --features cli --bin uniffi-bindgen -- generate \
  --library "target/aarch64-apple-ios/release/$lib" \
  --language swift --out-dir "$work/bindings"

mkdir -p "$work/headers"
cp "$work/bindings/"*.h "$work/headers/"
cp "$work/bindings/"*.modulemap "$work/headers/module.modulemap"

rm -rf "$package/EspansoKeyboardCoreFFI.xcframework"
xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/release/$lib" -headers "$work/headers" \
  -library "target/aarch64-apple-ios-sim/release/$lib" -headers "$work/headers" \
  -output "$package/EspansoKeyboardCoreFFI.xcframework" >/dev/null

cp "$work/bindings/"*.swift "$package/Sources/EspansoKeyboardCore/Generated/"

echo "$package/EspansoKeyboardCoreFFI.xcframework"
ls "$package/Sources/EspansoKeyboardCore/Generated/"
