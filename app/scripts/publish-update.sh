#!/bin/zsh
# Prépare les fichiers à déposer sur le site ; aucun téléversement n’est effectué.
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$APP_DIR/build/travail/Audience-macOS.zip}"
PREFIX='https://www.ralentirtravaux.com/apps/audience/mac/'
ACCOUNT='audience-mac'
UPDATES="$APP_DIR/build/travail/updates"
SPARKLE_BIN="${SPARKLE_BIN:-$APP_DIR/build/travail/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
if [[ ! -x "$SPARKLE_BIN/generate_appcast" || ! -f "$ARCHIVE" ]]; then
  print -u2 'Archive ou outils Sparkle absents : lancez scripts/build.sh au préalable (ou définissez SPARKLE_BIN).'
  exit 1
fi
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audience-update.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$STAGE_DIR"
APP="$STAGE_DIR/Audience.app"
PLIST="$APP/Contents/Info.plist"
codesign --verify --deep --strict --all-architectures "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" != 'fr.audience.native' ]]; then
  print -u2 'Cette archive ne contient pas Audience.'
  exit 1
fi
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)"
if [[ "$PUBLIC_KEY" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")" ]]; then
  print -u2 'La clé du trousseau ne correspond pas à la clé publique de cette app.'
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST")" != "${PREFIX}appcast.xml" ]]; then
  print -u2 'Le flux de cette archive ne correspond pas au dossier de publication.'
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
NAME="Audience-${VERSION}-${BUILD}-macOS.zip"
mkdir -p "$UPDATES"
# Une URL déjà publiée doit toujours désigner la même archive signée.
if [[ -e "$UPDATES/$NAME" ]] && ! cmp -s "$ARCHIVE" "$UPDATES/$NAME"; then
  print -u2 "Une archive différente existe déjà pour $VERSION ($BUILD). Augmentez les versions avant de publier."
  exit 1
fi
cp "$ARCHIVE" "$UPDATES/$NAME"
"$SPARKLE_BIN/generate_appcast" --account "$ACCOUNT" \
  --download-url-prefix "$PREFIX" \
  --link 'https://www.ralentirtravaux.com/apps/audience/' "$UPDATES"
printf '\nFichiers à déposer dans %s :\n%s\n' "$PREFIX" "$UPDATES"
