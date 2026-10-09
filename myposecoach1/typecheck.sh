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
# Không còn framework ngoài: nhận diện khung xương dùng Apple Vision (trong SDK).
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
  "${SOURCES[@]}"
