#!/usr/bin/env bash
# Build, smoke-test, and install gh-auto.app into ~/Applications, replacing any running copy.
# Safe to rerun: the installed app is only swapped out after the new build passes its checks.
#   DEST=/Applications scripts/publish.sh   install somewhere else
#   SKIP_SMOKE=1 scripts/publish.sh         skip the live GitHub check (e.g. offline)
set -euo pipefail

cd "$(dirname "$0")/.."
dest="${DEST:-$HOME/Applications}"
installed="$dest/gh-auto.app"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

step() { printf '\n==> %s\n' "$*"; }

step "Building"
staged="$(scripts/bundle.sh "$stage")"

step "Smoke test (live GitHub query)"
if [[ "${SKIP_SMOKE:-0}" == 1 ]]; then
  echo "skipped (SKIP_SMOKE=1)"
else
  "$staged/Contents/MacOS/gh-auto" --once
fi

step "Stopping running gh-auto"
if pkill -x gh-auto; then
  for _ in {1..50}; do pgrep -x gh-auto >/dev/null || break; sleep 0.1; done
  pgrep -x gh-auto >/dev/null && { echo "gh-auto did not exit" >&2; exit 1; }
  echo "stopped"
else
  echo "not running"
fi

step "Installing to $installed"
mkdir -p "$dest"
# Copy alongside, then swap, so a failed copy never leaves a half-installed app.
rm -rf "$installed.new" "$installed.old"
cp -R "$staged" "$installed.new"
[[ -d "$installed" ]] && mv "$installed" "$installed.old"
mv "$installed.new" "$installed"
rm -rf "$installed.old"

step "Launching"
open "$installed"
for _ in {1..50}; do pgrep -x gh-auto >/dev/null && break; sleep 0.1; done
pid="$(pgrep -x gh-auto)" || { echo "gh-auto failed to launch" >&2; exit 1; }
running="$(ps -o comm= -p "$pid")"
if [[ "$running" != "$installed/Contents/MacOS/gh-auto" ]]; then
  echo "unexpected binary running: $running" >&2
  exit 1
fi

plist="$installed/Contents/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
step "Published gh-auto $(read_key CFBundleShortVersionString) (build $(read_key CFBundleVersion), $(read_key GHAutoCommit)) — pid $pid"
