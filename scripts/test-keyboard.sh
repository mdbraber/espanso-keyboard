#!/usr/bin/env bash
# Builds the keyboard (app/) with the Rust core and runs its snippet UI tests in the iPhone Simulator, with Hex as
# the active keyboard. SIMULATOR names the device; extra arguments go to xcodebuild (default: only SnippetTests).
# The full log is in build/test-keyboard.log.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulator="${SIMULATOR:-iPhone 18 Pro}"

mkdir -p "$repo/build"
"$repo/scripts/build-xcframework.sh" >"$repo/build/xcframework.log" 2>&1 || { cat "$repo/build/xcframework.log"; exit 1; }
cd "$repo/app"
xcodegen generate --quiet

keyboard=$(xcodebuild -project HexKeyboard.xcodeproj -target Keyboard -showBuildSettings 2>/dev/null |
  awk '$1 == "PRODUCT_BUNDLE_IDENTIFIER" { print $3 }')
udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
print(next(d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name'] == sys.argv[1]))" "$simulator")

# Hex first in the keyboard list, as app/scripts/sim does; the Simulator reads the list when it boots.
xcrun simctl bootstatus "$udid" -b >/dev/null
current=$(xcrun simctl spawn "$udid" defaults read .GlobalPreferences AppleKeyboards 2>/dev/null || true)
if [[ "$current" != *"$keyboard"* ]]; then
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboards -array "$keyboard" "en_US@sw=QWERTY;hw=Automatic"
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboardsExpanded -int 1
  xcrun simctl shutdown "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
fi

[ $# -gt 0 ] || set -- -only-testing:HexUITests/SnippetTests
xcodebuild test \
  -project HexKeyboard.xcodeproj -scheme Hex \
  -destination "id=$udid" \
  -derivedDataPath "$repo/build/app-test" \
  -collect-test-diagnostics never \
  "$@" 2>&1 | tee "$repo/build/test-keyboard.log" | grep -E "error:|Test Case .*(passed|failed)|Executed|\*\* TEST"
