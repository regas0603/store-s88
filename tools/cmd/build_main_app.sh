#!/usr/bin/env bash
# tools/cmd/build_main_app.sh — Xuất "main app" (UI màn "sạch" + nhận diện app)
# từ nguồn main_app/ (trong repo) ra PACKAGE NGOÀI để app/build phụ thuộc.
#
#   bash tools/cmd/build_main_app.sh               # xuất + verify (pub get/analyze/test)
#   bash tools/cmd/build_main_app.sh --dry-run     # xem trước — không ghi file
#   bash tools/cmd/build_main_app.sh --out-dir D   # xuất tới thư mục khác
#   bash tools/cmd/build_main_app.sh --src apps/<bundleId>/main_app  # main_app của 1 app
#   bash tools/cmd/build_main_app.sh --no-verify   # chỉ copy, bỏ pub get/analyze/test
#   bash tools/cmd/build_main_app.sh check         # chỉ verify bản xuất hiện có
#
# Kiến trúc:
#   main_app/             (trong repo — nguồn code + rule, git theo dõi)
#        │  tools/cmd/build_main_app.sh  (copy + verify contract)
#        ▼
#   ../main_app_package/  (NGOÀI repo — app/pubspec.yaml path-dep vào đây)
#
# Vì sao: bản package app build phụ thuộc phải nằm NGOÀI git này, và tên/code
# không chứa từ nhạy cảm (store chỉ thấy "main_app_package"). Nguồn của sự
# thật là main_app/ — sửa ở đó, chạy tool để xuất.
#
# Contract (tool tự check, sai là fail):
#   1. pubspec name = main_app_package
#   2. lib/main_app_package.dart có MainAppScreen + mainAppMeta
#   3. lib/ KHÔNG chứa chữ 'fake'
#   4. pubspec KHÔNG phụ thuộc repo (path về flutter-self-host)
#
# Env: FLUTTER (flutter khác), MAIN_APP_PACKAGE_DIR (thư mục xuất mặc định).

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${MAIN_APP_SRC:-$ROOT/apps/_reference/main_app}"  # --src / MAIN_APP_SRC: main_app của 1 app (apps/<bundleId>/main_app)
PKG_NAME="main_app_package"
# CHỈ Flutter của engine (CLAUDE.md §1) — KHÔNG dùng flutter trong PATH (khác
# version → ghi lại pubspec.lock → lệch ABI host). Đè được bằng env FLUTTER.
_ENG_FLUTTER="$(dirname "$ROOT")/engine/flutter-framework/bin/flutter"
[ -x "$_ENG_FLUTTER" ] || _ENG_FLUTTER="$(dirname "$ROOT")/dart-sdk-build/flutter-framework/bin/flutter"
FLUTTER="${FLUTTER:-$_ENG_FLUTTER}"

OUT_VAL=""
DRY_RUN=0
VERIFY=1
CHECK_ONLY=0

die() { echo "✗ $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --out-dir) OUT_VAL="$2"; shift ;;
    --src) SRC="$(cd "$2" && pwd)"; shift ;;
    --out-dir=*) OUT_VAL="${1#*=}" ;;
    --no-verify) VERIFY=0 ;;
    check) CHECK_ONLY=1 ;;
    -h|--help|help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Lệnh lạ: $1 (xem --help)" ;;
  esac
  shift
done

OUT="${OUT_VAL:-${MAIN_APP_PACKAGE_DIR:-$ROOT/../main_app_package}}"

[ -f "$SRC/pubspec.yaml" ] || die "Không thấy $SRC/pubspec.yaml — nguồn main_app thiếu."
[ -f "$SRC/lib/$PKG_NAME.dart" ] || die "Không thấy $SRC/lib/$PKG_NAME.dart — entry package thiếu."

