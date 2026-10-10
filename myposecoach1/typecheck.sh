#!/bin/zsh
# Kiểm tra TOÀN BỘ app cùng MediaPipe, ML Kit và ONNX Runtime.
#
#   ./myposecoach1/typecheck.sh          # kiểm tra toàn bộ
#
# Thoát mã 0 = không lỗi; mã khác = có lỗi (in ra stdout).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v pod >/dev/null; then
  echo "CocoaPods is required: sudo gem install cocoapods" >&2
  exit 2
fi
cd myposecoach1
pod install
xcodebuild -resolvePackageDependencies -workspace myposecoach1.xcworkspace -scheme myposecoach1
xcodebuild build \
  -workspace myposecoach1.xcworkspace \
  -scheme myposecoach1 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
