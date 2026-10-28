# espanso-keyboard

An iPhone keyboard that types like Apple's and expands your Espanso snippets. The snippet
files are the same ones Espanso uses on the Mac: one folder, synced through iCloud Drive,
works on both devices.

The keyboard part comes from a fork of [Hex](https://github.com/AVGVSTVS96/hex-keyboard).
The snippet part is Espanso's own Rust code
([espanso-config, espanso-match, espanso-render](https://github.com/espanso/espanso)),
built for the iPhone. Snippets that run scripts use JavaScript files: Espanso runs them
with Bun on the Mac, and the keyboard runs the same files with JavaScriptCore.

The project started from one use case: typing `;jitsi` in a Fantastical event to get a
new Jitsi meeting link (see `fixtures/espanso/match/base.yml`).

## Status

Starting point only. `core/` loads an Espanso folder with Espanso's loader and has tests;
it builds for the iPhone and the iPhone Simulator. Everything else is described in
[docs/plan.md](docs/plan.md).

## Documents

| Document | What it covers |
|---|---|
| [docs/plan.md](docs/plan.md) | Build steps in order, each with what "done" means |
| [docs/architecture.md](docs/architecture.md) | How the keyboard, the companion app and the Rust core fit together |
| [docs/script-contract.md](docs/script-contract.md) | How snippet scripts are written so they run on the Mac and the iPhone |
| [docs/build-on-gloob.md](docs/build-on-gloob.md) | Setting up and building inside the gloob virtual machine |
| [docs/decisions.md](docs/decisions.md) | Decisions already made, and why |
| [AGENTS.md](AGENTS.md) | Rules for coding agents working in this repository |

## Getting started

```sh
git clone git@github-espanso-keyboard:mdbraber/espanso-keyboard.git ~/src/espanso-keyboard
```

Then follow [docs/build-on-gloob.md](docs/build-on-gloob.md) and step 0 of
[docs/plan.md](docs/plan.md).

## Quick check

```sh
scripts/check-ios.sh
```

Runs the core tests, then builds the core for the iPhone and the iPhone Simulator.

## Licence

GPL-3.0, because the project includes Espanso's GPL-3.0 code. Hex is MIT-licensed, which
may be combined with GPL code. Builds are for personal installation; the GPL and App Store
terms conflict, so the app is not meant for App Store release.
