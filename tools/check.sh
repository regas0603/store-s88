#!/usr/bin/env bash
# tools/check.sh — TOOL CHECK: chạy sau mỗi lần convert app_package / sửa main_app.
#
#   bash tools/check.sh                          # app_package + apps/*/main_app + registry
#   bash tools/check.sh --main-app <dir> ...     # kiểm (thêm) main_app của app khác
#   bash tools/check.sh --pkg <dir>              # app_package ở chỗ khác (mặc định ../app_package)
#
# Làm gì:
#   0. cục bộ      : package_config + dist/dynamic_interface.yaml (git ignore)
#                    lệch repo (vd pull đổi ABI host) → tự pub get / dyniface
#                    bootstrap bằng Flutter engine; pub get đổi lock = FAIL
#   1. app_package : áp templates/module (modules/home_content.dart) + kiểm
#                    (modprep): API, nhánh VM không chạm web, ranh giới
#                    host/module, VERSION package không lệch host đóng băng
#                    (bắt AI tự nâng version — chấp nhận thay đổi:
#                    bash tools/snapshot.sh)
#   2. main_app    : apps/*/main_app (kể cả _reference) không kéo package module
#                    vào host (lệch version package host chỉ CẢNH BÁO — mỗi
#                    bản build có ABI riêng, registry tự tính patch chạy được)
#   3. registry    : validator release registry (không ai bị force mà không có
#                    link, file bytecode manifest trỏ tới còn đủ, …)
#
# Exit 0 = tất cả OK. Tool ngoài khác: setup.sh (máy build), snapshot.sh (chấp
# nhận host mới), dynpub.sh (publish).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/tools/cmd"

PKG="$ROOT/../app_package"
MAIN_APPS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG="${2:?--pkg cần thư mục}"; shift 2 ;;
    --main-app) MAIN_APPS+=("${2:?--main-app cần thư mục}"); shift 2 ;;
    -h|--help|help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "cờ lạ: $1 (xem: bash tools/check.sh --help)" >&2; exit 2 ;;
  esac
done
if [ ${#MAIN_APPS[@]} -eq 0 ]; then
  for d in "$ROOT"/apps/*/main_app; do [ -d "$d" ] && MAIN_APPS+=("$d"); done
fi
PKG="$(cd "$PKG" 2>/dev/null && pwd || echo "$PKG")"

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' CYN=$'\033[36m' BLD=$'\033[1m' RST=$'\033[0m'
RESULTS=()
FAIL=0
run_step() {  # <tên> <lệnh...>
  local name="$1"; shift
  echo
  echo "${BLD}══ $name ══${RST}"
  if "$@"; then RESULTS+=("  ${GRN}[PASS]${RST} $name")
  else RESULTS+=("  ${RED}[FAIL]${RST} $name"); FAIL=$((FAIL+1)); fi
}
# apps/<bundleId>/main_app → "<bundleId>" (tô màu) cho tiêu đề bước.
app_label() {
  local d="${1%/}"
  if [ "$(basename "$d")" = main_app ]; then echo "${CYN}$(basename "$(dirname "$d")")${RST}"
  else echo "$d"; fi
}

# Bước 0: package_config + dist/dynamic_interface.yaml là file sinh ở từng máy
# (git ignore). Sau `git pull` có đổi ABI host chúng cũ → bước 1 báo lỗi giả
# ("không còn trong package_config", "host CHƯA lộ"). Tự sinh lại bằng Flutter
# engine để mọi máy check giống nhau; pub get làm đổi lock = FAIL (Flutter sai).
sync_local() {
  if ! python3 -B "$T/localstate.py" pkgconfig; then
    echo "  → pub get (Flutter engine)…"
    local before; before="$(shasum -a 256 "$ROOT/app/pubspec.lock")"
    bash "$T/dynmod.sh" pubget || return 1
    if [ "$(shasum -a 256 "$ROOT/app/pubspec.lock")" != "$before" ]; then
      echo "  ${RED}[FAIL]${RST} pub get làm đổi app/pubspec.lock — Flutter / package lệch (CLAUDE.md §1)."
      echo "         Khôi phục: git checkout -- app/pubspec.lock && bash tools/cmd/dynmod.sh pubget"
      python3 -B "$T/lockcheck.py"
      return 1
    fi
    python3 -B "$T/localstate.py" pkgconfig || return 1
  fi
  if ! python3 -B "$T/localstate.py" iface; then
    echo "  → sinh lại anchor + iface: bash tools/cmd/dyniface.sh bootstrap…"
    bash "$T/dyniface.sh" bootstrap || return 1
    python3 -B "$T/localstate.py" iface || return 1
  fi
}
run_step "0. trạng thái cục bộ — package_config + dist/dynamic_interface.yaml khớp repo" sync_local
run_step "1. app_package — áp template + kiểm ($PKG)" bash "$T/modprep.sh" apply --pkg "$PKG"
for d in "${MAIN_APPS[@]}"; do
  run_step "2. $(app_label "$d") — main_app không kéo package module vào host" \
    env ABICHECK_ALLOW_ABI_DIFF=1 bash "$T/abicheck.sh" main-app "$d"
done
if [ -d "$ROOT/registry" ]; then
  run_step "3. registry — validator" python3 -B "$ROOT/tools/registry/registry.py" validate
else
  RESULTS+=("  ${YEL}[SKIP]${RST} 3. registry — chưa có registry/ (tạo ở lần build/patch đầu qua dynpub.sh)")
fi

echo
echo "${BLD}══ KẾT QUẢ CHECK ══${RST}"
printf '%s\n' "${RESULTS[@]}"
if [ "$FAIL" = 0 ]; then
  echo "${GRN}${BLD}OK${RST} — ra patch: bash tools/dynpub.sh → [2]"
else
  echo "${RED}${BLD}$FAIL bước FAIL${RST} — xem [FAIL] ở trên"
fi
exit "$FAIL"
