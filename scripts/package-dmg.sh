#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
ARCH="${1:-}"
case "$ARCH" in
    arm64) PLATFORM="AppleSilicon" ;;
    x86_64) PLATFORM="Intel" ;;
    *) printf '用法：bash scripts/package-dmg.sh arm64|x86_64\n' >&2; exit 1 ;;
esac

bash scripts/build.sh --arch "$ARCH"
APP_DIR="$PROJECT_DIR/dist/Codex Quota.app"
lipo "$APP_DIR/Contents/MacOS/CodexQuota" -verify_arch "$ARCH"
codesign --verify --deep --strict "$APP_DIR"
DMG_PATH="$PROJECT_DIR/dist/CodexQuota-macOS-${PLATFORM}.dmg"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/.build/dmg-${ARCH}.XXXXXX")"
trap 'rm -r "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/Codex Quota.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Codex Quota $PLATFORM" -srcfolder "$STAGING_DIR" \
    -fs HFS+ -format UDZO -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
printf '%s\n' "$DMG_PATH"
