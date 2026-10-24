#!/usr/bin/env bash
# tools/cmd/unquarantine.sh — gỡ cờ com.apple.quarantine khỏi engine / SDK / cache.
#
#   bash tools/cmd/unquarantine.sh            # gỡ ở các thư mục mặc định
#   bash tools/cmd/unquarantine.sh <dir>...   # chỉ các thư mục chỉ định
#   bash tools/cmd/unquarantine.sh --check    # chỉ đếm, không gỡ (exit 1 nếu còn)
#
# Vì sao: thư mục chép qua AirDrop / zip / trình duyệt bị macOS gắn quarantine →
# mỗi binary (gen_snapshot, dart, impellerc, lib .dylib…) lần đầu chạy bị Gatekeeper
# chặn, phải "Allow Anyway" trong System Settings → Privacy & Security rồi chạy lại,
# lặp cho từng file. Gỡ cờ 1 lần trước là hết hỏi.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PARENT="$(dirname "$ROOT")"

CHECK=0
dirs=()
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) dirs+=("$a") ;;
  esac
done
if [ ${#dirs[@]} -eq 0 ]; then
  dirs=(
    "$PARENT/engine"
    "$PARENT/dart-sdk-build/flutter-framework/bin"
    "$PARENT/app_package"
    "$PARENT/main_app_package"
    "$ROOT"
    "$HOME/.pub-cache"
    "$HOME/Library/Caches/CocoaPods"
  )
fi

total=0
for d in "${dirs[@]}"; do
  [ -e "$d" ] || continue
  n="$(find "$d" -xattrname com.apple.quarantine 2>/dev/null | wc -l | tr -d ' ')"
  total=$((total + n))
  if [ "$n" = 0 ]; then
    echo "  [SKIP] $d: không có file quarantine"
  elif [ "$CHECK" = 1 ]; then
    echo "  [WARN] $d: $n file còn quarantine"
  else
    find "$d" -xattrname com.apple.quarantine -exec xattr -d com.apple.quarantine {} + 2>/dev/null || true
    left="$(find "$d" -xattrname com.apple.quarantine 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$left" = 0 ]; then
      echo "  [PASS] $d: gỡ quarantine $n file"
    else
      echo "  [WARN] $d: còn $left/$n file không gỡ được (thử: sudo xattr -dr com.apple.quarantine \"$d\")"
    fi
  fi
done
[ "$CHECK" = 1 ] && [ "$total" -gt 0 ] && exit 1
exit 0
