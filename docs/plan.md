# Plan

Steps in order. Each ends with a check that shows it's done. Steps 1 to 3 need no iPhone
and no signing, so they can run entirely in gloob.

## Step 0: Environment

Follow [build-on-gloob.md](build-on-gloob.md), "One-time setup" and "Check the setup".

Then confirm the Simulator works inside gloob: create any iOS app template with Xcode,
build it for the Simulator and launch it with `xcrun simctl`. If the Simulator doesn't
run in the virtual machine, record that in this file. Steps 1 to 3 don't need it;
steps 3 (Swift tests) and 4 onwards would then run their Simulator checks on the Mac.

**Done when:** `scripts/check-ios.sh` passes, `bun fixtures/espanso/scripts/jitsi.js`
prints a room name, and the Simulator question is answered.

**Result (2026-10-28): done.**

- Versions: macOS 27.0 (26A428), Xcode 27.1 (27A9275), Apple clang 21.0.0, iOS Simulator
  runtimes 27.0 and 27.1; rustup 1.29.2, rustc and cargo 1.99.1 with the
  `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets; XcodeGen 2.46.0, Bun 1.4.3,
  just 1.59.0 (Homebrew).
- `scripts/check-ios.sh` passes: 2 core tests, then both iPhone builds. The release
  static library is 31 MB for each target. A first run, including downloading and
  building all crates, took about 50 seconds.
- `bun fixtures/espanso/scripts/jitsi.js 10` prints a 10-character room name.
- **The Simulator works in gloob.** A throwaway SwiftUI app (made with XcodeGen, kept
  outside the repository) built with `xcodebuild -sdk iphonesimulator`, installed with
  `xcrun simctl install` and ran with `xcrun simctl launch --console-pty` on an
  iPhone 18 Pro Simulator (iOS 27.1). Its console output came through, and
  `simctl io screenshot` showed its screen. Booting the device the first time took
  about 1.5 minutes. Simulator checks in steps 3 and 4 can run in gloob.
- Differences from the instructions: the Xcode licence and the iOS platform were already
  in place; gloob has 28 GB of memory, not 16 GB; rustup's PATH change needs a new shell
  or `source "$HOME/.cargo/env"`. [build-on-gloob.md](build-on-gloob.md) is updated.

## Step 1: Expansion engine in Rust

In `core/`, build the engine that turns typed characters into expansions, using Espanso's
libraries. No JavaScript yet; script variables return an error.

1. **Load:** `espanso_config::load` (already used in `core/src/lib.rs`). Use the default
   configuration's match paths; keyboards can't see which app they're in, so app-specific
   configurations are ignored.
2. **Match:** build an `espanso_match::rolling::matcher::RollingMatcher` from the loaded
   matches. Espanso's own conversion from config matches to matcher input is in the
   Espanso repository at `espanso/src/cli/worker/engine/process/middleware/matcher/`
   (`convert.rs`, `rolling.rs`); copy and adapt it. Feed each typed character as
   `Event::Key { key: Key::Other, chars: Some(..) }`, and use `Event::VirtualSeparator`
   from `reset()`. Respect `word: true`, `left_word`, `right_word`,
   `propagate_case` and the configuration's `word_separators`.
3. **Render:** create a renderer with `espanso_render::create`, with the date, echo,
   random and choice extensions. Converting matches into renderer templates is also done
   in the Espanso repository, in `espanso/src/cli/worker/engine/process/middleware/render/`;
   copy and adapt it. Nested matches and global variables come along with that code.
4. **Expansion result:** delete count (the trigger's length in characters as the text
   field counts them; test with emoji and accented letters), the text to insert, and the
   cursor offset for `$|$`.
5. **Undo:** when `undo_backspace` is on and the very next key after an expansion is
   backspace, return an expansion that removes the inserted text and puts the trigger back.
6. **Interface:** the `EspansoEngine` from [architecture.md](architecture.md), still as a
   plain Rust API.

**Tests** (in `core/tests/`, using `fixtures/espanso/`, extended as needed):
- `;today` expands to today's date.
- A `word: true` trigger only fires between word separators.
- `$|$` gives the right cursor offset.
- Backspace after an expansion restores the trigger; any other key first means it doesn't.
- `reset()` mid-trigger stops the trigger from firing.
- Matches from `_` files are skipped unless imported, and imported ones work.
- Triggers containing non-ASCII characters give the right delete count.

**Done when:** these tests pass and `scripts/check-ios.sh` still passes.

**Result (2026-10-28): done.** `EspansoEngine` is in `core/src/engine.rs`; the code
copied from Espanso is in `core/src/espanso.rs`. `core/tests/engine.rs` has 20 tests (all
of the above plus nested matches, global variables, `propagate_case`, backspace while
typing a trigger, `undo_backspace: false`, choice, search and unsupported snippets). They
run through a simulated text field that applies each expansion as the keyboard will.
`scripts/check-ios.sh` passes. The release static library grew from 31 MB to 40 MB with
the renderer linked in.

How it follows Espanso, and where it differs:

- Each step follows the Espanso middleware it is named after (matcher, cause
  compensation, render, cursor hint, undo, action); comments in `engine.rs` name them.
- Call order: the keyboard inserts a typed character and then calls `type`, so the
  trigger is in the text field when it is replaced, as on the Mac. It calls `backspace`
  *before* deleting; an expansion returned then replaces the normal delete (Espanso
  instead deletes one character fewer, because the backspace already deleted one).
- Delete counts and cursor offsets are in grapheme clusters, one per `deleteBackward`.
  Espanso counts Unicode scalars for deleting, which differs only for triggers with
  combined characters such as `👍🏽`.
- `reset()` clears the matcher state and undo, as Espanso does for a mouse click, rather
  than feeding a `VirtualSeparator`. Both stop a trigger in progress; clearing also
  forgets the backspace history, which no longer fits the text after a cursor move.
- Text after a trigger in the same key press (a `.com` key) is deleted and inserted again
  after the expansion; only the first expansion in one key press is applied.
- A failed render doesn't expand and is available as `last_error()`. Espanso on the Mac
  types "[Espanso]: An error occurred during rendering…" instead.
- Markdown, HTML and image snippets aren't expanded, and regex triggers wait for step 6;
  each is listed in `warnings`. `choice` variables cancel the snippet until there is a
  picker (step 6).
- `type` is named `type_text` in Rust (`type` is a keyword); the Swift name can be set in
  step 3.

Questions raised, and how they were settled:

- **Undo of a `word: true` trigger doubled the left separator**, as Espanso does on the
  Mac (`espanso-engine/src/process/middleware/action.rs`). Fixed in the keyboard only, on
  the owner's decision; see [decisions.md](decisions.md). Test:
  `undo_of_a_word_trigger_keeps_the_left_separator_single`.
- **Several snippets with the same trigger**: the keyboard takes the first; accepted by the
  owner (decisions.md).
- **Cursor offset units** (open): `adjustTextPosition(byCharacterOffset:)` may count UTF-16
  units rather than grapheme clusters. Check in step 4 with an emoji after `$|$`.

## Step 2: Script variables in Rust

1. Add a replacement `script` extension in `core/` that follows
   [script-contract.md](script-contract.md): checks the arguments, fills in `%CONFIG%` and
   `%HOME%`, builds `argv` and `env` (reuse the `ESPANSO_<NAME>` conversion from
   `espanso-render/src/extension/util.rs`), calls a `ScriptRunner` supplied by the host,
   and applies `trim`, `ignore_error` and `debug` the way Espanso's
   `espanso-render/src/extension/script.rs` does.
2. Register it instead of Espanso's script extension. Leave Espanso's `shell` extension
   out, so `shell` variables fail cleanly.

**Tests:** with a test `ScriptRunner` in Rust: the `;jitsi` fixture calls it with
`argv == ["bun", "<fixture>/scripts/jitsi.js", "10"]`; earlier variables appear in `env`;
error output fails the snippet unless `ignore_error: true`; `trim: false` keeps whitespace;
`[bash, x.sh]` and `[bun, x.ts]` are rejected.

**Done when:** these tests pass.

**Result (2026-10-28): done.** The extension is `core/src/script.rs`, adapted from
Espanso's `script.rs` with `convert_to_env_variables` copied from `util.rs` (private in
Espanso). `core/tests/scripts.rs` has 10 tests: the ones above, plus a thrown error,
`ignore_error`, `%HOME%`, `node` and `deno`, `%PACKAGES%` and `shell`. The fixture gained
`;hallo` with `scripts/greet.js`, which runs under Bun too. `EspansoEngine::new` now takes
the `ScriptRunner`.

- `ScriptRunner.run` returns standard output, error output and success separately
  instead of a single string, so `ignore_error` can keep the output as Espanso does.
  An error from `run` means the script couldn't run at all; like Espanso failing to start
  the program, that fails the snippet even with `ignore_error`.
- `debug: true` logs through the `log` crate, as Espanso does; nothing shows it until the
  keyboard installs a logger.
- `%PACKAGES%` is rejected with an error rather than left in the path.

## Step 3: Swift package with JavaScriptCore

1. Expose the engine through UniFFI (procedural macros, no separate interface file), with
   `ScriptRunner` as a callback interface.
2. Add `scripts/build-xcframework.sh`: builds the core for `aarch64-apple-ios` and
   `aarch64-apple-ios-sim`, generates the Swift bindings, and assembles
   `EspansoKeyboardCore.xcframework`.
3. Add a Swift package in `swift/EspansoKeyboardCore/` that wraps the XCFramework and the
   generated Swift file, plus a `JavaScriptCoreScriptRunner`: loads the file, sets up
   `process.argv`, `process.env` and `console`, runs the script in a fresh `JSContext` on
   a background queue, and stops waiting after about one second.
4. Measure: the size the core adds to a linked app (the static library is about 31 MB
   before linking; most of that should be stripped), and the memory used after `load` with
   the fixture and with the owner's real Espanso folder.

**Tests** (Swift, in the Simulator): the fixture's `;jitsi` expands to
`https://meet.jit.si/mdb-` plus 10 characters; a script that loops forever fails the
snippet within about one second without blocking the test; `console.error` fails the
snippet.

