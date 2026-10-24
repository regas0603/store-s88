#!/usr/bin/env bash
# tools/cmd/dyniface.sh — Tool DU NHAT cho dynamic_interface.yaml + compile module B.
#
# Tong hop: gen_dynamic_interface.py +
# augment_from_validate.py + fix_disambiguation.py + repair_containers.py
# (cac script con nam trong tools/cmd/dyniface/).
#
# LENH:
#   bash tools/cmd/dyniface.sh gen [--anchor <dill>] [--regen]
#        # Sinh baseline yaml TU DONG tu anchor dill + platform dill.
#        # Khong --regen: chi chay khi yaml chua ton tai (bao ve file dang tot).
#
#   bash tools/cmd/dyniface.sh compile [module.dart] [-o out.bytecode] [--anchor <dill>] [--regen]
#        # 1 LENH COMPILE THAT: gen (neu can) -> dart2bytecode --validate 1 LAN
#        # (KHONG augment — iface la hop dong host, P4). Ra .bytecode tai -o
#        # (mac dinh dist/), rename content-addressed <ten>_<hash8>.bytecode.
#
#   bash tools/cmd/dyniface.sh bootstrap
#        # LUON build lai anchor tu app/main.dart + gen lai iface (truoc khi
#        # build host / setup).
#
#   bash tools/cmd/dyniface.sh loop [module.dart] [-o out.bytecode] [--rounds N] [--no-augment]
#        # (CU) loop augment iface tu loi — khong dung trong pipeline nua.
#
#   bash tools/cmd/dyniface.sh status
#        # Trang thai: anchor, yaml (so entry), bytecode (sha256).
#
#   bash tools/cmd/dyniface.sh packages [--write [--force]] | packages check
#        # P1: phan tang package host/module -> configs/abi/host_packages.yaml
#        # (docs/dynmod_build_once_plan.md). check: exit 1 neu manifest lech.
#
# Bien moi truong (giu dung quy uoc cua tools/cmd/dynmod.sh):
#   DYNMOD_WORK, DYNMOD_APP, DYNMOD_IFACE, DYNMOD_ENGINE_SRC
#   DYNIFACE_ANCHOR (anchor dill; mac dinh <out>.anchor.dill ben canh -o)
#
# Flow lay duoc tu G4 (03/10/2026): baseline gen chi phu library trong closure
# HOST; private member bi module override (dio _RequestConfig, dart:io
# FileSystemEntity, dart:core DateTime...) phai augment tu loi compile — loop
# tu dong den khi dart2bytecode exit 0.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${DYNMOD_WORK:-$(dirname "$ROOT")/dart-sdk-build}"  # derive từ vị trí project (anh em của repo)
APP="${DYNMOD_APP:-$ROOT/app}"
IFACE="${DYNMOD_IFACE:-$ROOT/dist/dynamic_interface.yaml}"
# Engine DÙNG (chỉ cần out/ + sdk/lib + lib/ui): ưu tiên ../engine — bản chép gọn
# (~4,3GB thay vì ~50GB checkout, tạo/cập nhật bằng: bash tools/cmd/dynmod.sh backup).
_ENG_DEF="$(dirname "$ROOT")/engine"; [ -d "$_ENG_DEF/out" ] || _ENG_DEF="$WORK/flutter-framework/engine/src"
ENGINE_SRC="${DYNMOD_ENGINE_SRC:-$_ENG_DEF}"
export DYNMOD_ENGINE_SRC="$ENGINE_SRC"  # python dyniface/*.py đọc sdk/lib, lib/ui, platform dill từ đây
OUTDIR="$ENGINE_SRC/out"
H="$OUTDIR/host_release_arm64"
ENGINE_HOME="${DYNMOD_ENGINE_HOME:-$(dirname "$ROOT")/engine}"
LOGDIR="$ENGINE_HOME/logs"
mkdir -p "$LOGDIR"

DIF="$ROOT/tools/cmd/dyniface"

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
ok()   { echo "  ${GRN}[PASS]${RST} $1"; }
info() { echo "  [i]    $1"; }
die()  { echo "  ${RED}[FAIL]${RST} $1" >&2; exit 1; }

