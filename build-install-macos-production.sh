#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$HOME/Developer/flutter-3.44.9/bin/flutter}"
readonly RUST_BIN_DIR="${RUST_BIN_DIR:-$HOME/.rustup/toolchains/1.81.0-aarch64-apple-darwin/bin}"
readonly VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
readonly GNU_SED_BIN_DIR="${GNU_SED_BIN_DIR:-/opt/homebrew/opt/gnu-sed/libexec/gnubin}"
readonly SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Development: Sunghyun Cho (9XZ7YFMATF)}"
readonly DESTINATION="$HOME/Applications/RustDesk Dev.app"
readonly ENTITLEMENTS="$REPOSITORY_ROOT/flutter/macos/Runner/Release.entitlements"
readonly ARM64_XCCONFIG="$REPOSITORY_ROOT/flutter/macos/Runner/Configs/Arm64.xcconfig"

require_file() {
  if [[ ! -x "$1" ]]; then
    echo "Required executable is unavailable: $1" >&2
    exit 1
  fi
}

require_readable_file() {
  if [[ ! -r "$1" ]]; then
    echo "Required file is unavailable: $1" >&2
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
require_readable_file "$ENTITLEMENTS"
require_readable_file "$ARM64_XCCONFIG"
require_directory "$VCPKG_ROOT"
require_directory "$GNU_SED_BIN_DIR"
command -v pod >/dev/null || {
  echo "CocoaPods is unavailable. Install it before running this script." >&2
  exit 1
}
security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY" || {
  echo "Signing identity is unavailable: $SIGNING_IDENTITY" >&2
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

cargo build --release --locked --features flutter
(
  cd flutter
  XCODE_XCCONFIG_FILE="$ARM64_XCCONFIG" "$FLUTTER_BIN" build macos --release
)

readonly SOURCE_APP="$REPOSITORY_ROOT/flutter/build/macos/Build/Products/Release/RustDesk.app"
require_directory "$SOURCE_APP"

stage_dir="$(mktemp -d "$(dirname "$DESTINATION")/.rustdesk-dev-install.XXXXXX")"
staged_app="$stage_dir/RustDesk Dev.app"
backup_app="$stage_dir/previous.app"
installed=false

cleanup() {
  local status=$?
  if [[ "$installed" == false && -d "$backup_app" && ! -e "$DESTINATION" ]]; then
    mv "$backup_app" "$DESTINATION"
  fi
  rm -rf "$stage_dir"
  exit "$status"
}
trap cleanup EXIT

ditto "$SOURCE_APP" "$staged_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.skinmaker.rustdesk.macos' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName RustDesk Dev' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName RustDesk Dev' "$staged_app/Contents/Info.plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string RustDesk Dev' "$staged_app/Contents/Info.plist"

codesign --force --deep --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"

if [[ -e "$DESTINATION" ]]; then
  mv "$DESTINATION" "$backup_app"
fi
mv "$staged_app" "$DESTINATION"
installed=true

echo "Installed Release build at: $DESTINATION"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist"
codesign -dv --verbose=2 "$DESTINATION" 2>&1 | grep -E 'Identifier=|TeamIdentifier='
