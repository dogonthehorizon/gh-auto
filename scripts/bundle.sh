#!/usr/bin/env bash
# Build a release binary and assemble a signed, version-stamped gh-auto.app.
# Usage: scripts/bundle.sh <output-dir>   (prints the bundle path on success)
set -euo pipefail

cd "$(dirname "$0")/.."
out_dir="${1:?usage: bundle.sh <output-dir>}"
app="$out_dir/gh-auto.app"
plist="$app/Contents/Info.plist"

swift build -c release >&2

# Marketing version from VERSION; build number and commit from git so every publish is traceable.
version="$(tr -d '[:space:]' < VERSION)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then commit="$commit-dirty"; fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$plist"
cp .build/release/GhAuto "$app/Contents/MacOS/gh-auto"
strip -x "$app/Contents/MacOS/gh-auto"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
/usr/libexec/PlistBuddy -c "Add :GHAutoCommit string $commit" "$plist"

codesign --force --sign - "$app" >&2
codesign --verify --strict "$app"

echo "$app"