platform_dill() {
  ls "$OUTDIR"/*/flutter_patched_sdk/platform_strong.dill 2>/dev/null | head -1
}

cmd_status() {
  local anchor="${DYNIFACE_ANCHOR:-$ROOT/dist/app_content.anchor.dill}"
  echo "== dyniface status =="
  if [ -f "$anchor" ]; then
    ok "anchor: $anchor ($(stat -f%z "$anchor") B)"
  else
    info "anchor chua co: $anchor (build host A + anchor truoc)"
  fi
  if [ -f "$IFACE" ]; then
    ok "iface: $IFACE ($(grep -c 'library:' "$IFACE") entry, $(wc -l < "$IFACE" | tr -d ' ') dong)"
  else
    info "iface chua co — chay: bash tools/cmd/dyniface.sh gen"
  fi
  local bc found=0
  for bc in "$ROOT"/dist/*.bytecode; do
    [ -f "$bc" ] || continue
    found=1
    ok "$(basename "$bc"): $(stat -f%z "$bc") B, sha256 $(shasum -a 256 "$bc" | cut -c1-16)…"
  done
  [ "$found" = 1 ] || info "chua co .bytecode nao trong dist/"
}

cmd_gen() {
  local anchor="${DYNIFACE_ANCHOR:-}"
  local regen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --anchor) anchor="$2"; shift 2 ;;
      --regen)  regen=1; shift ;;
      *) die "co la: $1 (gen [--anchor <dill>] [--regen])" ;;
    esac
  done
  [ -n "$anchor" ] || anchor="$ROOT/dist/app_content.anchor.dill"
  [ -f "$anchor" ] || die "khong co anchor dill $anchor — build host A + anchor truoc"
  local P; P="$(platform_dill)"
  [ -n "$P" ] || die "khong thay platform_strong.dill trong $OUTDIR"
  if [ -f "$IFACE" ] && [ "$regen" = 0 ]; then
    info "iface da ton tai ($IFACE) — bo qua gen. Dung --regen de sinh lai."
    return 0
  fi
  # Không backup: iface tái lập được 100% từ anchor + configs/abi/host_packages.yaml
  # + configs/abi/dynamic_interface.extra.yaml (P4).
  echo "== gen baseline iface tu anchor $(basename "$anchor") =="
  DYNIFACE_ANCHOR="$anchor" python3 "$DIF/gen_dynamic_interface.py" || die "gen baseline that bai"
  ok "gen xong: $IFACE ($(grep -c 'library:' "$IFACE") entry)"
}

# run_tool <py> <log> — chay 1 buoc augment; in output, rong -> exit non-zero da biet
cmd_loop() {
  # MAC DINH: module = ../app_package (host = $ROOT/app).
  local mod="$ROOT/../app_package/modules/home_content.dart" outf="$ROOT/dist/app_content.bytecode" rounds=40 augment=1
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) outf="$2"; shift 2 ;;
      --rounds) rounds="$2"; shift 2 ;;
      --anchor) export DYNIFACE_ANCHOR="$2"; shift 2 ;;
      --no-augment) augment=0; shift ;;
      *) mod="$1"; shift ;;
    esac
  done
  [ -f "$mod" ] || die "khong thay module $mod"
  [ -f "$IFACE" ] || die "chua co $IFACE — chay: bash tools/cmd/dyniface.sh gen"
  local AOT="$H/dart-sdk/bin/dartaotruntime"
  [ -x "$AOT" ] || die "thieu engine host ($AOT) — chay: bash tools/cmd/dynmod.sh engine host"
  local P; P="$(platform_dill)"
  [ -n "$P" ] || die "khong thay platform_strong.dill"
  local anchor="${DYNIFACE_ANCHOR:-${outf%.bytecode}.anchor.dill}"
  [ -f "$anchor" ] || die "khong co anchor $anchor — build truoc (dynmod.sh module)"
  mkdir -p "$(dirname "$outf")"
  local log="$LOGDIR/dyniface-loop-$(date +%H%M%S).log"
  echo "== loop compile $mod (anchor $(basename "$anchor")) =="
  echo "  log: $log"
  local i rc out stage h8 dir stem final
  for i in $(seq 1 "$rounds"); do
    rc=0
    ( cd "$APP" && "$AOT" "$H/gen/dart2bytecode.dart.snapshot" \
        --platform "$P" --target flutter \
        --import-dill "$anchor" --validate "$IFACE" \
        --packages "$APP/.dart_tool/package_config.json" \
        --allow-dynamic-calls-in-dynamic-modules \
        -Ddart.vm.product=true --output "$outf" "$mod" ) >"$log" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then
      # Rename content-addressed: <ten>.bytecode -> <ten>_<hash8>.bytecode
      # (hash = sha256 CONTENT của file, không metadata — cùng quy ước
      # dynpush.sh patch). File đã rename từ lần trước -> bỏ suffix cũ.
      h8="$(shasum -a 256 "$outf" | cut -c1-8)"
      dir="$(dirname "$outf")"
      stem="$(basename "${outf%.bytecode}")"
      case "$stem" in
        *_[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) stem="${stem%_*}" ;;
      esac
      final="$dir/${stem}_${h8}.bytecode"
      [ "$outf" = "$final" ] || mv -f "$outf" "$final"
      ok "BYTECODE OK tai vong $i: $final ($(stat -f%z "$final") B)"
      ok "sha256 $(shasum -a 256 "$final" | cut -c1-64)"
      return 0
    fi
    if [ "$augment" = 0 ]; then
      # Interface là HỢP ĐỒNG host (đóng băng) — không tự vá. Lỗi = module
      # dùng thứ host không lộ: sửa module, hoặc thêm vào
      # configs/abi/dynamic_interface.extra.yaml + BUILD LẠI HOST.
      echo "  ${RED}[FAIL]${RST} compile module that bai — xem $log"
      grep -oE "Error: .*|Unhandled exception.*|Crash when compiling.*" "$log" \
        | perl -pe 'my $n=0; s/\x27[^\x27]*\x27/++$n>1 ? "\x27…\x27" : $&/ge' | sort | uniq -c | sort -rn | head -15
      grep -m1 -A2 "Crash when compiling" "$log" || true
      return 1
    fi
    out=""
    stage=""
    out="$(python3 "$DIF/augment_from_validate.py" "$IFACE" "$log" "$APP/.dart_tool/package_config.json" 2>>"$log" || true)"
    case "$out" in NO_ERROR|NO_CHANGE|"" )
      out="$(python3 "$DIF/fix_disambiguation.py" "$IFACE" "$log" 2>>"$log" || true)"
      stage="fix_disambiguation" ;;
      * ) stage="augment_from_validate" ;;
    esac
    case "$out" in NO_ERROR|NO_CHANGE|"" )
      out="$(python3 "$DIF/repair_containers.py" "$IFACE" "$log" 2>>"$log" || true)"
      stage="repair_containers" ;;
    esac
    case "$out" in NO_ERROR|NO_CHANGE|"" )
      echo "  vong $i: khong con gi sua duoc (rc=$rc) — xem $log"
      tail -n 15 "$log"
      return 1 ;;
    esac
    echo "  vong $i: rc=$rc -> $stage ($out)"
  done
  echo "  ${RED}[FAIL]${RST} het $rounds vong chua xong — xem $log" >&2
  return 1
}

# compile = gen (neu can) + loop — 1 LENH TU SOURCE DEN .bytecode
cmd_compile() {
  local regen=0 pass=() mod_seen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --regen) regen=1; shift ;;
      -o|--anchor) pass+=("$1" "$2"); shift 2 ;;
      *) [ "$mod_seen" = 0 ] && mod_seen=1; shift ;;  # module path — loop co mac dinh
    esac
  done
  if [ "$regen" = 1 ]; then
    cmd_gen --regen
  elif [ ! -f "$IFACE" ]; then
    cmd_gen
  else
    info "iface da co — bo qua gen (dung --regen de sinh lai tu anchor)"
  fi
  # 1 lần, KHÔNG augment (P4): interface sinh trọn từ anchor + manifest +
  # configs/abi/dynamic_interface.extra.yaml — vá tự động sẽ làm iface lệch host.
  cmd_loop --rounds 1 --no-augment "${pass[@]+${pass[@]}}"
}

# bootstrap = pha vo vong lap anchor <-> iface tren may MOI (dist/ trong):
# build anchor dill bang gen_kernel_aot KHONG can --dynamic-interface, roi
# moi sinh baseline yaml tu anchor do.
cmd_bootstrap() {
  local anchor="$ROOT/dist/app_content.anchor.dill"
  while [ $# -gt 0 ]; do
    case "$1" in
      --anchor) anchor="$2"; shift 2 ;;
      *) die "co la: $1 (bootstrap [--anchor <dill>])" ;;
    esac
  done
  mkdir -p "$ROOT/dist"
  local H="$OUTDIR/host_release_arm64" AOT="$H/dart-sdk/bin/dartaotruntime"
  [ -x "$AOT" ] || die "thieu engine host ($AOT) — chay: bash tools/cmd/dynmod.sh engine host"
  local P; P="$(platform_dill)"; [ -n "$P" ] || die "khong thay platform_strong.dill trong $OUTDIR"
  # LUÔN build lại (~10s): anchor phải == kernel host HIỆN TẠI (pin
  # host_packages.g.dart, pubspec…) — anchor cũ lệch host = module nạp lỗi
  # "already loaded" / thiếu member lúc chạy (P4).
  [ -f "$APP/.dart_tool/package_config.json" ] \
    || die "app chua pub get — chay: DYNMOD_APP=$APP bash tools/cmd/dynmod.sh pubget"
  # iface lộ package host theo import của ../app_package/modules/home_content.dart.
  # convert_to_package / giải nén zip không có modules/ → thiếu thì iface rút
  # gọn, host build ra không chạy được patch nào (th1 android vc7) → luôn áp lại.
  bash "$ROOT/tools/cmd/modprep.sh" apply --no-check \
    || die "ap modules/ vao ../app_package that bai — xem [FAIL] o tren"
  local pkg; pkg="$(awk '/^name:/{print $2; exit}' "$APP/pubspec.yaml")"
  info "build anchor (gen_kernel_aot, KHONG can iface) -> $anchor"
  ( cd "$APP" && "$AOT" "$H/gen/gen_kernel_aot.dart.snapshot" \
      --platform "$P" --target flutter --no-aot --no-link-platform \
      --packages "$APP/.dart_tool/package_config.json" \
      -Ddart.vm.product=true --output "$anchor.tmp" "package:$pkg/main.dart" ) \
    || die "build anchor that bai (xem app/main.dart co import du closure?)"
  mv -f "$anchor.tmp" "$anchor"
  ok "anchor: $(basename "$anchor") ($(stat -f%z "$anchor") B)"
  export DYNIFACE_ANCHOR="$anchor"
  cmd_gen --regen
  # Dấu đầu vào: tools/check.sh bước 0 biết iface còn khớp repo không (máy khác
  # pull đổi ABI host mà chưa bootstrap → tự sinh lại thay vì báo lỗi giả).
  python3 -B "$ROOT/tools/cmd/localstate.py" iface-write
}

case "${1:-}" in
  gen)     shift; cmd_gen "$@" ;;
  bootstrap) shift; cmd_bootstrap "$@" ;;
  loop)    shift; cmd_loop "$@" ;;
  compile) shift; cmd_compile "$@" ;;
  status)  cmd_status ;;
  packages) shift
    # classify (manifest) rồi đồng bộ app/lib/shell/host_packages.g.dart:
    # --write → sinh lại; check → báo lệch.
    python3 "$DIF/classify_packages.py" "$@"
    case " $* " in
      *" check "*) python3 "$DIF/gen_host_pin.py" --check ;;
      *" --write "*) python3 "$DIF/gen_host_pin.py" ;;
    esac ;;
  *) sed -n '2,31p' "$0"; exit 1 ;;
esac