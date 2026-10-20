#!/usr/bin/env bash
# tools/cmd/modprep.sh — Biến package SINH RA (convert_to_package.sh của
# s88-flutter) thành MODULE dynmod. Chạy lại SAU MỖI LẦN convert, vì convert
# xoá sạch thư mục đích (mất modules/).
#
#   bash tools/cmd/modprep.sh apply [--pkg <dir>] [--no-packages] [--no-check]
#        # chép templates/module/** vào <dir> (bỏ đuôi .tmpl) rồi chạy check
#        # (--no-check: chỉ chép — setup.sh dùng để gen lại iface TRƯỚC khi check)
#   bash tools/cmd/modprep.sh check [--pkg <dir>] [--no-packages]
#        # chỉ kiểm, không ghi gì
#
# check gồm:
#   1. <dir> là package app_package
#   2. file template đã áp và GIỐNG HỆT template (không ai sửa tay bản áp)
#   3. API package khớp template (SunSports.init, SunSportsApp)
#   4. package_config của HOST có app_package -> <dir> (module compile bằng nó)
#   5. nhánh VM (iOS/Android) không import web (tools/cmd/modprep/vm_web_scan.py)
#   6. ràng buộc version app_package thoả ABI đóng băng (abicheck.sh app-package)
#   7. ranh giới host/module P1 (dyniface.sh packages check) — tắt bằng --no-packages
#
# Mặc định <dir> = ../app_package. Template: templates/module/.
# Chi tiết: docs/dynmod_build_once_plan.md (P2).

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${DYNMOD_APP:-$ROOT/app}"
TPL="$ROOT/templates/module"
PKGCFG="$APP/.dart_tool/package_config.json"

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
ok()   { echo "  ${GRN}[PASS]${RST} $1"; }
info() { echo "  [i]    $1"; }
bad()  { echo "  ${RED}[FAIL]${RST} $1" >&2; FAILS=$((FAILS+1)); }
die()  { echo "  ${RED}[FAIL]${RST} $1" >&2; exit 1; }
FAILS=0

# Thiếu template = không có entry module → iface sinh ra thiếu hẳn phần module
# (host build ra ABI sai) mà các bước sau vẫn "chạy được" → dừng ngay.
[ -f "$TPL/modules/home_content.dart.tmpl" ] \
  || die "thiếu $TPL/modules/home_content.dart.tmpl (entry module) — khôi phục templates/module/ (phải commit vào git) rồi chạy lại"

# Đường dẫn tương đối (trong template) của mọi file template, đã bỏ .tmpl.
tpl_files() { (cd "$TPL" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | sort); }
dest_of() { echo "${1%.tmpl}"; }

cmd_check() {
  local pkg="$1" packages="$2"
  echo "== modprep check $pkg =="
  [ -f "$pkg/pubspec.yaml" ] || die "không thấy $pkg/pubspec.yaml"
  [ "$(awk '/^name:/{print $2; exit}' "$pkg/pubspec.yaml")" = app_package ] \
    && ok "package app_package" || bad "pubspec name khác app_package"

  local f
  while IFS= read -r f; do
    local d; d="$(dest_of "$f")"
    if [ ! -f "$pkg/$d" ]; then bad "$d chưa áp — chạy: bash tools/cmd/modprep.sh apply"
    elif cmp -s "$TPL/$f" "$pkg/$d"; then ok "$d khớp template"
    else bad "$d KHÁC template (sửa template trong templates/module/, đừng sửa bản áp)"; fi
  done < <(tpl_files)

  # API mà templates/module/modules/home_content.dart.tmpl dùng — đổi template thì sửa ở đây.
  grep -qE "static Future<List<Override>> init\(" "$pkg/lib/sun_sports_init.dart" 2>/dev/null \
    && ok "API SunSports.init() -> List<Override>" || bad "lib/sun_sports_init.dart thiếu SunSports.init() -> List<Override>"
  grep -qE "class SunSportsApp\b" "$pkg/lib/sun_sports_root.dart" 2>/dev/null \
    && ok "API SunSportsApp" || bad "lib/sun_sports_root.dart thiếu class SunSportsApp"

  if [ ! -f "$PKGCFG" ]; then
    bad "host chưa pub get ($PKGCFG) — chạy: bash tools/cmd/dynmod.sh pubget"
  else
    local where
    where="$(python3 -c 'import json,os,sys
pc=json.load(open(sys.argv[1])); base=os.path.dirname(os.path.abspath(sys.argv[1]))
for p in pc["packages"]:
    if p["name"]=="app_package":
        r=p["rootUri"].replace("file://","")
        print(os.path.normpath(r if r.startswith("/") else os.path.join(base,r)))' "$PKGCFG")"
    if [ "$where" = "$(cd "$pkg" && pwd)" ]; then ok "host package_config: app_package -> $where"
    else bad "host package_config trỏ app_package -> '${where:-<không có>}', không phải $pkg"; fi
    python3 "$ROOT/tools/cmd/modprep/vm_web_scan.py" --pkg "$pkg" --package-config "$PKGCFG" \
      || FAILS=$((FAILS+1))
    # Ràng buộc version của app_package phải thoả host đóng băng (AI tự nâng
    # version → pub get host nâng theo → bytecode lệch host đã phát hành).
    if [ -f "$ROOT/configs/abi/module_abi.json" ]; then
      bash "$ROOT/tools/cmd/abicheck.sh" app-package "$pkg" || FAILS=$((FAILS+1))
    else
      info "chưa có configs/abi/module_abi.json — bỏ qua kiểm version (dynpub release sẽ chụp)"
    fi
    if [ "$packages" = 1 ]; then
      python3 "$ROOT/tools/cmd/dyniface/classify_packages.py" check || FAILS=$((FAILS+1))
    fi
  fi

  echo
  [ "$FAILS" = 0 ] && { echo "== modprep: OK — module sẵn sàng compile (dynpush.sh patch) =="; return 0; }
  echo "== modprep: $FAILS mục FAIL =="
  return 1
}

cmd_apply() {
  local pkg="$1" packages="$2" check="$3"
  [ -f "$pkg/pubspec.yaml" ] || die "không thấy $pkg/pubspec.yaml — sinh app_package trước: cd ../s88-flutter && bash convert_to_package.sh --env=prod --hardcode-version (ra ../app_package), rồi chạy lại"
  echo "== modprep apply templates/module -> $pkg =="
  local f
  while IFS= read -r f; do
    local d; d="$(dest_of "$f")"
    mkdir -p "$(dirname "$pkg/$d")"
    cp "$TPL/$f" "$pkg/$d"
    info "áp $d"
  done < <(tpl_files)
  [ "$check" = 1 ] || return 0
  echo
  cmd_check "$pkg" "$packages"
}

sub="${1:-}"; shift || true
pkg="$ROOT/../app_package"; packages=1; check=1
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) pkg="$2"; shift 2 ;;
    --no-packages) packages=0; shift ;;
    --no-check) check=0; shift ;;
    *) die "cờ lạ: $1" ;;
  esac
done
pkg="$(cd "$pkg" 2>/dev/null && pwd || echo "$pkg")"
case "$sub" in
  apply) cmd_apply "$pkg" "$packages" "$check" ;;
  check) cmd_check "$pkg" "$packages" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
