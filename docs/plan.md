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

Open questions:

- **Undo of a `word: true` trigger doubles the left separator**, on the Mac too: Espanso
  keeps the separator before the trigger when expanding, but types it again on undo
  (`espanso-engine/src/process/middleware/action.rs`). "ok brb " → "ok be right back " →
  backspace → "ok  brb ". The keyboard copies this to match the Mac; the test
  `undo_of_a_word_trigger_puts_back_the_whole_trigger` records it. Fix in both or keep?
- **Several snippets with the same trigger**: Espanso asks which one; the keyboard takes
  the first. A picker could come with the choice panel in step 6.
- **Cursor offset units**: `adjustTextPosition(byCharacterOffset:)` may count UTF-16
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

## Step 6: Later

In whatever order is useful:
- `clipboard` variables through `UIPasteboard`.
- Regex triggers (`espanso_match::regex`).
- Forms and `choice` variables, shown in the keyboard's own panel.
- Matching snippets in Hex's suggestion bar, using `search`.
- `import` between script files (a JavaScriptCore module loader limited to `scripts/`).

## Updating Espanso

The three Espanso libraries are pinned to one commit in `core/Cargo.toml`. To update:
change all three `rev` values together, run `cargo update -p espanso-config
-p espanso-match -p espanso-render`, compare the copied code from steps 1 and 2 with its
new upstream version, and run `scripts/check-ios.sh` plus the Swift tests.
