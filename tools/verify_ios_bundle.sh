#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/tools/ios-assets.sha256"
APP_BUNDLE="${1:-}"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "Cách dùng: $0 /duong/dan/myposecoach1.app" >&2
  exit 4
fi

asset_count=0
while read -r expected_sha256 relative_path; do
  [[ -z "${expected_sha256:-}" || "$expected_sha256" == \#* ]] && continue
  filename="${relative_path##*/}"
  match_count="$(find "$APP_BUNDLE" -type f -name "$filename" -print | awk 'END { print NR + 0 }')"
  if (( match_count != 1 )); then
    echo "Lỗi: bundle phải chứa đúng một file $filename, tìm thấy $match_count." >&2
    exit 4
  fi
  found_path="$(find "$APP_BUNDLE" -type f -name "$filename" -print -quit)"
  actual_sha256="$(shasum -a 256 "$found_path" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Lỗi: asset trong bundle sai checksum: $filename" >&2
    exit 4
  fi
  (( asset_count += 1 ))
done < "$MANIFEST"

if (( asset_count != 15 )); then
  echo "Lỗi: chỉ kiểm tra được $asset_count/15 asset trong app bundle." >&2
  exit 4
fi

missing_runtime_dependency=0
while IFS= read -r -d '' binary; do
  if ! file "$binary" | grep -q 'Mach-O'; then
    continue
  fi
  while IFS= read -r dependency; do
    [[ "$dependency" == @rpath/* ]] || continue
    relative_path="${dependency#@rpath/}"
    if [[ ! -e "$APP_BUNDLE/$relative_path" \
       && ! -e "$APP_BUNDLE/Frameworks/$relative_path" ]]; then
      echo "Lỗi: $(basename "$binary") cần $dependency nhưng app bundle không chứa file đó." >&2
      missing_runtime_dependency=1
    fi
  done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }')
done < <(find "$APP_BUNDLE" -type f -print0)

if (( missing_runtime_dependency != 0 )); then
  exit 4
fi

echo "PASS: app bundle chứa đủ asset và toàn bộ dependency @rpath."
