#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
swift build -c release --product CodexQuotaDock --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Codex Quota Dock.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexQuotaDock" "$APP_DIR/Contents/MacOS/CodexQuotaDock"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/codex.svg "$APP_DIR/Contents/Resources/codex.svg"
mkdir -p "$APP_DIR/Contents/Resources/ThirdPartyNotices"
cp Resources/ThirdPartyNotices/*.txt "$APP_DIR/Contents/Resources/ThirdPartyNotices/"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
