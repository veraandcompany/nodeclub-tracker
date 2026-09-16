#!/bin/bash
# Assemble Taskbar.app from the SwiftPM build product.
# Usage: ./Scripts/package_app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="Taskbar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

(cd "$ROOT" && swift build -c "$CONFIG" --show-bin-path >/dev/null 2>&1 || true)
(cd "$ROOT" && swift build -c "$CONFIG")
BIN_PATH="$(cd "$ROOT" && swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_PATH/$APP_NAME"
[ -x "$BIN" ] || { echo "error: missing $BIN (run: swift build -c $CONFIG)" >&2; exit 1; }

APP="$ROOT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
touch "$APP"
echo "packaged $APP ($CONFIG)"
