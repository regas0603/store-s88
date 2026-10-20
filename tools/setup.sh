#!/usr/bin/env bash
# tools/setup.sh — SETUP 1 LỆNH: đưa MÁY + REPO tới trạng thái chạy được toàn
# bộ chuỗi hotupdate (Dart Dynamic Modules) trên Android + iOS.
#
#   bash tools/setup.sh                 # làm mọi bước còn thiếu (idempotent)
#   bash tools/setup.sh --dry-run       # chỉ IN kế hoạch, không đổi gì
#   bash tools/setup.sh --skip-engine   # bỏ bước build engine (đã có sẵn)
#   bash tools/setup.sh --skip-module   # bỏ interface + anchor
#   bash tools/setup.sh --full          # nghiệm thu kèm test dart/flutter
#   bash tools/setup.sh --no-install    # KHÔNG tự cài SDK thiếu (chỉ kiểm tra)
#
# Bước nào ĐÃ XONG thì SKIP — chạy lại vô hại (kể cả sau khi reset máy).
#
# Làm gì (thứ tự có phụ thuộc):
#   0. Tự cài SDK    : thiếu cái nào (trừ Xcode) thì tự cài qua brew
#                      (brew itself, git, node>=20, python3, CocoaPods,
#                      Android cmdline-tools + licenses, Metal Toolchain);
#                      Xcode phải cài tay trên App Store (không script được).
#   1. Preflight   : git, node>=20, python3, Xcode, Metal Toolchain
#                    (KHÔNG cần flutter trong PATH — dùng ../engine/flutter-framework)
#   2. Engine ddm  : host + android + ios (build cái nào thiếu)
#   2b. app_package: ../app_package (module) phải có — SINH RA bởi
#                    ../s88-flutter/convert_to_package.sh, setup không tự tạo;
#                    thiếu thì báo cách tạo + bỏ qua bước 3-5
#   3. main_app_package : xuất ra NGOÀI repo (app path-dep vào đây)
#   4. app deps    : patch pubspec path + flutter pub get
#   5. Interface   : áp templates/module vào ../app_package +
#                    GEN LẠI dist/dynamic_interface.yaml từ anchor (~2s).
#                    KHÔNG compile bytecode — chạy tools/check.sh trước, rồi
#                    tools/dynpub.sh patch (compile + bytecode.manifest).
#                    KHÔNG còn skip khi file đã có — tránh yaml cũ/lech anchor.
#                    (bỏ qua với --skip-module; hoặc khi đã có loop đang chạy)
#   6. Nghiệm thu  : tools/cmd/doctor.sh (exit 0 = sẵn sàng)
#
# Env (khớp tools/cmd/dynmod.sh): DYNMOD_WORK, DYNMOD_REV, DYNMOD_ENGINE_SRC.
# Doc nền: docs/RUN_GUIDE.md, docs/dynmod_replace_shorebird_plan.md.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DYNMOD="$ROOT/tools/cmd/dynmod.sh"
DYNIFACE="$ROOT/tools/cmd/dyniface.sh"
WORK="${DYNMOD_WORK:-$(dirname "$ROOT")/dart-sdk-build}"  # derive từ vị trí project (anh em của repo)
BUILD_FF="$WORK/flutter-framework"   # checkout BUILD engine (~57GB) — chỉ cần khi build lại engine
# Flutter DÙNG: ../engine/flutter-framework (bản chép gọn) — có rồi thì KHÔNG cần
# clone/sync ../dart-sdk-build (trừ khi engine thiếu / khác version phải build lại).
_FF_DEF="$(dirname "$ROOT")/engine/flutter-framework"; [ -x "$_FF_DEF/bin/flutter" ] || _FF_DEF="$BUILD_FF"
FF="${DYNMOD_FF:-$_FF_DEF}"
# Engine DÙNG (chỉ cần out/ + sdk/lib + lib/ui): ưu tiên ../engine — bản chép gọn
# (~4,3GB thay vì ~50GB checkout, tạo/cập nhật bằng: bash tools/cmd/dynmod.sh backup).
_ENG_DEF="$(dirname "$ROOT")/engine"; [ -d "$_ENG_DEF/out" ] || _ENG_DEF="$WORK/flutter-framework/engine/src"
ENGINE_SRC="${DYNMOD_ENGINE_SRC:-$_ENG_DEF}"
OUT="$ENGINE_SRC/out"
APP="$ROOT/app"
MAIN_APP_OUT="${MAIN_APP_PACKAGE_DIR:-$ROOT/../main_app_package}"
IFACE="$ROOT/dist/dynamic_interface.yaml"
ANCHOR="$ROOT/dist/app_content.anchor.dill"
FV="$ROOT/tools/cmd/flutter_version.sh"
FLUTTER_VERSION="$(bash "$FV")"          # configs/flutter.json (env DYNMOD_REV thắng)
WANT=""                                  # commit của FLUTTER_VERSION — tính ở bước 2

