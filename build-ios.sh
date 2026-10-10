#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Lỗi: MediaPipe 1.1.0 cần Mac Apple Silicon để build iOS Simulator arm64." >&2
  echo "Trên Mac Intel chỉ có thể build đích thiết bị iOS arm64." >&2
  exit 2
fi

"$ROOT_DIR/bootstrap-ios.sh"

xcodebuild build \
  -workspace "$ROOT_DIR/myposecoach1/myposecoach1.xcworkspace" \
  -scheme myposecoach1 \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
