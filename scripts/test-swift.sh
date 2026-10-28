#!/usr/bin/env bash
# Builds the XCFramework and runs the Swift package's tests in the iPhone Simulator.
# SIMULATOR names the device (see `xcrun simctl list devices available`); extra arguments
# go to xcodebuild. The full log is in build/test-swift.log.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulator="${SIMULATOR:-iPhone 18 Pro}"

"$repo/scripts/build-xcframework.sh"

mkdir -p "$repo/build"
cd "$repo/swift/EspansoKeyboardCore"
xcodebuild test \
  -scheme EspansoKeyboardCore \
  -destination "platform=iOS Simulator,name=$simulator" \
  -derivedDataPath "$repo/build/swift" \
  -collect-test-diagnostics never \
  "$@" 2>&1 | tee "$repo/build/test-swift.log" | grep -E "error:|Test Case .*(passed|failed)|MEMORY|Executed|\*\* TEST"
