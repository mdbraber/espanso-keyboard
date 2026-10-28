# Building on gloob

gloob is the owner's Tart macOS virtual machine on their Mac, where development and coding
agents run. It was built from `ghcr.io/cirruslabs/macos-golden-gate-xcode:27.1`
(macOS 27.0, Xcode 27.1) and has 16 GB of memory.

## What gloob can and can't do for this project

| Task | In gloob? | Why |
|---|---|---|
| Rust core: build, test, build for iPhone and Simulator | Yes | Needs only internet access for crates |
| UniFFI bindings, XCFramework | Yes | Local tools |
| Xcode builds for the iPhone Simulator, Simulator tests | Expected yes; confirm in step 0 | Simulator in a virtual machine is the first thing to check |
| Installing on the owner's iPhone over USB | No | gloob has no USB passthrough |
| Installing or debugging over Wi-Fi | No | The Mac's packet filter blocks gloob from the local network and the tailnet |
| Signing for a real device | Owner's decision, see below | Needs an Apple signing certificate inside gloob |

## Getting a build onto the iPhone

Signing needs an Apple development certificate and provisioning profile, or an
App Store Connect key for TestFlight. gloob's standing rule is that its only standing
credentials are the coding agent's login and the machine's SSH key, so any of these is a
new credential. **The owner picks one of these before step 4; agents don't set it up.**

1. **Build in gloob, sign and install on the Mac.** gloob builds the app for the device
   unsigned (`CODE_SIGNING_ALLOWED=NO`). The owner copies the `.app` to the Mac and
   signs and installs it there with Xcode or `xcrun devicectl device install app`.
   No new credential in gloob. Most manual.
2. **Sign in gloob, install from the Mac.** The development certificate lives in gloob.
   gloob produces a signed `.app`; the Mac only installs it with `xcrun devicectl`.
3. **TestFlight from gloob.** An App Store Connect API key in gloob uploads builds; the
   iPhone installs them from the TestFlight app. Most automatic, and builds keep working
   for 90 days. TestFlight for internal testers isn't an App Store release, but check that
   this fits the GPL decision in [decisions.md](decisions.md).
4. **Open the project in Xcode on the Mac** and run it on the iPhone from there. The Mac
   has Xcode installed. Simplest for debugging the keyboard on a device, but the build
   then happens outside gloob.

Whichever is chosen, put the team ID and identifier prefix in an untracked file
(`Config/Local.xcconfig`, see step 4 of the plan), never in git.

## One-time setup in gloob

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

UniFFI's binding generator is built from the project itself in step 3, so it needs no
separate install.

## Check the setup

```sh
git clone <this repository> ~/src/espanso-keyboard
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
