#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Developer/flutter-3.44.9/bin/flutter}"
readonly RUST_BIN_DIR="${RUST_BIN_DIR:-$HOME/.rustup/toolchains/1.81.0-aarch64-apple-darwin/bin}"
readonly VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
readonly GNU_SED_BIN_DIR="${GNU_SED_BIN_DIR:-/opt/homebrew/opt/gnu-sed/libexec/gnubin}"

require_file() {
  if [[ ! -x "$1" ]]; then
    echo "Required executable is unavailable: $1" >&2
    exit 1
  fi
}

require_directory() {
  if [[ ! -d "$1" ]]; then
    echo "Required directory is unavailable: $1" >&2
    exit 1
  fi
}

require_file "$FLUTTER_BIN"
require_file "$RUST_BIN_DIR/cargo"
require_directory "$VCPKG_ROOT"
require_directory "$GNU_SED_BIN_DIR"
command -v pod >/dev/null || {
  echo "CocoaPods is unavailable. Install it before running this script." >&2
  exit 1
}

export PATH="$GNU_SED_BIN_DIR:$RUST_BIN_DIR:$PATH"
export VCPKG_ROOT
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

cd "$REPOSITORY_ROOT"
bash .github/patches/apply_flutter_3.44_source_patches.sh

(
  cd flutter
  "$FLUTTER_BIN" pub get
)
pod install --project-directory=flutter/macos

cargo build --locked --features flutter
install -m 755 target/debug/liblibrustdesk.dylib target/release/liblibrustdesk.dylib

cd flutter
exec "$FLUTTER_BIN" run -d macos --debug
