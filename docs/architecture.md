# Architecture

## Parts

```
iPhone
├── Companion app (SwiftUI)
│   ├── Picks the Espanso folder in iCloud Drive once (remembered as a bookmark)
│   └── Copies config/, match/ and scripts/ into the shared app group storage
│
├── Keyboard extension (fork of Hex)
│   ├── Hex: keys, layouts, autocorrect, suggestion bar
│   ├── Expansion hook: passes typed characters to the core, applies the result
│   └── Script runner: runs .js files in JavaScriptCore for the core
│
└── EspansoKeyboardCore (Rust, from core/)
    ├── espanso-config: loads the copied Espanso folder
    ├── espanso-match: finds triggers in the typed characters
    ├── espanso-render: fills in variables (date, echo, random, nested matches, …)
    └── Replacement extensions: script (calls the script runner), clipboard
```

Mac: Espanso, unchanged, reads the same folder through iCloud Drive and runs the same
scripts with Bun.

## Data flow

1. The owner keeps the Espanso folder in iCloud Drive (Espanso's sync guide:
   https://espanso.org/docs/sync/).
2. The companion app copies it into the app group storage when opened, or when "Reload"
   is tapped. The keyboard never reads iCloud Drive itself.
3. When the keyboard starts, it calls the core's `load` with the app group copy.
4. For each character typed, the keyboard calls the core. The core answers with nothing,
   or with an expansion: how many characters to delete, the text to insert, and how far to
   move the cursor back (for `$|$`).
5. The keyboard applies the expansion through `textDocumentProxy`.

## Core interface (Swift view)

Generated with Mozilla's UniFFI (https://mozilla.github.io/uniffi-rs/), so Swift sees
ordinary types. Names are a starting suggestion.

```swift
final class EspansoEngine {
    init(configFolder: String, scriptRunner: ScriptRunner) throws
    func type(_ text: String) -> Expansion?   // one key press: a character, or "\n"
    func backspace() -> Expansion?            // non-nil when undoing an expansion
    func reset()                              // cursor moved, field changed, keyboard reappeared
    func search(_ query: String) -> [SnippetSummary]
    var warnings: [String] { get }
}

struct Expansion {
    let deleteCount: Int        // characters to delete before the cursor
    let insert: String
    let cursorOffset: Int       // characters to move left after inserting (0 if none)
}

protocol ScriptRunner {         // implemented in Swift with JavaScriptCore
    func run(scriptPath: String, argv: [String], env: [String: String]) throws -> String
}
```

The keyboard inserts each typed character first and then calls `type`. It calls
`backspace` before deleting; if that returns an expansion, the keyboard applies it instead
of deleting a character.

The renderer is synchronous, so `run` blocks until the script finishes or the time limit
passes. The keyboard therefore calls `type` off the main thread whenever the typed text
could complete a trigger with a script variable, or simply always.

## Keyboard constraints that shape the design

- **Full Access is required.** Without it a keyboard cannot read the app group storage or
  the clipboard.
- **Memory limit.** iPhone keyboards are stopped when they use too much memory (in
  practice roughly 50 to 70 MB). Measure the core's memory and the app's size early
  (plan step 3).
- **Password and phone-number fields** always switch to Apple's keyboard.
- **The keyboard only sees its own typing.** Trigger state is reset whenever the cursor
  moves or the text changes in a way the keyboard didn't cause (`textDidChange`,
  `selectionDidChange`).
- **No programs can be started**, so Espanso's `shell` variables and non-JavaScript
  `script` variables fail and the snippet doesn't expand.

## Espanso behaviour on the iPhone

| Feature | Plan |
|---|---|
| Plain text, `word: true`, `$|$` cursor, nested matches, `imports`, `_` files | Works through Espanso's code (step 1) |
| `date`, `echo`, `random` variables | Works through Espanso's code (step 1) |
| `script` with a `.js` file | Replacement extension plus JavaScriptCore (steps 2 and 3) |
| Undo with backspace (`undo_backspace`) | Keyboard-side logic (step 1) |
| `clipboard` | Replacement extension calling `UIPasteboard` (step 6) |
| Regex triggers | `espanso-match` regex matcher (step 6) |
| Forms and `choice` | Needs keyboard UI (step 6) |
| `shell`, non-JavaScript scripts | Not possible on the iPhone |
| App-specific configs (`filter_title`, `filter_exec`) | Not possible: keyboards can't see which app they're in |