# ─── verify_contract <dir> — check contract (dùng cho nguồn + bản xuất) ─────
verify_contract() {
  local d="$1" bad
  [ -f "$d/pubspec.yaml" ] || die "$d: thiếu pubspec.yaml"
  grep -qE "^name:[[:space:]]*$PKG_NAME([[:space:]]|\$)" "$d/pubspec.yaml" \
    || die "$d/pubspec.yaml: 'name:' phải là $PKG_NAME"
  grep -q "MainAppScreen" "$d/lib/$PKG_NAME.dart" \
    || die "$d/lib/$PKG_NAME.dart: thiếu contract MainAppScreen"
  grep -q "mainAppMeta" "$d/lib/$PKG_NAME.dart" \
    || die "$d/lib/$PKG_NAME.dart: thiếu contract mainAppMeta"
  bad="$(grep -rin 'fake' "$d/lib" 2>/dev/null || true)"
  [ -z "$bad" ] || { echo "$bad" >&2; die "$d/lib chứa chữ 'fake' — cấm (cloaking)"; }
  if grep -q 'flutter-self-host' "$d/pubspec.yaml"; then
    die "$d/pubspec.yaml: không được phụ thuộc repo (path flutter-self-host)"
  fi
  echo "✓ contract OK: name=$PKG_NAME · MainAppScreen + mainAppMeta · lib/ sạch · không phụ thuộc repo"
}

# ─── abi_check <dir> — main_app này dùng chung bytecode module được không ────
# (không kéo package module vào host, không đổi version package host). Chưa
# có ABI đóng băng (configs/abi/module_abi.json) thì bỏ qua — dynpub release sẽ chụp.
abi_check() {
  if [ -f "$ROOT/configs/abi/module_abi.json" ]; then
    ABICHECK_ALLOW_ABI_DIFF=1 bash "$ROOT/tools/cmd/abicheck.sh" main-app "$1" \
      || die "main_app này KHÔNG dùng chung được bytecode module — xem [FAIL] ở trên"
  else
    echo "⚠ chưa có configs/abi/module_abi.json — bỏ qua kiểm dùng chung bytecode"
  fi
}

# ─── check: chỉ verify bản xuất hiện có ─────────────────────────────────────
if [ "$CHECK_ONLY" = 1 ]; then
  [ -d "$OUT" ] || die "Không thấy bản xuất: $OUT (bỏ 'check' để xuất mới)"
  echo "══ Verify bản xuất: $OUT ══"
  verify_contract "$OUT"
  abi_check "$OUT"
  exit 0
fi

echo "══ Xuất main app: $SRC → $OUT ══"

if [ "$DRY_RUN" = 1 ]; then
  verify_contract "$SRC"
  echo "(dry-run) sẽ copy lib/ test/ assets/ pubspec.yaml analysis_options.yaml README.md .gitignore → $OUT"
  echo "(dry-run) sẽ verify lại bản xuất + flutter pub get/analyze/test"
  exit 0
fi

mkdir -p "$OUT"
rm -rf "$OUT/lib" "$OUT/test" "$OUT/assets"
cp -R "$SRC/lib" "$OUT/lib"
if [ -d "$SRC/test" ]; then
  cp -R "$SRC/test" "$OUT/test"
fi
# Asset của main_app (ảnh, âm thanh…) — khai trong pubspec, dùng qua package:.
if [ -d "$SRC/assets" ]; then
  cp -R "$SRC/assets" "$OUT/assets"
fi
for f in pubspec.yaml analysis_options.yaml README.md .gitignore; do
  if [ -f "$SRC/$f" ]; then
    cp "$SRC/$f" "$OUT/$f"
  fi
done
echo "✓ copy xong (lib/ test/ assets/ + config) — file cũ đã bị thay (không sót rác)"

verify_contract "$OUT"

if [ "$VERIFY" = 1 ]; then
  echo "── flutter pub get + analyze + test (bản xuất) ──"
  (cd "$OUT" && "$FLUTTER" pub get > /dev/null)
  (cd "$OUT" && "$FLUTTER" analyze)
  (cd "$OUT" && "$FLUTTER" test)
  echo "✓ verify bản xuất OK"
else
  echo "⚠ --no-verify: bỏ qua pub get/analyze/test"
fi
abi_check "$OUT"

# App đã trỏ đúng bản xuất chưa?
if grep -q "$PKG_NAME" "$ROOT/app/pubspec.yaml"; then
  echo "✓ app/pubspec.yaml đã có dep $PKG_NAME"
else
  echo "⚠ app/pubspec.yaml CHƯA có dep $PKG_NAME — thêm:"
  echo "    $PKG_NAME:"
  echo "      path: ../../$(basename "$OUT")"
fi
echo "✓ Xong. App build phụ thuộc bản xuất tại: $OUT"
