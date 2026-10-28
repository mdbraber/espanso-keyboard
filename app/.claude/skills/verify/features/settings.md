# Settings

## Sub-features

The app's settings screen (styled like Settings › General › Keyboard), the same switches in Settings › Apps › Hex, One-Handed Keyboard (Off/Left/Right), Keep Mic On (voice typing, Off to Until Turned Off), and Reset Keyboard Dictionary.

## How to get to it (user POV)

Hex app › Settings, or Settings › Apps › Hex.

## Driving it with XCUITest

`UITests/SettingsAppTests.swift` flips a switch in the Settings app and reads it in Hex; `SettingsAppTests.testKeepMicOnIsPickedInHexAndShownInSettings` picks a Keep Mic On value in Hex and finds it in Settings (screenshots with `TEST_RUNNER_HEX_SHOTS=<folder>`); `SuggestionTests.testAutoCorrectionSettingIsSharedWithTheKeyboard` checks the keyboard follows it. `-HexResetSettings YES` clears settings and the learned memory at launch.

## Gotchas

The keyboard reads settings in `viewWillAppear`, so a test must reopen the keyboard after changing one.
