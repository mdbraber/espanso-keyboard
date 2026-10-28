# Decisions

Decisions already made. Change them only with the owner's agreement.

## Reuse Espanso's Rust code

The keyboard uses Espanso's own `espanso-config`, `espanso-match` and `espanso-render`
libraries instead of a Swift reimplementation of the snippet format.

- **Why:** the same snippet files behave exactly as they do in Espanso on the Mac,
  including imports, files starting with `_`, `word: true`, nested matches and variables.
- **Cost:** the whole app is GPL-3.0, and the build needs Rust.
- **Checked (2026-10-28, Espanso commit `80d9e35`):** all four Espanso engine libraries,
  including `espanso-engine`, compile for `aarch64-apple-ios` without changes.

## Use the three libraries directly, not `espanso-engine`

`espanso-engine` coordinates the desktop app and needs about 20 host components built
around a desktop (system keystroke capture, typing into other apps, tray icon, menus,
secure input). The keyboard instead uses config, match and render directly, with its own
small coordinating code. Espanso's desktop version of that code, in
`espanso/src/cli/worker/engine/` of the Espanso repository, is the template.

## Scripts are JavaScript files

Snippets that compute something use Espanso's standard `script` variable pointing to a
`.js` file inside the Espanso folder. No inline code (`bun -e`) and no custom variable
types such as `type: js`.

- **Why:** every snippet stays valid for Espanso on the Mac. Espanso skips variable types
  it doesn't know and then fails on the missing variable, so a custom type would break the
  snippet on the Mac.
- **Details:** [script-contract.md](script-contract.md).
- **Postponed:** `import` between script files. Add a module loader only once shared
  helpers are needed.

## Host keyboard: a fork of Hex

[Hex](https://github.com/AVGVSTVS96/hex-keyboard) (MIT) is matched to Apple's keyboard
in layout, pop-ups and haptics, and has its own autocorrect. Its typing logic is a separate
pure-Swift package (`Packages/HexKeyboard/Sources/KeyboardCore`).

- **Risk:** Hex only has English autocorrect and no swipe typing yet. Check how it handles
  Dutch typing before building on it (plan step 4).
- **Alternatives considered:** SnipKey (MIT, more mature, has its own snippets and iCloud
  sync, English suggestions), byteboard (pre-alpha, already reads Espanso files),
  iBoard (Apache 2.0, very new). KeyboardKit was ruled out: its licence is closed source,
  which cannot be combined with GPL code.

## No App Store release

GPL-3.0 and App Store terms conflict. Builds are installed on the owner's own devices
with their Apple developer account.
