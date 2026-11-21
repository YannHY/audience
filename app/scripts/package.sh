#!/bin/zsh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audience-package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
# Stage outside iCloud, whose Finder attributes can invalidate a bundle signature.
ditto --norsrc --noextattr "$APP_DIR/build/Audience.app" "$STAGE_DIR/Audience.app"
xattr -cr "$STAGE_DIR/Audience.app"
codesign --force --deep --sign - "$STAGE_DIR/Audience.app"
codesign --verify --deep --strict "$STAGE_DIR/Audience.app"
ditto -c -k --keepParent --norsrc --noextattr "$STAGE_DIR/Audience.app" "$APP_DIR/build/Audience-macOS.zip"
printf '\nArchive : %s\n' "$APP_DIR/build/Audience-macOS.zip"
