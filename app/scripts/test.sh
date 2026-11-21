#!/bin/zsh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/audience-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/audience-module-cache"
swift test --package-path "$APP_DIR" --scratch-path "$APP_DIR/.build" --disable-sandbox
