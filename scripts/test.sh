#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
pnpm build
cargo check --locked --manifest-path src-tauri/Cargo.toml
if [[ "$(uname -s)" == "Darwin" ]]; then
    bash scripts/check-legacy.sh "$@"
fi
