---
name: verify
description: Prove a change to Hex Keyboard works the way a user meets it. Builds on the Mac, runs KeyboardCore's unit and stress tests, types through the real keyboard extension in a headless simulator, checks autocorrect accuracy against scripts/eval.expected, and captures screenshots. Use before calling any change to the keyboard, the engine, the web demo or the app done.
---

# Verify Hex Keyboard

Everything builds and runs on the Mac (`ssh mac`). From this checkout, `scripts/mac '<command>'` syncs the tree to `~/Developer/hex-keyboard` on the Mac, runs the command there, and copies `shots/raw/` back. Bassim may be using the Mac at the same time: simulators boot headless, and Simulator.app and Xcode stay closed.

## Launch

`scripts/mac scripts/build` generates the project and builds the app and extension for the simulator. It is ready when it exits 0, which means `Keyboard.appex` exists. UI-test scripts create their own `hexkb …` simulators (`scripts/sim ensure`), install the app and turn the extension on by writing `AppleKeyboards`, so no Settings UI is involved.

## Doctor

`ssh mac 'xcodebuild -version | head -1; xcrun simctl list devices | grep hexkb'` shows the Xcode the build uses and which Hex simulators exist and are booted. A build that fails with a signing error for a device means `Config/Team.xcconfig` is missing on the Mac; simulator builds never need it.

## Drive

Pick by what changed, and run every row that applies.

| Change touches | Run | Passes when |
| --- | --- | --- |
| anything in `KeyboardCore` | `scripts/mac scripts/test` | both `Test run with N tests … passed` lines print. `TextStateStressTests` (3,000 seeded runs against a host that reports late and cut off) is one of them. |
| the decoder, models, key map, autocorrect or what a touch types | `scripts/mac scripts/eval` | it ends with `EVAL matches eval.expected`. A change that moves the numbers must beat them and updates `scripts/eval.expected` in the same commit. |
| anything a user touches | `scripts/mac scripts/uitest`, and `scripts/mac "scripts/uitest 'iPad Pro 11' iPad-Pro-11-inch-M5-12GB"` for iPad | every `Test Case … passed`, none failed. |
| how keys look | `scripts/mac 'scripts/sim all <tag>'`, then `uv run --with pillow --with numpy --with scipy scripts/shotdiff.py <tag>` | key rects match Apple's within half a point, light and dark. |
| the app's Your Taps screen or what it shows | `scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max <touches.json> <tag>'` | the fourteen screenshots in `shots/raw/` read right, light and dark. |
| voice typing (the bar's mic, `Dictation`, `Listener`'s signals) | `scripts/mac scripts/voicetest` | `VoiceTests … passed` for light and dark, and `shots/raw/voice/` shows the mic idle, listening, the typed text and the mic gone. |
| the web demo | sync `web/` to the Mac and run `scripts/web` there | it builds `web/dist`; open `web/dist/index.html` through a local server and type. |

The feature map in `features/` lists each feature, how a user reaches it, and the test that drives it.

## Evidence

Quote the summary lines each command prints: the test counts, the `EVAL` diff or match line, the UI test cases. Screenshots land in `shots/raw/` on both machines. A proof exercises the real path (taps through the extension, the engine through `handle`), not internal setters.

## Cleanup

`scripts/eval`, `scripts/memory`, `scripts/shots` and `scripts/sim all` shut down the simulators they booted. `scripts/test` and `scripts/uitest` leave theirs booted for the next run; shut them down with `ssh mac 'xcrun simctl shutdown <id>'` when done. Shut down only `hexkb` simulators, by id, never Simulator or Xcode by name. Screenshots stay in `shots/raw/`.

## Gotchas

- The simulator merges overlapping synthesized fingers into one sliding finger, so overlap at speed is covered by `TouchReplayTests` (package tests), not by `FastTypingTests`.
- `scripts/eval` runs a Release build; the decoder is too slow in Debug for the numbers to finish in reasonable time.
- Run one xcodebuild test at a time per simulator; two runs on the same `hexkb` device collide.
