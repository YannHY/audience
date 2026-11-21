#!/bin/zsh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-simulator}"
if (( $# > 0 )); then shift; fi
case "$MODE" in
  simulator)
    xcodebuild -project "$APP_DIR/Audience.xcodeproj" -scheme Audience-iPad \
      -configuration Debug -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$APP_DIR/build/travail/iPad/DerivedData" CODE_SIGNING_ALLOWED=NO "$@" build
    mkdir -p "$APP_DIR/build/travail/iPad/Simulator"
    ditto "$APP_DIR/build/travail/iPad/DerivedData/Build/Products/Debug-iphonesimulator/Audience-iPad.app" \
      "$APP_DIR/build/travail/iPad/Simulator/Audience-iPad.app"
    ;;
  device)
    xcodebuild -project "$APP_DIR/Audience.xcodeproj" -scheme Audience-iPad \
      -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath "$APP_DIR/build/travail/iPad/DerivedData" "$@" build
    ;;
  archive)
    xcodebuild -project "$APP_DIR/Audience.xcodeproj" -scheme Audience-iPad \
      -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath "$APP_DIR/build/travail/iPad/DerivedData" \
      -archivePath "$APP_DIR/build/travail/iPad/Audience-iPad.xcarchive" "$@" archive
    ;;
  export)
    xcodebuild -exportArchive -archivePath "$APP_DIR/build/travail/iPad/Audience-iPad.xcarchive" \
      -exportPath "$APP_DIR/build/travail/iPad/Export" \
      -exportOptionsPlist "$APP_DIR/Resources/ExportOptions-iPad.plist" "$@"
    ;;
  testflight-archive)
    xcodebuild -project "$APP_DIR/Audience.xcodeproj" -scheme Audience-iPad \
      -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath "$APP_DIR/build/travail/TestFlight/DerivedData" \
      -archivePath "$APP_DIR/build/travail/TestFlight/Audience-iPad.xcarchive" "$@" archive
    ;;
  testflight-export)
    xcodebuild -exportArchive -archivePath "$APP_DIR/build/travail/TestFlight/Audience-iPad.xcarchive" \
      -exportPath "$APP_DIR/build/travail/TestFlight/Export" \
      -exportOptionsPlist "$APP_DIR/Resources/ExportOptions-TestFlight.plist" "$@"
    ;;
  *)
    printf 'Usage : %s [simulator|device|archive|export|testflight-archive|testflight-export] [réglages Xcode…]\n' "$0" >&2
    exit 2
    ;;
esac
