#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
swift build -c release --product CodexQuotaDock --disable-sandbox "$@"
BIN_DIR="$(swift build -c release --show-bin-path "$@")"
APP_DIR="$PROJECT_DIR/dist/Codex Quota Dock.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexQuotaDock" "$APP_DIR/Contents/MacOS/CodexQuotaDock"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${APP_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
cp Resources/codex.svg "$APP_DIR/Contents/Resources/codex.svg"
mkdir -p "$APP_DIR/Contents/Resources/ThirdPartyNotices"
cp Resources/ThirdPartyNotices/*.txt "$APP_DIR/Contents/Resources/ThirdPartyNotices/"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIconDark.iconset" dark
iconutil -c icns "$PROJECT_DIR/.build/AppIconDark.iconset" -o "$APP_DIR/Contents/Resources/AppIconDark.icns"
codesign --force --deep --sign - "$APP_DIR"
# 原地覆盖包内文件不会更新包目录时间；通知 Launch Services 重新识别图标等元数据。
touch "$APP_DIR"
printf '%s\n' "$APP_DIR"
