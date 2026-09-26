#!/bin/bash
# Build the distributable DMG: swift build, app bundle (package_app.sh),
# staging folder with the app + an Applications symlink, diskutil image (UDZO),
# plus a SHA-256 sidecar for the release attachment.
# The result is ad-hoc signed only (no Developer ID) — see README "Install".
# Usage: ./Scripts/make_dmg.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="NodeClubTracker"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Config/Info.plist")"
DIST="$ROOT/dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$DIST/.stage"

"$ROOT/Scripts/package_app.sh" "$CONFIG"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$ROOT/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
rm -f "$DMG"
diskutil image create from "$STAGE" --volumeName "$APP_NAME $VERSION" --format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"

( cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

echo "created $DMG"
cat "$DMG.sha256"