FULL=0 SKIP_ENGINE=0 SKIP_MODULE=0 DRY_RUN=0 NO_INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --full)        FULL=1 ;;
    --skip-engine) SKIP_ENGINE=1 ;;
    --skip-module) SKIP_MODULE=1 ;;
    --dry-run|-n)  DRY_RUN=1 ;;
    --no-install)  NO_INSTALL=1 ;;
    -h|--help|help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'; exit 0 ;;
    *) echo "Cờ lạ: $1 (xem --help)" >&2; exit 2 ;;
  esac
  shift
done

DONE=0 SKIP=0 WARN=0 FAIL=0
step() { echo; echo "══ $1 ══"; }
RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
pass() { echo "  ${GRN}[PASS]${RST} $1"; DONE=$((DONE+1)); }
skip() { echo "  [SKIP] $1"; SKIP=$((SKIP+1)); }
warn() { echo "  ${YEL}[WARN]${RST} $1"; WARN=$((WARN+1)); }
bad()  { echo "  ${RED}[FAIL]${RST} $1"; FAIL=$((FAIL+1)); }
run()  { if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

# Engine <target> đã có interpreter dyn_modules VÀ build đúng version config chưa?
engine_od() {
  case "$1" in host) echo host_release_arm64 ;; android) echo android_release_arm64 ;; ios) echo ios_release ;; esac
}
engine_bin() {
  case "$1" in
    host)    echo "$OUT/host_release_arm64/FlutterMacOS.framework/Versions/A/FlutterMacOS" ;;
    android) echo "$OUT/android_release_arm64/libflutter.so" ;;
    ios)     echo "$OUT/ios_release/Flutter.framework/Flutter" ;;
  esac
}
engine_ok() {
  local b; b="$(engine_bin "$1")"
  [ -f "$b" ] && LC_ALL=C grep -a -q "Unexpected Dart bytecode magic" "$b" || return 1
  # stamp (dynmod.sh ghi lúc build) phải == commit của configs/flutter.json
  [ -n "$WANT" ] && [ "$(bash "$FV" --stamp "$OUT/$(engine_od "$1")" 2>/dev/null)" = "$WANT" ]
}

# ── 0. Tự cài SDK thiếu (trừ Xcode) ─────────────────────────────────────────
step "0. Tự cài SDK thiếu (brew — trừ Xcode)"
if [ "$DRY_RUN" = 1 ]; then
  DRY_RUN=1 NO_INSTALL="$NO_INSTALL" bash "$ROOT/tools/cmd/ensure_deps.sh" --dry-run || warn "bước 0 còn thiếu (xem dry-run ở trên)"
else
  DRY_RUN=0 NO_INSTALL="$NO_INSTALL" bash "$ROOT/tools/cmd/ensure_deps.sh" || warn "bước 0 còn thiếu (Xcode cài tay, còn lại chạy lại setup để cài tiếp)"
fi


# ── 1. Preflight ────────────────────────────────────────────────────────────
step "1. Preflight (SDK + Xcode + Metal)"
MISSING=0
for cmd in git node python3; do
  if command -v "$cmd" >/dev/null 2>&1; then pass "$cmd: $(command -v "$cmd")"
  else bad "thiếu $cmd — cài SDK rồi chạy lại"; MISSING=1; fi
done
if command -v node >/dev/null 2>&1; then
  NJ="$(node --version | sed 's/^v//' | cut -d. -f1)"
  if [ "${NJ:-0}" -ge 20 ]; then pass "node $(node --version) (>= 20)"; else bad "node $(node --version) quá cũ — Fastify 5 cần >= 20"; fi
