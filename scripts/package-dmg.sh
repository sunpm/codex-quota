#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
case "${1:-}" in
    arm64) TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin" ;;
    *) printf '用法：bash scripts/package-dmg.sh arm64|x86_64\n' >&2; exit 1 ;;
esac
exec bash scripts/build.sh --target "$TARGET" --bundles app,dmg
