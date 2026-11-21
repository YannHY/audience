#!/bin/zsh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/audience-clang-cache"
xcodebuild -project "$APP_DIR/Audience.xcodeproj" -scheme Audience \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$APP_DIR/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO "$@" build
mkdir -p "$APP_DIR/build"
ditto "$APP_DIR/build/DerivedData/Build/Products/Release/Audience.app" "$APP_DIR/build/Audience.app"
"$APP_DIR/scripts/package.sh"
printf '\nApplication : %s\n' "$APP_DIR/build/Audience.app"
