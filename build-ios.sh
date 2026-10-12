#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

"$ROOT_DIR/bootstrap-ios.sh"

xcodebuild build \
  -workspace "$ROOT_DIR/myposecoach1/myposecoach1.xcworkspace" \
  -scheme myposecoach1 \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO

APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/myposecoach1.app"
"$ROOT_DIR/tools/verify_ios_bundle.sh" "$APP_BUNDLE"

echo "Build sạch hoàn tất: $APP_BUNDLE"
