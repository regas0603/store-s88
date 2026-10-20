#!/usr/bin/env bash
# tools/cmd/doctor.sh — Kiểm tra máy build đã sẵn sàng.
# Chạy: bash tools/cmd/doctor.sh
#       bash tools/cmd/doctor.sh --full   # + chạy test Dart/Flutter
# Exit 0 = mọi thứ OK. Exit 1 = thiếu thứ gì đó (in ra từng mục PASS/FAIL).

set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Đường dẫn engine theo đúng mặc định của tools/cmd/dynmod.sh — đặt DYNMOD_WORK /
# DYNMOD_ENGINE_SRC trước khi gọi để doctor dò bản khác.
WORK="${DYNMOD_WORK:-$(dirname "$ROOT")/dart-sdk-build}"  # derive từ vị trí project (anh em của repo)
# Engine DÙNG (chỉ cần out/ + sdk/lib + lib/ui): ưu tiên ../engine — bản chép gọn
# (~4,3GB thay vì ~50GB checkout, tạo/cập nhật bằng: bash tools/cmd/dynmod.sh backup).
_ENG_DEF="$(dirname "$ROOT")/engine"; [ -d "$_ENG_DEF/out" ] || _ENG_DEF="$WORK/flutter-framework/engine/src"
ENGINE_SRC="${DYNMOD_ENGINE_SRC:-$_ENG_DEF}"
# Flutter DÙNG (CLI flutter/dart + framework): ../engine/flutter-framework (gom 1
# chỗ, tạo bằng: bash tools/cmd/dynmod.sh backup); chưa có thì checkout build.
ENGINE_HOME="${DYNMOD_ENGINE_HOME:-$(dirname "$ROOT")/engine}"
_FF_DEF="$ENGINE_HOME/flutter-framework"; [ -x "$_FF_DEF/bin/flutter" ] || _FF_DEF="$WORK/flutter-framework"
OUT="$ENGINE_SRC/out"
FAILS=0

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
pass() { echo "  ${GRN}[PASS]${RST} $1"; }
fail() { echo "  ${RED}[FAIL]${RST} $1  ← $2"; FAILS=$((FAILS+1)); }
warn() { echo "  ${YEL}[WARN]${RST} $1"; }

echo "== 1. SDK tối thiểu =="
for cmd in git node python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd: $(command -v "$cmd")"
  else
    fail "$cmd" "cài SDK rồi chạy lại bash tools/cmd/doctor.sh"
  fi
done
# Flutter: CHỈ bản của engine (CLAUDE.md §1) — flutter trong PATH không dùng tới.
if [ -x "${DYNMOD_FF:-$_FF_DEF}/bin/flutter" ]; then pass "flutter (engine): ${DYNMOD_FF:-$_FF_DEF}/bin/flutter"
else fail "flutter (engine)" "thiếu ${DYNMOD_FF:-$_FF_DEF}/bin/flutter — chép ../engine hoặc chạy: bash tools/setup.sh"; fi

echo "== 2. Engine dynamic-modules (flutter/flutter upstream) =="
# Engine host: bắt buộc cho CẢ 2 — `--local-engine-host` + dartaotruntime
# (gen_kernel anchor.dill + dart2bytecode compile module .bytecode).
check_engine() { # $1=label  $2=out dir  $3=binary kỳ vọng  $4=hint
  if [ ! -d "$2" ]; then
    fail "$1" "chưa có out dir $2 — $4"
  elif [ ! -e "$3" ]; then
    fail "$1" "out dir có nhưng thiếu binary — build lại: $4"
  else
    pass "$1: ${3#$WORK/}"
  fi
}
check_engine "engine host" \
  "$OUT/host_release_arm64" \
  "$OUT/host_release_arm64/FlutterMacOS.framework/Versions/A/FlutterMacOS" \
  "bash tools/cmd/dynmod.sh engine host"
check_engine "engine android" \
  "$OUT/android_release_arm64" \
  "$OUT/android_release_arm64/libflutter.so" \
  "bash tools/cmd/dynmod.sh engine android"
check_engine "engine ios" \
  "$OUT/ios_release" \
  "$OUT/ios_release/Flutter.framework/Flutter" \
  "bash tools/cmd/dynmod.sh engine ios"
# Version: engine (stamp lúc build) + checkout flutter phải == configs/flutter.json
FV="$ROOT/tools/cmd/flutter_version.sh"
FVER="$(bash "$FV" 2>/dev/null || echo '?')"
WANT="$(bash "$FV" --commit 2>/dev/null || true)"
FF_DIR="${DYNMOD_FF:-$_FF_DEF}"
if [ -z "$WANT" ]; then
  fail "flutter $FVER" "checkout chưa có ref này — chạy: bash tools/setup.sh (tự sync)"
