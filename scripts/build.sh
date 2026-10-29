#!/bin/bash
# Sparkle 的嵌套签名流程参考 nanvon/cc-bar (MIT), scripts/build.sh。
# Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
# Swift Build 目前会把最低系统版本写成链接 SDK 版本，导致系统沿用旧外观。
# 使用 native 保留真实 SDK 版本：https://github.com/swiftlang/swift-build/issues/1887
swift build --build-system native -c release --product CodexQuota --disable-sandbox "$@"
BIN_DIR="$(swift build --build-system native -c release --show-bin-path "$@")"
APP_DIR="$PROJECT_DIR/dist/Codex Quota.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/CodexQuota" "$APP_DIR/Contents/MacOS/CodexQuota"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
ARCHITECTURES="$(lipo -archs "$BIN_DIR/CodexQuota")"
case "$ARCHITECTURES" in
    arm64) UPDATE_PLATFORM="AppleSilicon" ;;
    x86_64) UPDATE_PLATFORM="Intel" ;;
    *) printf '构建产物必须是 arm64 或 x86_64 单架构\n' >&2; exit 1 ;;
esac
/usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/sunpm/codex-quota/releases/latest/download/appcast-${UPDATE_PLATFORM}.xml" "$APP_DIR/Contents/Info.plist"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    python3 -c 'import base64, os, sys
key = base64.b64decode(os.environ["SPARKLE_PUBLIC_ED_KEY"], validate=True)
if len(key) != 32:
    sys.exit("SPARKLE_PUBLIC_ED_KEY 必须是 32 字节 Ed25519 公钥")'
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
elif [[ -n "${RELEASE_TAG:-}" ]]; then
    printf '发行构建必须设置 SPARKLE_PUBLIC_ED_KEY；参见 docs/updating.md\n' >&2
    exit 1
fi
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${APP_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${RELEASE_TAG:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :ReleaseVersion string ${RELEASE_TAG#v}" "$APP_DIR/Contents/Info.plist"
fi
cp Resources/codex.svg "$APP_DIR/Contents/Resources/codex.svg"
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
    cp "$RELEASE_NOTES_FILE" "$APP_DIR/Contents/Resources/ReleaseNotes.md"
else
    rm -f "$APP_DIR/Contents/Resources/ReleaseNotes.md"
fi
mkdir -p "$APP_DIR/Contents/Resources/ThirdPartyNotices"
cp Resources/ThirdPartyNotices/*.txt "$APP_DIR/Contents/Resources/ThirdPartyNotices/"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIconDark.iconset" dark
iconutil -c icns "$PROJECT_DIR/.build/AppIconDark.iconset" -o "$APP_DIR/Contents/Resources/AppIconDark.icns"
SPARKLE_SOURCE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
# 替换本次构建拥有的框架，避免升级依赖后残留旧的辅助程序。
rm -rf "$SPARKLE_FRAMEWORK"
ditto "$SPARKLE_SOURCE" "$SPARKLE_FRAMEWORK"
SPARKLE_CONTENTS="$SPARKLE_FRAMEWORK/Versions/B"
for SERVICE in "$SPARKLE_CONTENTS"/XPCServices/*.xpc; do
    codesign --force --sign - --options runtime --timestamp=none \
        --preserve-metadata=entitlements "$SERVICE"
done
codesign --force --sign - --options runtime --timestamp=none "$SPARKLE_CONTENTS/Autoupdate"
codesign --force --sign - --options runtime --timestamp=none "$SPARKLE_CONTENTS/Updater.app"
codesign --force --sign - --options runtime --timestamp=none "$SPARKLE_FRAMEWORK"
# 外层 App 沿用 ad-hoc 签名；从内到外封装，不用 --deep 重签辅助程序。
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
# 原地覆盖包内文件不会更新包目录时间；通知 Launch Services 重新识别图标等元数据。
touch "$APP_DIR"
printf '%s\n' "$APP_DIR"
