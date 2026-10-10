#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/myposecoach1"
WORKSPACE="$APP_DIR/myposecoach1.xcworkspace"
COCOAPODS_VERSION="1.16.2"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Lỗi: iOS chỉ có thể bootstrap/build trên macOS." >&2
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Lỗi: chưa có Xcode Command Line Tools. Chạy: xcode-select --install" >&2
  exit 2
fi

"$ROOT_DIR/tools/verify_ios_assets.sh"

current_pod_version=""
if command -v pod >/dev/null 2>&1; then
  current_pod_version="$(pod --version 2>/dev/null || true)"
fi

if [[ "$current_pod_version" != "$COCOAPODS_VERSION" ]]; then
  if ! command -v ruby >/dev/null 2>&1 || ! command -v gem >/dev/null 2>&1; then
    echo "Lỗi: cần Ruby/RubyGems để cài CocoaPods $COCOAPODS_VERSION." >&2
    exit 2
  fi

  echo "Đang cài CocoaPods $COCOAPODS_VERSION cho user hiện tại..."
  gem install --user-install cocoapods --version "$COCOAPODS_VERSION" --no-document
  user_gem_bin="$(ruby -r rubygems -e 'print Gem.user_dir')/bin"
  export PATH="$user_gem_bin:$PATH"
fi

if ! command -v pod >/dev/null 2>&1 || [[ "$(pod --version)" != "$COCOAPODS_VERSION" ]]; then
  echo "Lỗi: không gọi được CocoaPods $COCOAPODS_VERSION sau khi cài." >&2
  exit 2
fi

echo "Đang khôi phục CocoaPods từ Podfile.lock..."
(
  cd "$APP_DIR"
  pod install
)

echo "Đang khôi phục Swift Package từ Package.resolved..."
xcodebuild -resolvePackageDependencies \
  -workspace "$WORKSPACE" \
  -scheme myposecoach1

echo "Bootstrap hoàn tất: $WORKSPACE"

if [[ "${1:-}" == "--open" ]]; then
  open "$WORKSPACE"
fi
