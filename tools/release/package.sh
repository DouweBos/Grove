#!/bin/bash
# Packages a notarized dist/Grove.app for release: the Sparkle zip + appcast, and a DMG for first installs.
# Usage: package.sh <version> <production|beta>
# Signs the appcast with $SPARKLE_PRIVATE_KEY, or the "grove" key in the login keychain when unset.
set -euo pipefail

VERSION=$1
CHANNEL=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIST="$ROOT/dist"
FEED="$DIST/appcast"
DOWNLOADS="https://houwert.dev/grove/updates/"
APP="$DIST/Grove.app"

[ -d "$APP" ] || { echo "Missing $APP" >&2; exit 1; }
xcrun stapler validate "$APP" >/dev/null

# Sparkle's tools, matching the version the app links.
SPARKLE_VERSION=$(python3 -c "import json,sys; print(next(p['state']['version'] for p in json.load(open(sys.argv[1]))['pins'] if p['identity']=='sparkle'))" \
  "$ROOT/app/Grove/Grove.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
TOOLS="$HOME/Library/Caches/grove-release/sparkle-$SPARKLE_VERSION"
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  mkdir -p "$TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$TOOLS"
fi

rm -rf "$FEED" && mkdir -p "$FEED"

# The appcast keeps every earlier release; it lives on the newest GitHub release of either channel.
PREVIOUS=$(gh release list --exclude-drafts --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)
if [ -n "$PREVIOUS" ]; then
  gh release download "$PREVIOUS" --pattern appcast.xml --dir "$FEED" 2>/dev/null || echo "No appcast on $PREVIOUS; starting a new one"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$FEED/Grove-$VERSION.zip"

# Release notes: $GROVE_RELEASE_NOTES (one change per line) or the commit subjects since the last tag.
NOTES=${GROVE_RELEASE_NOTES:-}
if [ -z "$NOTES" ]; then
  LAST_TAG=$(git -C "$ROOT" describe --tags --abbrev=0 HEAD 2>/dev/null || true)
  NOTES=$(git -C "$ROOT" log --no-merges --format=%s ${LAST_TAG:+"$LAST_TAG"..HEAD} | grep -vE '^chore\(release\)' || true)
fi
{
  echo "<ul>"
  printf '%s\n' "$NOTES" | sed '/^[[:space:]]*$/d; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/^[-*] //; s|.*|<li>&</li>|'
  echo "</ul>"
} > "$FEED/Grove-$VERSION.html"

ARGS=(--download-url-prefix "$DOWNLOADS" --embed-release-notes --maximum-deltas 0)
[ "$CHANNEL" = "beta" ] && ARGS+=(--channel beta)
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/bin/generate_appcast" --ed-key-file - "${ARGS[@]}" "$FEED"
else
  "$TOOLS/bin/generate_appcast" --account grove "${ARGS[@]}" "$FEED"
fi

# DMG for first installs; updates go through the zip.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Grove -srcfolder "$STAGE" -ov -format UDZO "$DIST/Grove-$VERSION.dmg"
rm -rf "$STAGE"
codesign --sign "Developer ID Application" --timestamp "$DIST/Grove-$VERSION.dmg"

echo "Packaged Grove $VERSION ($CHANNEL):"
ls -1 "$FEED" "$DIST"/*.dmg
