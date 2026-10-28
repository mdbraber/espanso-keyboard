# Every tap lands

## Sub-features

Fast typing at 200 and 1,000 wpm with nothing lost, taps in the gaps between keys and above the top row, the first tap after the keyboard opens, rollover (a held key commits when the next finger lands), keys looked up in the precomputed `KeyMap`, host reports that arrive late or cut off.

## How to get to it (user POV)

Type fast and sloppily in any field.

## Driving it with XCUITest

`UITests/FastTypingTests.swift` types a passage with XCTest's HID synthesizer. `UITests/FirstTapTests.swift` taps between keys and right after launch. In the package tests, `TouchReplayTests` replays overlapping fingers frame by frame through `KeyboardView`, and `TextStateStressTests` checks 3,000 seeded runs against a host like iOS's.

## Gotchas

iOS drops touches on fully transparent pixels of a third-party keyboard; `KeyboardInputView`'s 0.001 fill is what makes gap taps arrive, and `testTapsBetweenKeysType` fails without it. On a device, `TouchTrace` (see `TouchTrace.swift`) logs touch timing when its file exists.
