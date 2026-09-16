#!/bin/bash
# Dev loop: kill any running instance, build, package, relaunch, verify it stays up.
# Usage: ./Scripts/compile_and_run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NodeClubTracker"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

"$ROOT/Scripts/package_app.sh" debug
open -n "$ROOT/$APP_NAME.app"
sleep 1.5

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "✔ $APP_NAME is running (pid $(pgrep -x "$APP_NAME" | head -1))"
else
    echo "✘ $APP_NAME failed to stay running" >&2
    exit 1
fi
