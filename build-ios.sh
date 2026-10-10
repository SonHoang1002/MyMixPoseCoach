#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$ROOT_DIR/bootstrap-ios.sh"

xcodebuild build \
  -workspace "$ROOT_DIR/myposecoach1/myposecoach1.xcworkspace" \
  -scheme myposecoach1 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