**Done when:** these tests pass and the size and memory numbers are written into this
file. If memory after loading is above about 30 MB, stop and discuss before step 4.

**Result (2026-10-28): done, except measuring the owner's real Espanso folder.**

- UniFFI 0.32.2 with procedural macros, in `core/src/ffi.rs`: a thin wrapper around the
  Rust `EspansoEngine` behind a mutex, with `ScriptRunner` as a callback interface. Swift
  sees `EspansoEngine(configFolder:scriptRunner:)`, `typeText(text:)`, `backspace()`,
  `reset()`, `search(query:)`, `warnings()` and `lastError()`. The bindings are generated
  directly from the iPhone static library; `uniffi-bindgen` is a binary in `core/` behind
  the `cli` feature, so the library doesn't build the generator's dependencies for the
  iPhone.
- `scripts/build-xcframework.sh` builds both targets (iOS 17.0 minimum), generates the
  bindings and writes `EspansoKeyboardCoreFFI.xcframework` and the generated Swift file
  into `swift/EspansoKeyboardCore/`. Both are ignored by git, so run the script before
  building the package. `scripts/test-swift.sh` runs it and then the Swift tests.
- `swift/EspansoKeyboardCore/` (Swift 6, iOS 17) has `JavaScriptCoreScriptRunner` and
  its tests, run in the iPhone 18 Pro Simulator: `;jitsi` gives a new 10-character room each
  time; earlier variables reach the script; an endless loop fails the snippet after
  1.0 seconds and a second engine still works meanwhile; `console.error`, a thrown error
  and a missing file fail the snippet; `console` output matches Bun's for the cases in
  the script contract; memory.