fi
if [ "$(uname -s)" = Darwin ]; then
  if xcode-select -p >/dev/null 2>&1; then pass "Xcode: $(xcodebuild -version 2>/dev/null | head -1)"
  else bad "Xcode — cài Xcode đầy đủ (iOS chỉ ký được trên macOS)"; fi
  if xcrun metal --version >/dev/null 2>&1; then pass "Metal Toolchain"
  else warn "Metal Toolchain thiếu — chạy: xcodebuild -downloadComponent MetalToolchain (engine host cần)"; fi
else
  bad "OS $(uname -s) — tool viết cho macOS (phải build cả iOS)"
fi
[ "$MISSING" = 0 ] || { echo; echo "Dừng: cài SDK còn thiếu rồi chạy lại."; exit 1; }

# ── 2. Engine dynamic-modules ───────────────────────────────────────────────
step "2. Engine dynamic-modules (host + android + ios)"
if [ "$SKIP_ENGINE" = 1 ]; then
  skip "--skip-engine: bỏ kiểm/build engine"
else
  echo "  Flutter $FLUTTER_VERSION (configs/flutter.json)"
  WANT="$(bash "$FV" --commit 2>/dev/null || true)"
  HEAD_REV="$(git -C "$FF" rev-parse HEAD 2>/dev/null || true)"
  NEED_BUILD=0 BUILD_FAIL=0
  for t in host android ios; do engine_ok "$t" || NEED_BUILD=1; done
  # Flutter DÙNG ($FF — ../engine/flutter-framework nếu có) phải đúng version;
  # engine thiếu/khác version mà chưa có source → sync. Đủ 3 engine đúng version
  # + Flutter đúng rev → KHÔNG đụng tới ../dart-sdk-build (không clone / sync).
  echo "  Flutter dùng: $FF"
  if [ -z "$WANT" ] || [ "$HEAD_REV" != "$WANT" ] \
     || { [ "$NEED_BUILD" = 1 ] && [ ! -x "$BUILD_FF/engine/src/flutter/tools/gn" ]; }; then
    warn "checkout flutter ${HEAD_REV:0:10} ≠ $FLUTTER_VERSION (hoặc chưa sync) — checkout + gclient sync (lần đầu tải ~chục GB)"
    if run bash "$DYNMOD" sync; then
      WANT="$(bash "$FV" --commit 2>/dev/null || true)"
      NEED_BUILD=0
      for t in host android ios; do engine_ok "$t" || NEED_BUILD=1; done
    else
      bad "sync flutter $FLUTTER_VERSION thất bại"
    fi
  fi
  for t in host android ios; do
    if engine_ok "$t"; then skip "engine $t đã có interpreter @ $FLUTTER_VERSION"
    else
      warn "engine $t chưa build / khác version $FLUTTER_VERSION — build ngay (log: $WORK/logs)"
      run bash "$DYNMOD" engine "$t" || { bad "engine $t build thất bại — xem $WORK/logs/ninja-*-*.log"; BUILD_FAIL=1; }
    fi
  done
  # Engine luôn build ra checkout → chép gọn sang ../engine (hoặc DYNMOD_ENGINE_SRC)
  # khi vừa build hoặc chưa có bản chép; các bước sau dùng luôn bản chép đó.
  ENG_COPY="${DYNMOD_ENGINE_SRC:-$(dirname "$ROOT")/engine}"
  # Build lỗi → KHÔNG chép (out/ checkout còn bản cũ/dở — chép sang = engine sai version).
  if [ "$BUILD_FAIL" = 1 ]; then
    warn "có engine build lỗi — không chép sang $ENG_COPY"
  elif [ "$ENG_COPY" != "$BUILD_FF/engine/src" ] && { [ "$NEED_BUILD" = 1 ] || [ ! -d "$ENG_COPY/out" ]; }; then
    if run bash "$DYNMOD" backup "$ENG_COPY"; then
      pass "engine chép gọn → $ENG_COPY"
      ENGINE_SRC="$ENG_COPY"; OUT="$ENGINE_SRC/out"
    else
      bad "chép engine sang $ENG_COPY thất bại"
    fi
  fi
fi

