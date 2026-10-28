# Agent instructions

This repository builds an iPhone keyboard with Espanso snippet expansion. Read
[README.md](README.md), then [docs/plan.md](docs/plan.md) for the current step and
[docs/decisions.md](docs/decisions.md) for what is already settled.

## Working rules

- Work through [docs/plan.md](docs/plan.md) in order. A step is done only when its
  "Done when" check passes. Record measurements and open questions in the plan.
- Decisions in [docs/decisions.md](docs/decisions.md) are the owner's. Raise a proposed
  change with the owner rather than working around it.
- Snippet behaviour must match Espanso on the Mac. When unsure what Espanso does, read its
  source at the pinned commit (`core/Cargo.toml`) rather than guessing, and add a test.
- Scripts follow [docs/script-contract.md](docs/script-contract.md). Don't add inline
  JavaScript or custom variable types.
- Code copied from Espanso keeps its copyright header and a comment naming the upstream
  file it came from.

## Environment

The project is built in gloob, a macOS virtual machine; see
[docs/build-on-gloob.md](docs/build-on-gloob.md).

- Don't set up signing certificates, provisioning profiles, App Store Connect keys or
  Apple account logins. How builds reach the iPhone is the owner's decision.
- Team IDs, identifier prefixes and app group names go in untracked
  `Config/Local.xcconfig`, never in committed files.
- Never commit the owner's real snippet files. `fixtures/espanso/` holds test snippets
  only.

## Commands

```sh
scripts/check-ios.sh                 # core tests, then iPhone and Simulator builds
cd core && cargo test                # core tests only
bun fixtures/espanso/scripts/jitsi.js 10
```
