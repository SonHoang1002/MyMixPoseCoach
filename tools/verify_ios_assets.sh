#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

check_asset() {
  local relative_path="$1"
  local expected_sha256="$2"
  local absolute_path="$ROOT_DIR/$relative_path"

  if [[ ! -f "$absolute_path" ]]; then
    echo "Lỗi: thiếu asset bắt buộc: $relative_path" >&2
    exit 3
  fi

  local actual_sha256
  actual_sha256="$(shasum -a 256 "$absolute_path" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Lỗi: checksum không đúng cho $relative_path" >&2
    echo "  cần: $expected_sha256" >&2
    echo "  có:  $actual_sha256" >&2
    exit 3
  fi

  if ! git -C "$ROOT_DIR" ls-files --error-unmatch "$relative_path" >/dev/null 2>&1; then
    echo "Lỗi: asset có trên máy nhưng chưa được Git theo dõi: $relative_path" >&2
    exit 3
  fi
}

check_asset \
  "myposecoach1/myposecoach1/pose_landmarker_full.task" \
  "4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad"

check_asset \
  "myposecoach1/myposecoach1/geocalib/geocalib-mang-int8.onnx" \
  "7e63366ef8b9acbe4a2350633d415015c5f4143fc9605057d5ca4734c73a5814"

echo "PASS: model iOS đầy đủ và đúng checksum."