# ── 2b. app_package (module — sinh ra từ s88-flutter) ───────────────────────
# app/pubspec.yaml path-dep vào ../app_package (+ packages/game_engine): thiếu
# thì pub get / xuất main_app / interface đều fail dây chuyền → dừng sớm, chỉ rõ.
step "2b. app_package (module — ../app_package)"
APP_PKG="$(dirname "$ROOT")/app_package"
NO_APP_PKG=0
if [ -f "$APP_PKG/pubspec.yaml" ] && [ -f "$APP_PKG/packages/game_engine/pubspec.yaml" ]; then
  pass "có $APP_PKG"
else
  NO_APP_PKG=1
  bad "chưa có $APP_PKG (hoặc thiếu packages/game_engine) — bản SINH RA, setup không tự tạo:"
  S88="$(dirname "$ROOT")/s88-flutter"
  [ -f "$S88/convert_to_package.sh" ] \
    || echo "         git clone https://github.com/G1-production/s88-flutter.git $S88"
  echo "         cd $S88 && bash convert_to_package.sh   # (thêm cờ --env=… theo quy trình phát hành)"
  echo "         rồi chạy lại: bash tools/setup.sh"
fi

# ── 3. main_app_package (ngoài repo) ────────────────────────────────────────
step "3. Xuất main_app_package (app path-dep)"
if [ "$NO_APP_PKG" = 1 ]; then
  skip "cần ../app_package trước (bước 2b)"
elif [ -f "$MAIN_APP_OUT/pubspec.yaml" ]; then
  skip "đã có: $MAIN_APP_OUT"
else
  warn "chưa có $MAIN_APP_OUT — xuất từ main_app/ (copy + pub get/analyze/test)"
  run bash "$ROOT/tools/cmd/build_main_app.sh" || bad "xuất main_app_package thất bại"
fi

