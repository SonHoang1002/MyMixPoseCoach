#!/bin/zsh
# Kiểm tra cú pháp Swift của TOÀN BỘ app iOS mà KHÔNG cần mở Xcode.
# Dùng khi port code từ Android: chạy lệnh này để bắt lỗi trước khi báo xong.
#
#   ./myposecoach1/typecheck.sh          # kiểm tra toàn bộ
#
# Thoát mã 0 = không lỗi; mã khác = có lỗi (in ra stdout).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
FR=(
  -F myposecoach1/Pods/MediaPipeTasksVision/frameworks/MediaPipeTasksVision.xcframework/ios-arm64_x86_64-simulator
  -F myposecoach1/Pods/MediaPipeTasksCommon/frameworks/MediaPipeTasksCommon.xcframework/ios-arm64_x86_64-simulator
)
SOURCES=( myposecoach1/myposecoach1/**/*.swift(N) )

xcrun swiftc -typecheck \
  -sdk "$SDK" \
  -target arm64-apple-ios18.0-simulator \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  "${FR[@]}" \
  "${SOURCES[@]}"
