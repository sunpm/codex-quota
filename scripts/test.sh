#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
swift run --disable-sandbox QuotaCoreChecks
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
APP_SOURCES=()
for source in Sources/CodexQuotaDock/*.swift; do
    if [[ "$source" != */App.swift ]]; then APP_SOURCES+=("$source"); fi
done
# 与正式 App 使用同一份实现，注入模拟客户端；不依赖 XCTest / 完整 Xcode。
swiftc -parse-as-library -I "$BIN_DIR/Modules" \
    "$BIN_DIR/QuotaCore.build/"*.swift.o \
    "${APP_SOURCES[@]}" Tests/AppChecks/AppChecks.swift \
    -o "$BIN_DIR/QuotaAppChecks"
"$BIN_DIR/QuotaAppChecks" "$@"