else
  if [ "$(git -C "$FF_DIR" rev-parse HEAD 2>/dev/null)" = "$WANT" ]; then pass "checkout flutter @ $FVER (${WANT:0:10})"
  else fail "checkout flutter" "không ở $FVER — chạy: bash tools/setup.sh"; fi
  for od in host_release_arm64 android_release_arm64 ios_release; do
    got="$(bash "$FV" --stamp "$OUT/$od" 2>/dev/null || true)"
    if [ "$got" = "$WANT" ]; then pass "engine $od build từ $FVER"
    else fail "engine $od" "build từ ${got:-(không rõ — chưa có stamp)} ≠ $FVER — chạy: bash tools/setup.sh"; fi
  done
fi
# Compile module cần 2 tool này nằm trong engine host.
AOT="$OUT/host_release_arm64/dart-sdk/bin/dartaotruntime"
if [ -x "$AOT" ]; then
  pass "dartaotruntime (compile module: anchor.dill + dart2bytecode)"
else
  fail "dartaotruntime" "$AOT — chạy: bash tools/cmd/dynmod.sh engine host"
fi

echo "== 2b. Artifact repo (app build + publish được?) =="
# main_app_package: app path-dep ../../main_app_package — thiếu là `flutter pub
# get` fail. Xuất bằng: bash tools/cmd/build_main_app.sh
if [ -f "$ROOT/../main_app_package/pubspec.yaml" ]; then
  pass "main_app_package (ngoài repo)"
else
  fail "main_app_package" "thiếu $ROOT/../main_app_package — chạy: bash tools/cmd/build_main_app.sh"
fi
# app_package + game_engine: nguồn module B + native plugin (chỉ Android lấy native).
if [ -f "$ROOT/../app_package/pubspec.yaml" ]; then
  pass "app_package (nguồn module)"
else
  fail "app_package" "thiếu $ROOT/../app_package — app/pubspec.yaml path-dep vào đây"
fi
if [ -d "$ROOT/../app_package/packages/game_engine" ]; then
  pass "app_package/packages/game_engine (native plugin)"
else
  fail "game_engine" "thiếu ../app_package/packages/game_engine — app path-dep vào đây"
fi
# dynamic_interface.yaml — gitignored (dist/), cần cho build ddm + compile module.
if [ -f "$ROOT/dist/dynamic_interface.yaml" ]; then
  pass "dist/dynamic_interface.yaml ($(grep -c 'library:' "$ROOT/dist/dynamic_interface.yaml") entry)"
else
  warn "chưa có dist/dynamic_interface.yaml — chạy: bash tools/cmd/dyniface.sh bootstrap"
fi
# app đã pub get chưa (resolve được path dep).
if [ -f "$ROOT/app/.dart_tool/package_config.json" ]; then
  pass "app đã pub get"
else
  warn "app chưa pub get — chạy: bash tools/setup.sh"
fi
if ls "$ROOT"/configs/apps/*.json >/dev/null 2>&1; then
  pass "configs/apps/*.json ($(ls "$ROOT"/configs/apps/*.json | wc -l | tr -d ' ') app)"
else
  warn "chưa có configs/apps/*.json — base URL update cho app"
fi

echo "== 3. Node (CLI dynpush gen manifest qua node) =="
if command -v node >/dev/null 2>&1; then
  pass "node: $(node --version)"
else
  fail "node" "cài Node.js (dynpush dùng node để gen/đọc JSON)"
fi
if [ -d "$ROOT/dist" ]; then
  pass "dist/ (staging bytecode.manifest — tạo lúc chạy dynpush patch)"
fi

echo "== 4. Dart/Flutter + test (tuỳ chọn --full) =="
if [ "${1:-}" = "--full" ]; then
  if [ -x "$FF_DIR/bin/flutter" ]; then
    for pkg in loading_kit/loading_kit loading_kit/dyn_loader; do
      [ -d "$ROOT/$pkg" ] || continue
      (cd "$ROOT/$pkg" && "$FF_DIR/bin/flutter" test 2>&1 | tail -1 | sed "s|^|  ${GRN}[PASS]${RST} $pkg: |") || true
    done
  else
    fail "flutter của engine" "không thấy $FF_DIR/bin/flutter — chạy: bash tools/setup.sh"
  fi
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "KẾT QUẢ: OK — máy sẵn sàng."
else
  echo "KẾT QUẢ: $FAILS mục FAIL — xử lý theo chú thích từng dòng."
fi
exit "$FAILS"