# Building on gloob

gloob is the owner's Tart macOS virtual machine on their Mac, where development and coding
agents run. It was built from `ghcr.io/cirruslabs/macos-golden-gate-xcode:27.1`
(macOS 27.0, Xcode 27.1) and has 28 GB of memory.

## What gloob can and can't do for this project

| Task | In gloob? | Why |
|---|---|---|
| Rust core: build, test, build for iPhone and Simulator | Yes | Needs only internet access for crates |
| UniFFI bindings, XCFramework | Yes | Local tools |
| Xcode builds for the iPhone Simulator, Simulator tests | Yes | Confirmed in step 0: an app builds, installs and launches with `xcrun simctl`. The first boot of a Simulator device takes about 1.5 minutes |
| Installing on the owner's iPhone over USB | No | gloob has no USB passthrough |
| Installing or debugging over Wi-Fi | No | The Mac's packet filter blocks gloob from the local network and the tailnet |
| Signing for a real device | Yes | Xcode in gloob is signed in to the owner's Apple developer account |

## Signing

Decided by the owner (2026-10-28): **builds are signed in gloob** with the Apple developer
account that Xcode in gloob is already signed in to. Use automatic signing, and pass
`-allowProvisioningUpdates` to `xcodebuild` so it can create certificates, identifiers,
app groups and provisioning profiles through that account.

Don't add other Apple credentials to gloob, such as App Store Connect API keys or
exported certificate files.

Put the team ID and identifiers in the untracked `Config/Local.xcconfig`, never in git.
Copy `Config/Local.xcconfig.example` and fill in `DEVELOPMENT_TEAM` (Xcode › Settings ›
Accounts), `APP_BUNDLE_ID` and `APP_GROUP_ID`.

## Getting a signed build onto the iPhone

gloob can't reach the iPhone, so a signed build gets there in one of two ways. Use the
first until there's a reason to set up the second.

1. **Install from the Mac.** gloob builds a signed `.app` for the device. The owner copies
   it to the Mac (for example with `scp` from the Mac, which can reach gloob) and installs
   it with `xcrun devicectl device install app --device <iPhone> <path to .app>`.
2. **TestFlight from gloob.** gloob archives the app and uploads it to App Store Connect
   with Xcode's signed-in account (`xcodebuild -exportArchive` with an export options
   file set to upload). The iPhone installs builds from the TestFlight app, and each build
   works for 90 days. This needs an app record in App Store Connect, which the owner
   creates. Internal TestFlight testing isn't an App Store release, but the owner should
   confirm it fits the GPL decision in [decisions.md](decisions.md) first.

For debugging the keyboard on the device itself, open the project in Xcode on the Mac,
which also has Xcode installed, and run it from there.

## One-time setup in gloob

The golden-gate image already has the Xcode licence accepted and the iOS 27.0 and 27.1
Simulator runtimes installed; check with `xcodebuild -checkFirstLaunchStatus` (exit status
0) and `xcrun simctl list runtimes`, and skip the first two commands if both are fine.

```sh
# Xcode is preinstalled; accept the licence and install the iOS platform if missing.
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS

# Rust (no Homebrew Rust; rustup manages the iPhone targets)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

# Project tools
brew install xcodegen bun just
```

rustup adds `~/.cargo/bin` to `~/.zshenv`, `~/.zprofile` and `~/.profile`; until a new
shell is opened, run `source "$HOME/.cargo/env"` first.

UniFFI's binding generator is built from the project itself in step 3, so it needs no
separate install.

## GitHub access: deploy key

gloob reaches GitHub with a deploy key that only works for this repository, not with the
owner's own GitHub account.

- The key is `~/.ssh/github-espanso-keyboard` (Ed25519), with its public half in
  `~/.ssh/github-espanso-keyboard.pub`.
- On GitHub it is added to the repository (Settings → Deploy keys) under the name
  `gloob`, with write access so agents can push.
- `~/.ssh/config` has a host alias that uses only that key:

  ```
  Host github-espanso-keyboard
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-espanso-keyboard
    IdentitiesOnly yes
  ```

  `IdentitiesOnly yes` stops SSH from offering other keys first; GitHub accepts the first
  key it recognises, so another key could otherwise give the wrong access.

Clone and push through the alias, `git@github-espanso-keyboard:mdbraber/espanso-keyboard.git`,
instead of `git@github.com:…`.

## Check the setup

```sh
git clone git@github-espanso-keyboard:mdbraber/espanso-keyboard.git ~/src/espanso-keyboard
cd ~/src/espanso-keyboard
scripts/check-ios.sh
bun fixtures/espanso/scripts/jitsi.js 10
```

`check-ios.sh` should end with two lines naming `libespanso_keyboard_core.a` for
`aarch64-apple-ios` and `aarch64-apple-ios-sim`. The Bun command should print a
10-character room name.

## Network

gloob reaches the internet (GitHub, crates.io, Homebrew, Apple) but not the local network
or the tailnet. Nothing in this project needs local network access, except installing on
the iPhone, which happens on the Mac as described above.
