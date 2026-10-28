#!/usr/bin/env bash
# Runs the core tests on the Mac, then builds the core library for the iPhone and
# the iPhone Simulator. Run from anywhere; installs missing Rust targets.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo/core"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null

cargo test
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  lib="target/$target/release/libespanso_keyboard_core.a"
  printf '%s  %s\n' "$(du -h "$lib" | cut -f1)" "$lib"
done
