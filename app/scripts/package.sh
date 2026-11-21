#!/bin/zsh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
  print -u2 'La notarisation nécessite SIGN_IDENTITY avec un certificat Developer ID Application.'
  exit 1
fi
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audience-package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
# Stage outside iCloud, whose Finder attributes can invalidate a bundle signature.
ditto --norsrc --noextattr "$APP_DIR/build/Audience.app" "$STAGE_DIR/Audience.app"
xattr -cr "$STAGE_DIR/Audience.app"
# Sign nested Sparkle components from the inside out, retaining Downloader entitlements.
sign_component() {
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --preserve-metadata=entitlements "$1"
  else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements "$1"
  fi
}
SPARKLE="$STAGE_DIR/Audience.app/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  print -u2 'Sparkle.framework est absent : recompilez avec scripts/build.sh.'
  exit 1
fi
sign_component "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign_component "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign_component "$SPARKLE/Versions/B/Autoupdate"
sign_component "$SPARKLE/Versions/B/Updater.app"
sign_component "$SPARKLE"
sign_component "$STAGE_DIR/Audience.app"
codesign --verify --deep --strict --all-architectures "$STAGE_DIR/Audience.app"
ditto -c -k --keepParent --norsrc --noextattr "$STAGE_DIR/Audience.app" "$STAGE_DIR/Audience-macOS.zip"
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$STAGE_DIR/Audience-macOS.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
    > "$APP_DIR/build/travail/Audience-notarization.json"
  if [[ "$(plutil -extract status raw -o - "$APP_DIR/build/travail/Audience-notarization.json")" != "Accepted" ]]; then
    print -u2 "Notarisation refusée : consultez $APP_DIR/build/travail/Audience-notarization.json et le journal notarytool."
    exit 1
  fi
  xcrun stapler staple "$STAGE_DIR/Audience.app"
  xcrun stapler validate "$STAGE_DIR/Audience.app"
  spctl --assess --type execute --verbose=2 "$STAGE_DIR/Audience.app"
  # ZIP files cannot be stapled; recreate the archive with the app's ticket.
  rm "$STAGE_DIR/Audience-macOS.zip"
  ditto -c -k --keepParent --norsrc --noextattr "$STAGE_DIR/Audience.app" "$STAGE_DIR/Audience-macOS.zip"
fi
# The archive is the distributable artifact; iCloud may immediately restore
# FinderInfo on the convenience copy below, even after xattr clears it.
mv -f "$STAGE_DIR/Audience-macOS.zip" "$APP_DIR/build/travail/Audience-macOS.zip"
ditto --norsrc --noextattr "$STAGE_DIR/Audience.app" "$APP_DIR/build/Audience.app"
xattr -cr "$APP_DIR/build/Audience.app"
if ! codesign --verify --deep --strict --all-architectures "$APP_DIR/build/Audience.app"; then
  print -u2 'La copie .app du projet a des attributs iCloud : décompressez le ZIP hors iCloud pour utiliser la version vérifiée.'
fi
codesign --display --verbose=2 "$STAGE_DIR/Audience.app"
printf '\nArchive : %s\n' "$APP_DIR/build/travail/Audience-macOS.zip"
