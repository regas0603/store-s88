#!/usr/bin/env bash
# tools/snapshot.sh — TOOL SNAPSHOT: chấp nhận host MỚI làm "ABI đóng băng".
#
#   bash tools/snapshot.sh        # xem thay đổi → hỏi y/N → chụp mốc → check
#   bash tools/snapshot.sh -y     # không hỏi (CI)
#
# Dùng khi CỐ Ý đổi host: đổi engine (configs/flutter.json), thêm/bỏ/chuyển
# package host (configs/abi/host_packages.yaml), sinh lại interface (setup.sh).
# Làm 3 việc:
#   1. In thay đổi: host vs ABI đóng băng + ràng buộc version app_package.
#   2. Chụp mốc mới: configs/abi/app_package_deps.json + configs/abi/module_abi.json
#      (abicheck.sh app-package --accept + abicheck.sh snapshot).
#   3. Chạy tools/check.sh.
#
# Mốc chụp từ NGUỒN host (engine checkout + app/pubspec.lock + iface) —
# không cần build host trước. Sau khi chụp: bytecode cũ KHÔNG chạy trên host
# mới → bash tools/dynpub.sh patch + build lại MỌI app (bash tools/dynpub.sh).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/tools/cmd"

YES=0
case "${1:-}" in
  "") ;;
  -y|--yes) YES=1 ;;
  -h|--help|help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "cờ lạ: $1 (xem: bash tools/snapshot.sh --help)" >&2; exit 2 ;;
esac

echo "══ Thay đổi so với mốc đang đóng băng ══"
CHANGED=0
if [ -f "$ROOT/configs/abi/module_abi.json" ]; then
  bash "$T/abicheck.sh" host || CHANGED=1
else
  echo "  [i]    chưa có configs/abi/module_abi.json — chụp lần đầu"
  CHANGED=1
fi
PKG_OUT="$(bash "$T/abicheck.sh" app-package)" || CHANGED=1
echo "$PKG_OUT"
grep -q "ĐỔI so với mốc" <<<"$PKG_OUT" && CHANGED=1

if [ "$CHANGED" = 0 ]; then
  echo
  echo "Host + app_package khớp mốc — không có gì để chụp."
  exit 0
fi

echo
echo "Chấp nhận host MỚI → bytecode cũ KHÔNG chạy trên host này nữa (phải dynpub patch + build lại MỌI app)."
if [ "$YES" = 0 ]; then
  read -r -p "Chụp mốc mới? [y/N] " ans
  case "$ans" in y|Y|yes) ;; *) echo "Huỷ — không ghi gì."; exit 1 ;; esac
fi

echo
echo "══ Chụp mốc ══"
# Snapshot TRƯỚC: module_abi.json phải phản ánh host hiện tại (lock mới) để
# app-package --accept kiểm ràng buộc đúng version vừa nhận (vd ^2.5.6 vs 2.5.6).
# Thứ tự cũ (app-package → snapshot) luôn fail khi option [11] nâng version.
bash "$T/abicheck.sh" snapshot || exit 1
bash "$T/abicheck.sh" app-package --accept || { echo "app_package còn vi phạm ABI — sửa [FAIL] ở trên rồi chạy lại"; exit 1; }

echo
bash "$ROOT/tools/check.sh"
RC=$?
[ "$RC" = 0 ] && echo "Bước tiếp: bash tools/dynpub.sh patch   →   bash tools/dynpub.sh (build host)"
exit "$RC"