- **Size:** the static library is 41 MB, but a release iPhone app linking the package
  grows by 4.7 MB (4.1 MB with symbols stripped, as in an archive): about 1.7 MB of code
  and 1.4 MB of constant data, much of which is probably the time zone and locale tables
  of the date extension.
- **Memory** (Simulator, test run on its own, phys_footprint): loading the fixture adds
  0.05 MB, and a generated folder of 2000 snippets 0.4 MB. The first script run adds
  3.9 MB for JavaScriptCore; 20 more runs add 0.2 MB. Well under 30 MB. The owner's real
  folder isn't in gloob: copy it to a temporary folder outside the repository and pass
  it to the memory test, or measure on the iPhone in step 4.
- Runaway scripts are stopped with JavaScriptCore's non-public
  `JSContextGroupSetExecutionTimeLimit` (owner's decision, see decisions.md); before that,
  a script that never ended kept a CPU core busy until the keyboard was stopped. The
  runner still stops waiting after 1 second, so typing is never held longer, but the stop
  itself isn't precise. Measured in gloob's Simulator with a 1-second limit, five runs
  each, one at a time: `for (;;) {}` 7.1 s the first time, then 1.1 s; a loop doing
  `i++` 1.1–1.2 s; a loop building strings 5.6–8.4 s, probably because garbage collection
  time doesn't count. Every run was stopped. Test: `testARunawayScriptFailsWithinAboutASecond`
  checks the script's thread ends, and `testTheTimeLimitCannotBeIgnored` that
  `ignore_error` doesn't keep a timed-out script's output. 9 Swift tests in total.

## Step 4: Keyboard

1. Bring Hex into `app/` with `git subtree add --prefix app
   https://github.com/AVGVSTVS96/hex-keyboard.git main --squash`, so upstream changes can
   be pulled later with `git subtree pull`.
2. Hex keeps its signing settings in `app/Config/Signing.xcconfig` and its identifiers
   (`com.shahidy.hexkeyboard` and its app group) in the project and in
   `app/App/Hex.entitlements` and `app/Keyboard/Keyboard.entitlements`. Make all of these
   come from `Config/Local.xcconfig`, which is not committed, with a committed
   `Config/Local.xcconfig.example`. Signing uses Xcode's signed-in account in gloob
   ([build-on-gloob.md](build-on-gloob.md), "Signing").
3. Install it on the iPhone unchanged and have the owner type with it for a day,
   including Dutch. **Stop here if the owner isn't happy with the typing.** Reconsider
   the host keyboard (see [decisions.md](decisions.md)) before going further.
4. Add the `EspansoKeyboardCore` package to the keyboard target and connect it where Hex
   inserts text: pass each typed character to `type`, apply returned expansions through
   `textDocumentProxy` (`deleteBackward` repeated, `insertText`,
   `adjustTextPosition(byCharacterOffset:)` for the cursor), pass backspace to `backspace`,
   and call `reset` from `textDidChange`, `selectionDidChange` and when the keyboard
   appears.
5. Temporarily load the snippets bundled into the keyboard from `fixtures/espanso/`.

**Done when:** in the Simulator and on the iPhone, typing `;jitsi` in Notes and in a
Fantastical event gives a new meeting link each time, `;today` gives the date, and normal
typing and autocorrect feel unchanged.

**Progress (2026-10-28):** items 1 and 2 done.

- Hex is in `app/` from upstream commit `4d048b2` (squashed subtree).
- Hex builds with XcodeGen: `cd app && xcodegen generate`, then build the `Hex` scheme.
  Its deployment target is iOS 26, so the iPhone needs iOS 26 or later.
- Identifiers: `app/Config/Signing.xcconfig` includes the repository's
  `Config/Local.xcconfig` (example: `Config/Local.xcconfig.example`), which sets
  `DEVELOPMENT_TEAM`, `APP_BUNDLE_ID` and `APP_GROUP_ID`. Without it, Simulator builds use
  `com.example.espansokeyboard`. The bundle IDs, URL name and entitlements use these
  settings. The app group reaches the Swift code through a `HexAppGroup` Info.plist key
  (`SettingsStore.appGroup`), and a build script sets it in the built `Settings.bundle`;
  that script needs `ENABLE_USER_SCRIPT_SANDBOXING = NO` on the Hex target only.
- Left unchanged in Hex, as they only matter for Hex's own development: its `scripts/`,
  UI tests and `xtool.yml` still name `com.shahidy.hexkeyboard`, and its logs still use
  that subsystem.
- Checked: the Simulator build has the bundle IDs and app group from the settings in both
  Info.plists, both entitlements and `Settings.bundle`, and Hex launches.
- Bundle ID `com.mdbraber.espansokeyboard` (keyboard `.keyboard`, app group
  `group.com.mdbraber.espansokeyboard`), chosen by the owner to match their other apps.
  The signed device build (`xcodebuild … -configuration Release -destination
  'generic/platform=iOS' -allowProvisioningUpdates build`) registered them through Xcode's
  account; both targets got team provisioning profiles, 18 MB app.
- Installed on the owner's iPhone (iOS 27.0) directly from gloob with
  `xcrun devicectl device install app`; the iPhone is paired with Xcode in gloob over the
  local network, contrary to what build-on-gloob.md said (now corrected).
- Item 3: the owner tried it on the iPhone and gave the go-ahead (2026-10-28) without the
  full day of typing.

Items 4 and 5 (2026-10-28):

- Hex's `KeyboardUI` got a `TextExpander` protocol and an `expander` property on
  `HexKeyboardViewController`, so Hex's package doesn't depend on the Rust core. The
  `Keyboard` target sets it to `EspansoExpander` (`app/Keyboard/EspansoExpander.swift`),
  which loads the test snippets in `fixtures/espanso/`, bundled into the keyboard as
  `espanso/`.
- What the engine is told: after each key Hex handles, the view controller compares Hex's
  copy of the text before the caret with what it was. Text added at the caret is passed
  to `type`. If Hex also changed earlier text (autocorrect on a word ender, a smart dash,
  the double-space period), the engine is reset first and then gets the added text, as
  the trigger in progress no longer matches the field. So the engine matches what is in
  the field, including smart quotes, not the raw key presses as Espanso on the Mac does.
  Backspace asks the engine first; a returned undo replaces Hex's delete. Suggestions,
  emoji, dictation, cursor moves and changes reported by the host reset the engine.
- Expansions are applied through a new `TypingEngine.replace(_:with:movingBack:in:)`, so
  Hex's own copy of the text, autocapitalization and suggestions stay right.
- Simulator builds exclude x86_64, as the Rust core is built for Apple silicon only.
- `scripts/test-keyboard.sh` builds everything, makes Hex the Simulator's active keyboard
  and runs `app/UITests/SnippetTests.swift`: `;today`, `;jitsi` (script through
  JavaScriptCore), backspace undo, `$|$`, a `word: true` trigger after a space, and
  ordinary typing with autocapitalization and the double-space period. All 6 pass, and
  Hex's own `TypingTests` still pass (9, plus 1 skipped as iPad-only):
  `scripts/test-keyboard.sh -only-testing:HexUITests/TypingTests`.
- **Done (2026-10-28):** the owner confirmed the snippets work on the iPhone, installed
  from gloob; the Simulator checks are the UI tests above.
- Known limits: `type` runs on the main thread, so a slow script holds the keyboard for
  up to the 1-second limit (architecture.md suggests a background thread; not needed for
  the fixture scripts, which take milliseconds). A `word: true` trigger that Hex
  autocorrects when the word ends no longer matches.

## Step 5: Companion app import

1. In the Hex app, add a screen to pick the Espanso folder from iCloud Drive with a folder
   picker, remembered as a security-scoped bookmark.
2. On app launch and on "Reload", copy `config/`, `match/` and `scripts/` from it into the
   app group storage, replacing the previous copy in one step (copy to a new folder, then
   swap), so the keyboard never sees half a copy. Show Espanso's loading warnings.
3. The keyboard loads from the app group copy instead of the bundled fixtures and reloads
   when the copy changes (check the folder's modification date when the keyboard appears).

**Done when:** a snippet added on the Mac in Espanso's folder works on the iPhone after
opening the app, and also still works in Espanso on the Mac.

**Progress (2026-10-28):** items 1 to 3 built; the "Done when" check needs the owner's
folder on the iPhone.

- Keyboard Settings has an "Espanso" section, above "Sources" (owner's choice), opening
  `EspansoViewController`: pick
  the folder (document picker for folders, kept as a bookmark), Reload, the number of
  snippets and when they were copied, and Espanso's warnings.
- `EspansoImport` (`app/App/`) copies `config/`, `match/` and `scripts/` file by file
  through a file coordinator, so iCloud Drive downloads files first, into
  `<app group>/Espanso/<UUID>/`. It loads the copy as the keyboard will, to collect
  warnings and refuse a folder that doesn't load. Then it points the `current` symbolic
  link at it with one `rename` and removes all but the two newest copies; the one before
  may still be read by an open keyboard. Hex copies again each time it becomes active,
  and on Reload.
- The keyboard resolves `current` (`app/Shared/EspansoLibrary.swift`) when it appears and
  reloads when it points somewhere new; this replaces checking the folder's modification
  date. The fixture is no longer bundled into the keyboard.
- UI tests: Debug builds take `-EspansoImport <folder>`, so `SnippetTests` copy
  `fixtures/espanso/` through the same code before typing. A seventh test checks the
  Espanso screen. All 7 pass.
- In the Simulator the keyboard reads the app group without Full Access; whether the
  iPhone allows that is to be seen (architecture.md assumes Full Access is needed).
- Once, every keyboard stopped appearing in the Simulator, Apple's included, until the
  device was erased (`xcrun simctl erase`). The first run after that missed one
  expansion, probably first-boot timing; the reruns passed.

## Step 6: Features

Approved by the owner (2026-10-28) from a review of other text expansion keyboards and
apps (TextExpander, SnipKey, WordBoard, Raycast, Typinator, TypeIt4Me, Text Blaze, aText,
and the Android apps for Espanso files). Numbers are those of the review; secure
snippets (13) were not approved.

1. Tap a snippet in the list to copy its result (part of 11).
2. A switch to turn expansion off.
3. Forms and `choice` variables, in a panel inside the keyboard.
4. `clipboard` variables.
5. Fuzzy search.
6. Add snippets on the iPhone (`match/iphone.yml`) and edit existing ones in place; see
   decisions.md.
7. Matching snippets in Hex's suggestion bar while typing a trigger.
8. A snippet panel in the keyboard: search and tap to insert.
9. Favourites, first in the panel.
10. The snippet list grouped by match file.
11. A detail screen per snippet: triggers, file, text, variables, a preview, copy.
12. Usage counts per snippet, kept on the phone.
- Espanso snippets take precedence over iOS Text Replacements (decisions.md).

**Result (2026-10-28): all built.**

- Engine (`core/`): `choice` and `form` variables ask instead of blocking. The engine
  renders with a `Prompter` that answers from the answers so far and records the first
  question it can't, returns that `Prompt`, and renders again once it is answered
  (`src/prompt.rs`). `clipboard` reads a host `Clipboard`. `insert_snippet` expands a
  snippet by id, `preview` renders with default answers, `complete` finds triggers the
  text before the caret has begun (two characters, or three at a word start for
  triggers starting with a letter). Snippets carry their id, match file, raw text and
  variables; each expansion names its snippet. Editing (`src/edit.rs`): find one
  snippet's lines by its first trigger or regex (parsing just that item with
  `serde_norway`, Espanso's YAML library), replace them, or append a new snippet;
  nothing else in the file changes. 59 Rust tests.
- Hex: small hooks only. `TextExpander` gained completions, accepting one, reserving
  Text Replacement shortcuts and the snippets button. `HexKeyboardViewController` gained
  a panel above the suggestion bar, `keyCapture` (the keys type into the panel), and
  `applyExpansion`. The suggestion bar gained a snippets button at its left end; snippet
  completions take the bar from word suggestions. Text Replacements whose shortcut is a
  trigger are left out of the corrector (decisions.md).
- Keyboard: snippet panel (favourites, then by match file; fuzzy search typed with the
  keys; return inserts the best match), choice panel, form panel (text fields typed with
  the keys, choice fields cycle with a tap), clipboard through `UIPasteboard`, usage
  counts in `<app group>/Espanso/usage.json`, the on/off switch.
- App (Keyboard Settings › Espanso Snippets): Expand Snippets switch; one page per
  match file (the owner's request, so a large folder isn't one endless list), with fuzzy
  search across all files on the main screen and within a file on its page, and
  "used N×"; a detail screen with triggers, file, text,
  variables, preview, Copy Result, Favourite and usage; Add Snippet (to
  `match/iphone.yml`); Edit Snippet (its YAML lines). Edits are tried on a scratch copy
  and refused when Espanso reports new warnings, then written through a file coordinator
  and the folder is copied again.
- UI tests (`scripts/test-keyboard.sh`): `SnippetTests` (8) and `FeatureTests` (11)
  pass. `testASnippetWinsOverATextReplacement` adds a Text Replacement `brb` in Settings
  and checks Espanso's `brb` wins; with the fix switched off it fails as it should. They copy the fixture to `build/ui-espanso` first, so edits never touch
  `fixtures/`. `-EspansoImport` (Debug only) also resets the switch, favourites and
  counts.
- Hex's checks (its `app:verify` skill, run locally instead of over `ssh mac`): package
  tests pass (10 and 129, including the 3,000-run `TextStateStressTests`); `scripts/eval`
  ends with `EVAL matches eval.expected`; Hex's own UI tests pass (20, one skipped as
  iPad-only). Hex's `scripts/sim use hex` enables the keyboard under Hex's original
  bundle ID, so its UI tests run through `scripts/test-keyboard.sh` instead.
- Not tested automatically: a real change through the YAML editor in the UI (the Rust
  tests cover the text change; typing YAML indentation through Hex's keys runs into its
  double-space period).

Earlier list, kept for reference:
- `clipboard` variables through `UIPasteboard`.
- ~~Regex triggers (`espanso_match::regex`).~~ Done 2026-10-28, after the owner's first
  folder turned out to use them: Espanso's regex matcher runs beside the trigger matcher
  with its states in the same backspace history, trigger matches first; named groups
  become `echo` variables before the snippet's own, as in Espanso's renderer adapter, so
  scripts get them as `ESPANSO_<NAME>`. A regex that doesn't compile is a warning (Espanso
  only logs it). Tests: 6 in `core/tests/engine.rs`, 1 in `scripts.rs`, and
  `testRegexTriggerUsesItsNamedGroup` through the keyboard.
- Forms and `choice` variables, shown in the keyboard's own panel.
- Matching snippets in Hex's suggestion bar, using `search`.
- `import` between script files (a JavaScriptCore module loader limited to `scripts/`).

## Step 7: Dutch

Requested by the owner (2026-10-29): Dutch next to English, with autocorrect, suggestions
and predictions, switched inside the keyboard. Hex's typing was good enough to build on
(owner, same day), so this is an addition to Hex, not a change of host keyboard.

1. Accents in the lexicon. Hex's trie holds a–z and the apostrophe. Keep that alphabet,
   so taps decode as before, and store each word without its accents ("ideeen") with its
   real spelling in a table after the trie ("ideeën"). Lookups drop accents first, and
   the spelling comes back from the table, so typing "ideeen" gives "ideeën". A word you
   type with accents yourself is left as you typed it. English must stay the same: Hex's
   `scripts/eval` still ends with `EVAL matches eval.expected`.
2. Dutch word list and counts (`nl.lexicon`, built by `scripts/lexicon-nl`): words from
   OpenTaal's word list (BSD-3 / CC BY 3.0), counts from OPUS OpenSubtitles 2018 Dutch,
   which is conversational like the English fiction counts.
3. Dutch next words (`nl.phrases`) from the same subtitles.
4. A Dutch test set from Tatoeba (CC BY 2.0 FR), kept apart from the training text, for
   Hex's `Evaluation` (taps with noise, predictions).
5. Switching: a Language setting in the app, English and Nederlands in the menu you get
   by holding 123 (which already holds one-handed mode), and the language's name on the
   space bar. The system globe key belongs to iOS and can't switch inside one keyboard.
   Words learned are kept per language; where your taps land is shared.
6. Emoji suggestions stay English-only, so in Dutch they're off.

**Done when:** with Nederlands picked, "ik heb geen idee" types without corrections,
"ideeen" becomes "ideeën" and predictions after "dank" include "je" (`DutchLexiconTests`),
and picking NL from the 123 menu in the Simulator does the same through the keyboard
(`LanguageTests`); the Dutch evaluation reports word accuracy close to English at the same
noise; the English evaluation is unchanged; all existing tests pass.

**Result (2026-10-30): built.**

- Lexicon (`KeyboardCore/Correction/Lexicon.swift`): words are stored without accents
  and a spelled flag points into a table after the trie, so en.lexicon is unchanged on
  disk. `Lexicon.letters` folds case, accents and ’ to the 27 letters; spellings that
  differ only in accents share a word spelled the commoner way ("een", not "één"; "voor",
  not "vóór"). A word typed with accents isn't corrected. Folding ’ also means a
  contraction typed with smart punctuation ("I’m") now reads as the word it is, which
  moved one English number up: chat predictions for a learning user, top 3 30.3% →
  30.6% (`eval.expected` updated; every other English line unchanged).
- Data: `scripts/lexicon-nl` (186,174 words, 4.8 MB) and `scripts/phrases-nl` (50,070
  contexts, 1.5 MB), both run on gloob in a few minutes from cached downloads in
  `app/build/`. OpenTaal leaves out "ok", "okay", "hey" and a few more; the script adds
  them. Subtitles write "'t" and "'n"; those aren't counted, or "t" and "n" would be
  common words. Sources and licences in `Resources/LEXICON-LICENSE`. OpenSubtitles has
  no licence of its own; only counts derived from it are shipped, as for the English.
- Evaluation (`Evaluation.dutch`, 500 Tatoeba sentences typed without accents, 2,777
  words), word accuracy after autocorrect:

  | noise | 0 | 0.15 | 0.25 | 0.35 |
  | --- | --- | --- | --- | --- |
  | Dutch, decoder | 99.6% | 99.5% | 97.3% | 88.5% |
  | English, decoder | 99.9% | 99.8% | 97.3% | 88.6% |
  | Dutch, iOS spell checker | 98.0% | 97.6% | 82.0% | 48.5% |

  Predictions, top 3: 26.9% (phrases-nl) and 28.2% (chat-nl) for a new user. Words it
  wrongly changes, even typed dead center: rare words next to common ones ("at" → "dat",
  "aten" → "laten", "wei" → "wie") and names Tatoeba uses.
- Switching: `Language` and `KeyboardSettings.language`; the 123 hold menu gained EN and
  NL after the hands (`MenuItem`); the space bar's corner shows the language's code
  beside "hex" ("hex · NL"; at first its full name across the space bar, changed at the
  owner's request 2026-10-30); Keyboard Settings › Language and the Settings app have a Language choice; `-HexLanguage en|nl` for tests.
  `HexKeyboardViewController.useLanguage` swaps the corrector and keeps learned words per
  language (`typing-memory-nl.json` beside Hex's `typing-memory.json`), carrying the touch
  model over. The extension declares `PrimaryLanguage` `mul`. Emoji suggestions are off
  in Dutch.
- Tests: `AccentTests` (6, KeyboardCore), `DutchLexiconTests` (5), `LanguageTests` (UI:
  pick NL from the menu, "goede ideeen" → "Goede ideeën", back to EN, "teh" → "the").
- Xcode doesn't always recopy a package's resource bundle into the app, the extension
  or a test bundle when a resource is added; after adding one, delete the nested
  `HexKeyboard_*.bundle` copies under `build/*/Build/Products` (the keyboard crashed on
  the missing `nl.lexicon` until then). The iPhone build hit it too: check that
  `Hex.app/PlugIns/Keyboard.appex/HexKeyboard_KeyboardUI.bundle` holds `nl.lexicon`.
- Installed on the owner's iPhone from gloob (2026-10-30), signed Release build.

Open:
- Installed but not yet typed with on the iPhone: memory with nl.lexicon loaded, and how
  it feels.
- ~~No automatic language detection; switching is by hand.~~ Done 2026-10-30, see below.
- Dutch capitalization of "ij" at a sentence start ("IJs") isn't done.

**English & Nederlands (2026-10-30)**, asked for by the owner "like Apple does it": a
third choice, EN-NL in the 123 menu. `Mixture` (KeyboardCore) holds both languages with
weights; P(word) = Σ weight × P(word | language) at the lexicon level of Hex's language
model, next words mix the two phrase tables, and the decoder searches both tries. The
weights come from the last 12 words before the caret (each earlier word counting 0.8 of
the next, a word a language lacks at P = 10⁻⁷), and each language keeps at least 5%, so a
message can switch. With one language every path goes straight to its lexicon, and the
English and Dutch numbers are unchanged. Learned words for both go in
`typing-memory-en+nl.json`.

`Evaluation.both` types the English and the Dutch phrases alternately with one corrector;
each phrase starts with the weights the other language left, so the first words of each
are the hard case. Autocorrect, decoder (learning):

| noise | 0.15 | 0.25 | 0.35 |
| --- | --- | --- | --- |
| English alone | 99.8% (99.9%) | 97.3% (97.1%) | 88.6% (91.2%) |
| English in EN+NL | 99.9% (99.9%) | 97.1% (96.8%) | 87.5% (89.8%) |
| Dutch alone | 99.5% (99.4%) | 97.3% (97.2%) | 88.5% (90.6%) |
| Dutch in EN+NL | 99.5% (99.6%) | 96.0% (95.6%) | 85.0% (87.6%) |

Predictions, top 3 for a new user: chat 19.8% (20.2% alone), chat-nl 27.6% (28.2%).
Typical cross-language slips at high noise: "get" → "het", "must" → "niet".
Tests: `MixtureTests` (6), `BilingualTests` (4), `LanguageTests.testBothLanguages…` (UI).

**Emoji in Dutch (2026-10-30).** `emoji-nl.txt` (5,487 words) is made by
`scripts/emoji-nl.py` from CLDR's Dutch annotations, ranked like Hex's English
candidates, then read through: categories, numbers and words whose emoji nobody typing
them would want find none ("dag", "trouwens", "bomen"), and FIRST fixes the order where
the ranking doesn't ("hart" ❤️ before the anatomical 🫀). Words ending in s that aren't
plurals get an empty line, or Hex's English plural rule finds "trouwen" for "trouwens".
The engine has one index per language of the mixture (`TypingEngine.emojiCatalogs`)
and uses the leading language's, so in EN+NL "die" after Dutch finds nothing and after
English finds 💀. Tests: `DutchEmojiTests` (2), `BilingualTests.emojiComeFrom…`.

**Features on/off (2026-10-30)**, asked for by the owner: "when switched off everything
stops; when on you can set options". Hex's main screen lists Keyboard Settings, Voice,
Espanso Snippets, Sources and Your Taps; each feature page starts with a master switch
and shows its options only while it's on (the Settings app mirrors them):

- Voice Typing off: the keyboard has no mic (`SuggestionBar.showsMic`), Hex never uses
  the microphone, and the Transcripts tab goes. On: Keep Mic On, and Transcripts (off
  stops saving dictations, offers to delete the kept ones, hides the tab).
- Espanso Snippets off: the keyboard loads no snippets, so nothing expands, is suggested
  or shown. On: Expand While Typing (off: triggers type as written and aren't suggested;
  the snippets button still inserts snippets), Snippets Button.
- Sources off: nothing is sent to any source and no hints show. On: the sources.
- Learn My Taps off: the engine stops learning taps and the keyboard resets its touch
  model to the default, so autocorrect no longer adapts to your thumbs; nothing is
  shared and Your Taps goes. On: Show Your Taps (sharing with the app, and the tab).

`UITab.isHidden` didn't hide a tab on iPhone, so the tab bar is given only the visible
tabs. Tests: `FeatureSwitchTests` (UI, 2, including the keyboard losing its mic),
`LearnTapsTests`. Running the UI tests while the package tests run can time out
`FeatureTests.testAChoiceAsksInAPanel`; alone they all pass.

## Updating Espanso

The three Espanso libraries are pinned to one commit in `core/Cargo.toml`. To update:
change all three `rev` values together, run `cargo update -p espanso-config
-p espanso-match -p espanso-render`, compare the copied code from steps 1 and 2 with its
new upstream version, and run `scripts/check-ios.sh` plus the Swift tests.
