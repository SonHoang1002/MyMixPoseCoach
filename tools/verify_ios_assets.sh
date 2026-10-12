#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/tools/ios-assets.sha256"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Lỗi: thiếu manifest asset: tools/ios-assets.sha256" >&2
  exit 3
fi

asset_count=0
while read -r expected_sha256 relative_path; do
  [[ -z "${expected_sha256:-}" || "$expected_sha256" == \#* ]] && continue
  absolute_path="$ROOT_DIR/$relative_path"

  if [[ ! -f "$absolute_path" ]]; then
    echo "Lỗi: thiếu asset bắt buộc: $relative_path" >&2
    exit 3
  fi

  actual_sha256="$(shasum -a 256 "$absolute_path" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Lỗi: checksum không đúng cho $relative_path" >&2
    echo "  cần: $expected_sha256" >&2
    echo "  có:  $actual_sha256" >&2
    exit 3
  fi

  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && ! git -C "$ROOT_DIR" ls-files --error-unmatch "$relative_path" >/dev/null 2>&1; then
    echo "Lỗi: asset có trên máy nhưng chưa được Git theo dõi: $relative_path" >&2
    exit 3
  fi
  (( asset_count += 1 ))
done < "$MANIFEST"

if (( asset_count != 15 )); then
  echo "Lỗi: manifest phải có đúng 15 asset runtime, hiện có $asset_count." >&2
  exit 3
fi

echo "PASS: đủ 2 model và 13 template; checksum và trạng thái Git đều hợp lệ."