# ── 4. App deps ─────────────────────────────────────────────────────────────
step "4. App deps (patch pubspec path + flutter pub get)"
# pub get lại khi Dart đổi (đổi configs/flutter.json): so generatorVersion với Dart của checkout.
PKG_DART="$(grep -o '"generatorVersion": *"[^"]*"' "$APP/.dart_tool/package_config.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || true)"
# bin/cache chỉ làm mới khi chạy flutter → gọi 1 lần (tải Dart đúng version checkout).
[ "$DRY_RUN" = 1 ] || "$FF/bin/flutter" --version >/dev/null 2>&1 || true
FF_DART="$(cat "$FF/bin/cache/dart-sdk/version" 2>/dev/null || true)"
if [ "$NO_APP_PKG" = 1 ]; then
  skip "cần ../app_package trước (bước 2b)"
elif [ -f "$APP/.dart_tool/package_config.json" ] && [ "$DRY_RUN" = 0 ] \
   && { [ -z "$FF_DART" ] || [ "$PKG_DART" = "$FF_DART" ]; }; then
  skip "app đã pub get (Dart ${PKG_DART:-?})"
else
  run env DYNMOD_APP="$APP" DYNMOD_WORK="$WORK" DYNMOD_ENGINE_SRC="$ENGINE_SRC" bash "$DYNMOD" pubget \
    || bad "flutter pub get thất bại (thiếu main_app_package? engine chưa sync?)"
fi
# CLAUDE.md §2: sau pub get, lock không được trôi version so với bản commit
# (lock = ABI host). Trôi thường do ../app_package khác bản đã dùng lúc chốt lock.
if [ "$DRY_RUN" = 0 ] && [ "$NO_APP_PKG" = 0 ] && git -C "$ROOT" cat-file -e HEAD:app/pubspec.lock 2>/dev/null; then
  if python3 -B "$ROOT/tools/cmd/lockcheck.py" >/dev/null 2>&1; then pass "pubspec.lock khớp lock tham chiếu"
  else
    python3 -B "$ROOT/tools/cmd/lockcheck.py" 2>&1 | grep FAIL | sed 's/^/  /'
    bad "pubspec.lock trôi version so với bản commit — ../app_package khác bản đã chốt lock? Cố ý đổi → commit app/pubspec.lock; không thì: git checkout -- app/pubspec.lock và dùng đúng app_package"
  fi
fi

# ── 5. Interface + anchor ───────────────────────────────────────────────────
# GEN LẠI MỖI LẦN (~2s, GIỮ các entry private đã augment → làm lại vô hại).
# KHÔNG compile bytecode ở đây: phải qua tools/check.sh trước, rồi mới
# bash tools/dynpub.sh patch (compile + bytecode.manifest).
step "5. Interface + anchor (dist/dynamic_interface.yaml)"
if [ "$SKIP_MODULE" = 1 ]; then
  skip "--skip-module: bỏ interface/anchor"
elif [ "$NO_APP_PKG" = 1 ]; then
  skip "cần ../app_package trước (bước 2b)"
elif ! engine_ok host; then
  warn "chưa có engine host — bỏ qua (chạy lại setup khi engine host xong)"
elif [ ! -f "$APP/.dart_tool/package_config.json" ] && [ "$DRY_RUN" = 0 ]; then
  warn "app chưa pub get — bỏ qua interface"
elif [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] bash tools/cmd/modprep.sh apply --no-check                               # áp templates/module vào ../app_package"
  echo "  [dry-run] env DYNIFACE_ANCHOR=$ANCHOR bash $DYNIFACE bootstrap --anchor $ANCHOR   # gen lại yaml (~2s)"
elif pgrep -f 'dyniface\.sh (compile|loop)' >/dev/null 2>&1; then
  # Data race: gen/compile cùng ghi 1 file yaml → corrupt (đã từng crash
  # "library ... has not been indexed"). Không đụng vào khi loop đang chạy.
  warn "đang có dyniface compile/loop đang chạy — KHÔNG gen lại (tránh ghi đè yaml); chờ nó xong rồi chạy lại setup"
elif ! bash "$ROOT/tools/cmd/modprep.sh" apply --no-check; then
  # app_package là bản SINH RA (convert_to_package.sh xoá modules/) — áp lại
  # entry từ templates/module/ trước khi gen iface (gen đọc modules/home_content.dart).
  bad "modprep apply thất bại (../app_package đã convert chưa?)"
else
  echo "  [gen] gen lại interface từ anchor $(basename "$ANCHOR") (~2s, giữ entry đã augment)"
  run env DYNMOD_APP="$APP" DYNMOD_WORK="$WORK" DYNMOD_ENGINE_SRC="$ENGINE_SRC" DYNIFACE_ANCHOR="$ANCHOR" \
      bash "$DYNIFACE" bootstrap --anchor "$ANCHOR" || bad "sinh interface thất bại (anchor dựng được?)"
fi

# ── 6. Nghiệm thu ───────────────────────────────────────────────────────────
step "6. Nghiệm thu (tools/cmd/doctor.sh)"
if [ "$DRY_RUN" = 1 ]; then
  echo "  [dry-run] bash tools/cmd/doctor.sh $([ "$FULL" = 1 ] && echo --full)"
else
  set +e
  bash "$ROOT/tools/cmd/doctor.sh" $([ "$FULL" = 1 ] && echo --full)
  RC=$?
  set -e
  if [ "$RC" = 0 ]; then pass "doctor OK — máy sẵn sàng"
  else warn "doctor còn $RC mục FAIL — xử lý theo chú thích ở trên"; fi
fi

# ── Tổng kết ────────────────────────────────────────────────────────────────
echo
echo "══ KẾT QUẢ SETUP ══"
echo "  PASS=$DONE  SKIP=$SKIP  WARN=$WARN  FAIL=$FAIL"
if [ "$FAIL" = 0 ]; then
  cat <<'TIP'
SETUP XONG — máy build + interface sẵn sàng. Bước tiếp (wizard: bash tools/dynpub.sh):
  1. kiểm       : bash tools/check.sh           # app_package / main_app / host
  2. build host : menu [5] — ghi registry/hosts/ + tự commit (không cần VPN)
  3. ra patch   : menu [1]
  4. lên store  : menu [6] submitted / live → menu [2] deploy (máy có VPN)
Xem tools/README.md + docs/release_registry_design.md.
TIP
else
  echo "SETUP CHƯA XONG — xử lý $FAIL mục ${RED}[FAIL]${RST} ở trên rồi chạy lại: bash tools/setup.sh"
fi
exit "$FAIL"
