#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
# 下方直接链接对象文件，固定使用原生构建目录，避免受 Swift 默认构建引擎变化影响。
swift run --build-system native --disable-sandbox QuotaCoreChecks
BIN_DIR="$(swift build --build-system native --disable-sandbox --show-bin-path)"
SPARKLE_DIR="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
APP_SOURCES=()
for source in Sources/CodexQuota/*.swift; do
    if [[ "$source" != */App.swift ]]; then APP_SOURCES+=("$source"); fi
done
# 与正式 App 使用同一份实现，注入模拟客户端；不依赖 XCTest / 完整 Xcode。
swiftc -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR/CZstd.build" \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_DIR" \
    "$BIN_DIR/QuotaCore.build/"*.swift.o \
    "$BIN_DIR/CZstd.build/"*.c.o \
    "${APP_SOURCES[@]}" Tests/AppChecks/AppChecks.swift \
    -o "$BIN_DIR/QuotaAppChecks"
"$BIN_DIR/QuotaAppChecks" "$@"
