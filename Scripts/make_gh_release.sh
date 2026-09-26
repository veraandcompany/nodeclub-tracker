#!/bin/bash
# One-shot GitHub release: preflight, build DMG + SHA-256, tag, push, publish.
#
# The version is read from Config/Info.plist — bump and commit it BEFORE running.
# The tag points at the current HEAD, so the release always matches the checked-out code.
#
# Usage: ./Scripts/make_gh_release.sh ["release notes"] [--draft] [--prerelease]
#   notes:  optional; default = commit subjects since the last tag (oldest first)
#   flags:  forwarded to `gh release create`
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="NodeClubTracker"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Config/Info.plist")"
TAG="v$VERSION"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
SHA="$DMG.sha256"

NOTES=""
GH_FLAGS=""
for arg in "$@"; do
    case "$arg" in
        --draft)      GH_FLAGS="$GH_FLAGS --draft" ;;
        --prerelease) GH_FLAGS="$GH_FLAGS --prerelease" ;;
        -*)           echo "error: unknown option: $arg (only --draft / --prerelease)" >&2; exit 1 ;;
        *)
            if [ -n "$NOTES" ]; then
                echo "error: extra positional argument: $arg" >&2; exit 1
            fi
            NOTES="$arg"
            ;;
    esac
done

echo "==> releasing $TAG"

# --- preflight ---------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { echo "error: gh not installed (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated (gh auth login)" >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "error: no origin remote" >&2; exit 1; }
BRANCH="$(git symbolic-ref -q --short HEAD || true)"
[ -n "$BRANCH" ] || { echo "error: detached HEAD — check out a branch first" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "error: working tree is dirty — commit or stash first" >&2; exit 1; }
git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1 && { echo "error: tag $TAG already exists locally" >&2; exit 1; }
git ls-remote --tags origin "$TAG" 2>/dev/null | grep -q . && { echo "error: tag $TAG already exists on origin" >&2; exit 1; }
gh release view "$TAG" >/dev/null 2>&1 && { echo "error: release $TAG already exists on GitHub" >&2; exit 1; }

# --- build -------------------------------------------------------------------
./Scripts/make_dmg.sh release
[ -f "$DMG" ] && [ -f "$SHA" ] || { echo "error: build did not produce $DMG" >&2; exit 1; }

# --- release notes -----------------------------------------------------------
if [ -z "$NOTES" ]; then
    PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    if [ -n "$PREV" ]; then
        NOTES="$(git log --pretty='- %s' "$PREV"..HEAD)"
    else
        NOTES="$(git log --reverse --pretty='- %s')"
    fi
fi

# --- tag + push --------------------------------------------------------------
git tag "$TAG"
git push origin "$BRANCH"
git push origin "$TAG"

# --- publish -----------------------------------------------------------------
# shellcheck disable=SC2086  # GH_FLAGS is intentionally word-split (bare flags only)
if ! gh release create "$TAG" "$DMG" "$SHA" --title "$TAG" --notes "$NOTES" $GH_FLAGS; then
    echo "error: gh release create failed. Tag $TAG was already pushed; to retry:" >&2
    echo "  git tag -d $TAG && git push origin :refs/tags/$TAG" >&2
    exit 1
fi

echo "==> released $TAG at $(gh release view "$TAG" --json url -q .url)"
