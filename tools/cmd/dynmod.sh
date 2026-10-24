#!/usr/bin/env bash
# tools/cmd/dynmod.sh — build chuỗi Dart DYNAMIC MODULES từ Flutter UPSTREAM (100% public).
# Tool này dùng flutter/flutter monorepo + cờ engine `dart_dynamic_modules=true`
# — không fork engine, không dart-sdk private. Tài liệu: dyn_modules_*_result.md.
#
# PHẠM VI: app chỉ build ANDROID + IOS. macOS KHÔNG phải target của app —
#   nó chỉ là máy build (bắt buộc: iOS chỉ ký được trên macOS) + engine `host`
#   (dartaotruntime / gen_kernel_aot / dart2bytecode để compile module, và làm
#   --local-engine-host lúc `flutter build`). Không có `flutter build macos`.
#
# Bootstrap đầy đủ máy build = bash tools/setup.sh (gọi sync/engine/backup/pubget
# của tool này); kiểm máy = bash tools/cmd/doctor.sh.
#
# Lệnh:
#   bash tools/cmd/dynmod.sh sync                        # clone flutter @REV + .gclient + gclient sync
#   bash tools/cmd/dynmod.sh engine <host|android|ios|all> [--patch-setjmp] [--jobs N] [--bg]
#   bash tools/cmd/dynmod.sh app <android|ios> [--sjfix] [-- <cờ flutter build thêm>]
#   bash tools/cmd/dynmod.sh module [module.dart] [--entry <file trong lib/>] [-o out.bytecode]
#   bash tools/cmd/dynmod.sh status                      # engine nào đã build, có interpreter chưa
#   bash tools/cmd/dynmod.sh backup [thư_mục_đích]       # chép engine đã build (bỏ obj/) để dùng lại
#   bash tools/cmd/dynmod.sh dsym                        # sinh dSYM Flutter.framework cho out/ios_release
#   bash tools/cmd/dynmod.sh watch <host|android|ios>    # doi build nen xong -> notification + file DONE/FAIL
#   bash tools/cmd/dynmod.sh env                         # in cac bien DYNMOD_* dang dung
#
# Biến môi trường (có mặc định):
#   DYNMOD_WORK   thư mục làm việc ngoài repo   (mặc định ../dart-sdk-build — anh em của folder project)
#   DYNMOD_REV    ghi đè version flutter/flutter (mặc định: configs/flutter.json)
#   DYNMOD_APP    app Flutter host               (mặc định $ROOT/app)
#   DYNMOD_IFACE  dynamic_interface.yaml         (mặc định $ROOT/dist/dynamic_interface.yaml)
#   DYNMOD_ENGINE_SRC  thư mục chứa out/ để app/module/status DÙNG (vd. bản backup);
#                 mặc định = engine/src của checkout. Build engine luôn ra checkout.
#
# Gotcha đã gặp và tool tự xử lý:
#   - autoninja crash với target Android trên macOS (đọc /proc) → luôn gọi ninja trực tiếp.
#   - .gclient phải nằm ở GỐC checkout flutter (solution name=".") — không đặt ở thư mục cha.
#   - Engine host cần Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).
#   - Anchor dill phải compile từ URI package: (không phải đường dẫn file), và module phải
#     import package:<app>/... — nếu không host và module thấy 2 kiểu `Registry` khác nhau.
#   - platform_strong.dill giống hệt giữa host/android/ios → 1 module dùng cho mọi nền tảng.
#
# Thời lượng thật (M4 Max 14 core): sync ~5 phút (no-history), host ~15 phút, android ~6,
# ios ~5. Disk: checkout + 3 out dir ~ vài chục GB.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${DYNMOD_WORK:-$(dirname "$ROOT")/dart-sdk-build}"  # derive từ vị trí project (anh em của repo)
# Version Flutter: configs/flutter.json (env DYNMOD_REV thắng) — xem tools/cmd/flutter_version.sh
REV="$(bash "$ROOT/tools/cmd/flutter_version.sh")"
# Flutter DÙNG (CLI flutter/dart + framework): ../engine/flutter-framework (gom 1
# chỗ, tạo bằng: bash tools/cmd/dynmod.sh backup); chưa có thì checkout build.
ENGINE_HOME="${DYNMOD_ENGINE_HOME:-$(dirname "$ROOT")/engine}"
_FF_DEF="$ENGINE_HOME/flutter-framework"; [ -x "$_FF_DEF/bin/flutter" ] || _FF_DEF="$WORK/flutter-framework"
FF_SRC="$WORK/flutter-framework"         # checkout ĐỂ BUILD engine (sync/engine/backup)
FF="${DYNMOD_FF:-$_FF_DEF}"              # Flutter DÙNG (pub get / build app / module)
SRC="$FF_SRC/engine/src"                 # nơi BUILD engine (cần source)
# Engine DÙNG (chỉ cần out/ + sdk/lib + lib/ui): ưu tiên ../engine — bản chép gọn
# (~4,3GB thay vì ~50GB checkout, tạo/cập nhật bằng: bash tools/cmd/dynmod.sh backup).
_ENG_DEF="$(dirname "$ROOT")/engine"; [ -d "$_ENG_DEF/out" ] || _ENG_DEF="$WORK/flutter-framework/engine/src"
ENGINE_SRC="${DYNMOD_ENGINE_SRC:-$_ENG_DEF}"  # nơi DÙNG engine — khác $SRC (nơi BUILD)
OUT="$ENGINE_SRC/out"
APP="${DYNMOD_APP:-$ROOT/app}"
IFACE="${DYNMOD_IFACE:-$ROOT/dist/dynamic_interface.yaml}"
DEPOT="$WORK/depot_tools"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"
LOGDIR="$ENGINE_HOME/logs"

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
ok()   { echo "  ${GRN}[PASS]${RST} $1"; }
info() { echo "  [INFO] $1"; }
die()  { echo "LỖI: $*" >&2; exit 1; }

out_dir() {  # <target> [sjfix] → tên out dir
  case "$1" in
    host)    echo host_release_arm64 ;;
    android) [ "${2:-}" = 1 ] && echo android_release_arm64_sjfix || echo android_release_arm64 ;;
    ios)     echo ios_release ;;
    *) die "target lạ: $1 (host|android|ios)" ;;
  esac
}

# File nhị phân engine chứa interpreter → dùng để verify build có dyn_modules thật.
engine_binary() {
  case "$1" in
    host*)   echo "$OUT/host_release_arm64/FlutterMacOS.framework/Versions/A/FlutterMacOS" ;;
    android*) echo "$OUT/$1/libflutter.so" ;;
    ios*)    echo "$OUT/ios_release/Flutter.framework/Flutter" ;;
  esac
}

has_interpreter() {  # <binary> → 0 nếu có chuỗi đặc trưng của interpreter
  # grep -a thẳng vào file (không pipe strings|grep -q: dưới pipefail, SIGPIPE làm pipeline "fail")
  [ -f "$1" ] && LC_ALL=C grep -a -q "Unexpected Dart bytecode magic" "$1"
}

with_log() {  # <tên> <lệnh...> → chạy, ghi log đầy đủ, in đuôi
  local name="$1"; shift
  mkdir -p "$LOGDIR"
  local log="$LOGDIR/$name-$(date +%Y%m%d-%H%M%S).log"
  info "log: $log"
  set +e
  "$@" > "$log" 2>&1
  local rc=$?
  set -e
  tail -15 "$log"
  [ "$rc" = 0 ] || die "$name thất bại (exit $rc) — xem $log"
}

# ---------------------------------------------------------------- sync
cmd_sync() {
  mkdir -p "$WORK"
  if [ ! -d "$DEPOT/.git" ]; then
    info "clone depot_tools → $DEPOT"
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT"
  fi
  export PATH="$DEPOT:$PATH"
  if [ ! -d "$FF_SRC/.git" ]; then
    info "clone flutter/flutter → $FF_SRC"
    git clone https://github.com/flutter/flutter.git "$FF_SRC"
  fi
  # REV = tag (3.47.0) hoặc commit — fetch tag thành ref local để checkout theo tên được.
  git -C "$FF_SRC" fetch --quiet origin "+refs/tags/$REV:refs/tags/$REV" 2>/dev/null \
    || git -C "$FF_SRC" fetch --quiet origin "$REV" 2>/dev/null || true
  git -C "$FF_SRC" checkout --quiet "$REV" 2>/dev/null || git -C "$FF_SRC" checkout --quiet FETCH_HEAD \
    || die "không checkout được flutter @ $REV (configs/flutter.json)"
  ok "flutter @ $(git -C "$FF_SRC" rev-parse --short=8 HEAD)"
  # .gclient ở GỐC checkout, solution name="." (xem gotcha ở đầu file)
  [ -f "$FF_SRC/.gclient" ] || cp "$FF_SRC/engine/scripts/standard.gclient" "$FF_SRC/.gclient"
  info "gclient sync -D --no-history (Android deps tải mặc định trên mac)"
  (cd "$FF_SRC" && with_log sync gclient sync -D --no-history)
  [ -x "$SRC/flutter/tools/gn" ] && ok "sync xong" || die "sync xong nhưng thiếu flutter/tools/gn"
}

# ---------------------------------------------------------------- engine
# Vá toolchain Apple (áp lúc build, hoàn nguyên sau — checkout luôn sạch để đổi version):
# clang/lld ghim trong DEPS của engine cũ hơn SDK Xcode mới (vd 3.47.x + Xcode 27:
# ld64.lld "unknown architecture" arm64e.x1 trong .tbd; -Werror,-Wignored-attributes ở
# os_log). → link mac/ios bằng ld của Xcode (-fuse-ld=ld) + bỏ cảnh báo đó. Cùng cách
# đã dùng cho engine 3.44.2 thời Shorebird. Tắt: DYNMOD_NO_TOOLCHAIN_PATCH=1.
TC_FILE="$SRC/build/config/compiler/BUILD.gn"
TC_MARK="[dynmod] apple-ld"

apply_toolchain_patch() {
  [ "$(uname -s)" = Darwin ] && [ -z "${DYNMOD_NO_TOOLCHAIN_PATCH:-}" ] || return 0
  grep -q "$TC_MARK" "$TC_FILE" && return 0
  cp -p "$TC_FILE" "$TC_FILE.dynmod-orig"
  python3 - "$TC_FILE" "$TC_MARK" <<'EOF'
import sys
p, mark = sys.argv[1], sys.argv[2]
s = open(p).read()
a = "    ldflags += common_mac_flags\n"
assert s.count(a) == 1, "không tìm thấy 'ldflags += common_mac_flags' trong build/config/compiler/BUILD.gn (engine đổi?)"
s = s.replace(a, a + f"""
    # {mark}: ld của Xcode thay ld64.lld (lld cũ không đọc .tbd SDK mới)
    ldflags += [ "-fuse-ld=ld" ]
    cflags += [ "-Wno-ignored-attributes" ]
""")
open(p, "w").write(s)
EOF
  info "đã vá tạm $TC_FILE (-fuse-ld=ld, -Wno-ignored-attributes — hoàn nguyên sau build)"
}

revert_toolchain_patch() {
  [ -f "$TC_FILE.dynmod-orig" ] && mv "$TC_FILE.dynmod-orig" "$TC_FILE" && info "đã hoàn nguyên build/config/compiler/BUILD.gn"
  return 0
}

# Backport front_end (Dart 3.13 / Flutter 3.47.x): validator dynamic module ép
# `node as Library` → dart2bytecode CRASH "type 'Extension' is not a subtype of type
# 'Library'" khi dynamic_interface có entry extension. Dart master đã sửa (bỏ qua
# Extension + member không có class). Chỉ áp khi file còn code lỗi; hoàn nguyên sau build.
FE_FILE="$SRC/flutter/third_party/dart/pkg/front_end/lib/src/kernel/dynamic_module_validator.dart"

apply_frontend_patch() {
  [ -f "$FE_FILE" ] && grep -q '(node as Library).classes' "$FE_FILE" || return 0
  cp -p "$FE_FILE" "$FE_FILE.dynmod-orig"
  python3 - "$FE_FILE" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """      if (node is Member) {
        checkExposedClass(node.enclosingClass!, node);
        registerSelectorName(node);
      } else if (node is Class) {
        checkExposedClass(node, node);
        registerClassMembers(node);
      } else {
        for (Class c in (node as Library).classes) {"""
new = """      if (node is Member) {
        if (node.enclosingClass case final enclosingClass?) {
          checkExposedClass(enclosingClass, node);
          registerSelectorName(node);
        }
      } else if (node is Class) {
        checkExposedClass(node, node);
        registerClassMembers(node);
      } else if (node is Library) {
        for (Class c in node.classes) {"""
assert s.count(old) == 1, "dynamic_module_validator.dart khác mẫu — kiểm tra lại backport"
open(p, "w").write(s.replace(old, new))
EOF
  info "đã backport tạm $FE_FILE (Extension trong dynamically-callable — hoàn nguyên sau build)"
}

revert_frontend_patch() {
  [ -f "$FE_FILE.dynmod-orig" ] && mv "$FE_FILE.dynmod-orig" "$FE_FILE" && info "đã hoàn nguyên dynamic_module_validator.dart"
  return 0
}

SJ_FILE="$SRC/flutter/third_party/dart/runtime/vm/interpreter.cc"
SJ_MARK="[THESIS EXPERIMENT] setjmp"

apply_setjmp_patch() {
  grep -q "$SJ_MARK" "$SJ_FILE" && return 0
  cp "$SJ_FILE" "$SJ_FILE.dynmod-orig"
  python3 - "$SJ_FILE" "$SJ_MARK" <<'EOF'
import sys
p, mark = sys.argv[1], sys.argv[2]
s = open(p).read()
a = '#include "vm/globals.h"\n#if defined(DART_DYNAMIC_MODULES)\n'
assert a in s, 'không tìm thấy điểm chèn trong interpreter.cc (Dart đổi?)'
s = s.replace(a, a + f'''
// {mark}: bionic setjmp() lưu signal mask → syscall sigprocmask MỖI lần interpreter
// gọi runtime/native/compiled. Apple đã dùng _setjmp (platform/globals.h). Xem
// docs/dyn_modules_speed_result.md §4.
#if defined(DART_HOST_OS_ANDROID) && !__has_feature(thread_sanitizer)
#undef DART_SETJMP
#undef DART_LONGJMP
#define DART_SETJMP _setjmp
#define DART_LONGJMP _longjmp
#endif
''', 1)
open(p, 'w').write(s)
EOF
  info "đã vá tạm $SJ_FILE (sẽ hoàn nguyên sau build)"
}

revert_setjmp_patch() {
  [ -f "$SJ_FILE.dynmod-orig" ] && mv "$SJ_FILE.dynmod-orig" "$SJ_FILE" && info "đã hoàn nguyên interpreter.cc"
  return 0
}

build_one() {  # <host|android|ios> <sjfix 0|1>
  local t="$1" sj="$2" od; od="$(out_dir "$t" "$sj")"
  local gnargs=(--runtime-mode release --no-lto --no-prebuilt-dart-sdk --gn-args=dart_dynamic_modules=true)
  local targets=()
  case "$t" in
    host)    gnargs+=(--mac-cpu arm64 --full-dart-sdk) ;;
    android) gnargs+=(--android --android-cpu arm64) ;;
    ios)     gnargs+=(--ios)
             targets=(flutter/lib/snapshot:generate_snapshot_bins flutter/shell/platform/darwin/ios:flutter_framework) ;;
  esac
  [ "$sj" = 1 ] && gnargs+=(--target-dir "$od")
  echo "== engine $t → out/$od =="
  export PATH="$DEPOT:$PATH"
  if [ "$sj" = 1 ]; then
    [ "$t" = android ] || die "--patch-setjmp chỉ áp cho android (Apple đã dùng _setjmp)"
    apply_setjmp_patch
    trap revert_setjmp_patch EXIT
  fi
  apply_toolchain_patch
  apply_frontend_patch
  trap 'revert_toolchain_patch; revert_frontend_patch; revert_setjmp_patch' EXIT
  (cd "$SRC" && with_log "gn-$od" flutter/tools/gn "${gnargs[@]}")
  # ninja TRỰC TIẾP — autoninja hỏng với target Android trên macOS
  (cd "$SRC" && with_log "ninja-$od" ninja -j "$JOBS" -C "out/$od" ${targets[@]+"${targets[@]}"})
  revert_toolchain_patch
  revert_frontend_patch
  if [ "$sj" = 1 ]; then revert_setjmp_patch; fi
  trap - EXIT
  local OUT="$SRC/out"   # kiểm tra bản vừa build (không phải DYNMOD_ENGINE_SRC)
  if has_interpreter "$(engine_binary "$od")"; then ok "out/$od có interpreter (dyn_modules)"
  else die "out/$od build xong nhưng KHÔNG thấy interpreter — kiểm tra args.gn"; fi
  # Stamp revision → setup/doctor biết engine build từ version nào (đổi configs/flutter.json = build lại)
  { git -C "$FF_SRC" rev-parse HEAD; echo "$REV"; } > "$OUT/$od/$(bash "$ROOT/tools/cmd/flutter_version.sh" --stamp-name)"
  if [ "$t" = ios ]; then ios_dsym "$OUT/$od"; fi
}

# dSYM của Flutter.framework (engine ios): binary đã strip, DWARF nằm trong obj/ của
# checkout build → dsymutil theo debug map. Đặt vào xcframework/ios-arm64/dSYMs/ —
# flutter_tools (local engine) tự chép vào build → archive có dSYM, App Store Connect
# không báo "archive did not include a dSYM for the Flutter.framework".
# Chỉ chạy được ở máy còn obj/ (../dart-sdk-build); backup chép kèm sang ../engine.
ios_dsym() {  # <out_dir ios_release>
  local od="$1"
  local bin="$od/Flutter.xcframework/ios-arm64/Flutter.framework/Flutter"
  local dsym="$od/Flutter.xcframework/ios-arm64/dSYMs/Flutter.framework.dSYM"
  [ -f "$bin" ] || die "không thấy $bin"
  local want have
  want="$(dwarfdump --uuid "$bin" | awk '{print $2}')"
  have="$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$want" ] && [ "$have" = "$want" ]; then
    ok "dSYM Flutter.framework khớp UUID $want"; return 0
  fi
  [ -d "$od/obj" ] || die "thiếu $od/obj (object của bản build) → không sinh được dSYM; chạy ở máy build engine"
  rm -rf "$dsym"
  mkdir -p "$(dirname "$dsym")"
  mkdir -p "$LOGDIR"
  local log="$LOGDIR/dsym-ios-$(date +%Y%m%d-%H%M%S).log"
  info "dsymutil Flutter.framework… (log: $log — cảnh báo thiếu .pcm/.pch là bình thường)"
  dsymutil "$bin" -o "$dsym" > "$log" 2>&1 || die "dsymutil thất bại — xem $log"
  have="$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}' || true)"
  [ "$have" = "$want" ] || die "dSYM sinh ra lệch UUID (${have:-rỗng} ≠ $want)"
  local cus; cus="$(dwarfdump --debug-info "$dsym" 2>/dev/null | grep -c DW_TAG_compile_unit || true)"
  [ "${cus:-0}" -gt 0 ] || die "dSYM không có DWARF — obj/ build không kèm debug info?"
  ok "dSYM Flutter.framework → $dsym ($(du -sh "$dsym" | cut -f1), $cus compile unit)"
}

cmd_engine() {
  local what="${1:-}"; shift || true
  local sj=0 bg=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --patch-setjmp) sj=1; shift ;;
      --bg) bg=1; shift ;;
      --jobs) JOBS="${2:?thiếu số sau --jobs}"; shift 2 ;;
      *) die "cờ lạ: $1" ;;
    esac
  done
  [ -x "$SRC/flutter/tools/gn" ] || die "chưa sync — chạy: bash tools/cmd/dynmod.sh sync"
  # --bg: chay nen + tu watch (notification + file DONE/FAIL), khong can canh.
  if [ "$bg" = 1 ]; then
    case "$what" in
      host|android|ios) ;;
      *) die "--bg chi dung voi 1 target (host|android|ios), khong dung voi all" ;;
    esac
    local od; od="$(out_dir "$what" "$sj")"
    local log="$LOGDIR/ninja-$od-$(date +%Y%m%d-%H%M%S).log"
    info "build nen out/$od — log: $log"
    # Moi lan goi deedline rieng de tranh nhieu job ninja danh nhau.
    DYNMOD_JOBS="$JOBS" nohup bash -c "DYNMOD_WORK='$WORK' DYNMOD_REV='$REV' '$ROOT/tools/cmd/dynmod.sh' engine '$what' $([ "$sj" = 1 ] && echo --patch-setjmp) --jobs '$JOBS'" > "$log" 2>&1 &
    info "engine pid $! — tien trinh ninja that ten la 'ninja -C out/$od'"
    nohup bash "$ROOT/tools/cmd/dynmod.sh" watch "$what" > "$LOGDIR/watch-$od.log" 2>&1 &
    info "watch pid $! — xong co file $LOGDIR/${od}_DONE.txt + notification"
    return 0
  fi
  case "$what" in
    host|ios) build_one "$what" 0 ;;
    android)  build_one android "$sj" ;;
    all)      build_one host 0; build_one android "$sj"; build_one ios 0 ;;
    *) die "dùng: engine <host|android|ios|all> [--patch-setjmp] [--bg] [--jobs N]" ;;
  esac
}

# ---------------------------------------------------------------- app helpers
# May reset hay doi WORK/checkout -> pubspec cu sai path. Ham nay dam bao
# dynamic_modules path dep luon tro dung checkout hien tai + du http/crypto.
# package dynamic_modules (app path-dep): ưu tiên bản chép trong engine DÙNG
# (../engine — dynmod.sh backup chép kèm), không có thì lấy từ checkout.
dynmod_pkg_dir() {
  local p="$ENGINE_SRC/flutter/third_party/dart/pkg/dynamic_modules"
  [ -d "$p" ] || p="$SRC/flutter/third_party/dart/pkg/dynamic_modules"
  echo "$p"
}

ensure_pubspec_dep() {
  local dart_pm; dart_pm="$(dynmod_pkg_dir)"
  [ -d "$dart_pm" ] || die "chua sync — thieu $dart_pm"
  [ -f "$APP/pubspec.yaml" ] || die "khong thay $APP/pubspec.yaml — app/ là project host của repo — kiểm DYNMOD_APP"
  # crypto ^6 khong ton tai (pub chi co ^3) -> sua luon de pub get khong fail.
  sed -i '' 's/crypto: \^6\.0\.0/crypto: ^3.0.0/' "$APP/pubspec.yaml" 2>/dev/null || true
  python3 - "$APP/pubspec.yaml" "$dart_pm" <<'PYEOF'
import os, sys
p, pm = sys.argv[1], sys.argv[2]
# Path TƯƠNG ĐỐI so với pubspec — không ghi đường dẫn tuyệt đối vào repo.
pm = os.path.relpath(pm, os.path.dirname(os.path.abspath(p)))
s = open(p).read()
block = f"  dynamic_modules:\n    path: {pm}\n"
if "dynamic_modules:" in s:
  import re
  # Thay ca dong comment mau bi sot (tranh grep nham).
  s = re.sub(r"  # dynamic_modules:.*\n  # .*\n", block, s)
  s = re.sub(r"  dynamic_modules:\n(?:    .*\n)+", block, s)
  if "path: " not in s.split("dynamic_modules:")[1].split("\n")[1]:
    s = s.replace("  dynamic_modules:\n", block, 1)
else:
  s = s.replace("  http:", block + "  http:")
open(p, "w").write(s)
print("pubspec dynamic_modules ->", pm)
PYEOF
  # loading_kit/dyn_loader (phụ thuộc của app ở G6) cũng trỏ path dynamic_modules.
  local dynloader="$ROOT/loading_kit/dyn_loader/pubspec.yaml"
  if [ -f "$dynloader" ]; then
    python3 - "$dynloader" "$dart_pm" <<'PYEOF'
import os, re, sys
p, pm = sys.argv[1], sys.argv[2]
# Path TƯƠNG ĐỐI so với pubspec — không ghi đường dẫn tuyệt đối vào repo.
pm = os.path.relpath(pm, os.path.dirname(os.path.abspath(p)))
s = open(p).read()
s = re.sub(r"  dynamic_modules:\n(?:    path: .*\n)", f"  dynamic_modules:\n    path: {pm}\n", s)
open(p, "w").write(s)
print("dyn_loader pubspec dynamic_modules ->", pm)
PYEOF
  fi
  grep -q "path: .*dynamic_modules" "$APP/pubspec.yaml" || grep -q "path: $dart_pm" "$APP/pubspec.yaml" || die "patch pubspec that bai"
}

# Patch platform tu dong truoc moi lan build app.
# KHONG co nhanh macOS: app chi build android/ios (xem pham vi o dau file).
ensure_platform_patches() {
  local plat="${1:-android}"
  if [ "$plat" = android ] && [ -f "$APP/android/app/src/main/AndroidManifest.xml" ]; then
    local mf="$APP/android/app/src/main/AndroidManifest.xml"
    grep -q "android.permission.INTERNET" "$mf" || python3 - "$mf" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "android.permission.INTERNET" not in s:
  s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if "usesCleartextTraffic" not in s:
  s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
open(p, "w").write(s)
print("patched AndroidManifest (INTERNET + cleartext lab)")
PYEOF
  fi
}

# Chon iface: $APP/dynamic_interface.yaml (neu app co) else $IFACE = dist/ (sinh bang dyniface.sh).
iface_for_app() {
  if [ -f "$APP/dynamic_interface.yaml" ]; then echo "$APP/dynamic_interface.yaml"
  else echo "$IFACE"; fi
}

# Sinh ban dynamic_interface CHO HOST BUILD (anchor + flutter build): gỡ entry
# `dynamically-callable` trỏ library KHÔNG có trong host program — giữ thì
# annotator host crash "The library 'X' has not been indexed" →
# Target kernel_snapshot_program failed. Bản đầy đủ ($1) vẫn là input cho
# `dart2bytecode --validate` lúc compile module. Chi tiet: tools/cmd/dyniface/gen_host_iface.py
host_iface() {
  local src="$1" out="$ROOT/dist/dynamic_interface.host.yaml"
  # report của python → stderr để `$(host_iface ...)` chỉ captures đường dẫn
  python3 "$ROOT/tools/cmd/dyniface/gen_host_iface.py" --src "$src" --out "$out" >&2 \
    || { echo "LỖI: sinh dynamic_interface.host.yaml thất bại" >&2; return 1; }
  echo "$out"
}

# ---------------------------------------------------------------- app
# Tu dong: pubspec path dep -> checkout hien tai + flutter pub get + patch
# AndroidManifest (INTERNET/cleartext) truoc khi build.
# CHI android|ios — macOS khong phai target app (xem pham vi o dau file).
cmd_app() {
  local plat="${1:-}"; shift || true
  local sj=0 extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --sjfix) sj=1; shift ;;
      --) shift; extra=("$@"); break ;;
      *) extra+=("$1"); shift ;;
    esac
  done
  local eng kind
  case "$plat" in
    android) eng="$(out_dir android "$sj")"; kind=apk; extra=(--target-platform android-arm64 ${extra[@]+"${extra[@]}"}) ;;
    ios)     eng=ios_release; kind=ios ;;
    *) die "dùng: app <android|ios> [--sjfix] [-- cờ flutter build]" ;;
  esac
  [ -d "$OUT/$eng" ] || die "chưa có engine out/$eng — chạy: bash tools/cmd/dynmod.sh engine $plat"
  # engine host: bat buoc cho ca 2 — `--local-engine-host` + dartaotruntime
  # (gen_kernel anchor.dill + dart2bytecode compile module).
  [ -d "$OUT/host_release_arm64" ] || die "cần engine host (local-engine-host + compile module) — chạy: engine host"
  local IF; IF="$(iface_for_app)"
  [ -f "$IF" ] || die "không thấy $IF"
  # Bản host (gỡ entry dynamically-callable ngoài host program) — bản $IF đầy
  # đủ vẫn là input validate của module.
  local IF_HOST; IF_HOST="$(host_iface "$IF")" || die "sinh dynamic_interface.host.yaml thất bại"
  echo "== app $plat (engine $OUT/$eng) =="
  # 0. pubspec: dynamic_modules path -> checkout hien tai (may reset doi duong dan).
  ensure_pubspec_dep
  # 1. pub get bang flutter cua checkout (khop Dart SDK co dynamic_modules).
  (cd "$APP" && with_log "pubget-$plat" "$FF/bin/flutter" pub get)
  # 2. Patch platform: Android INTERNET+cleartext (lab).
  ensure_platform_patches "$plat"
  (cd "$APP" && with_log "app-$plat" "$FF/bin/flutter" build "$kind" --release \
     --local-engine-src-path "$ENGINE_SRC" --local-engine="$eng" --local-engine-host=host_release_arm64 \
     --extra-front-end-options=--dynamic-interface="$IF_HOST" ${extra[@]+"${extra[@]}"})
}

# ---------------------------------------------------------------- pubget
# Patch pubspec path dep (dynamic_modules -> checkout hien tai) + flutter pub
# get, KHONG build app. Dung cho setup/CI khi chi can resolve deps.
cmd_pubget() {
  # CHỈ Flutter của engine (CLAUDE.md §1) — KHÔNG lùi về flutter trong PATH:
  # bản khác version ghi lại pubspec.lock → lệch ABI host.
  local f; f="$FF/bin/flutter"
  [ -x "$f" ] || die "không thấy $f — chạy: bash tools/setup.sh (hoặc dynmod.sh backup)"
  ensure_pubspec_dep
  (cd "$APP" && with_log "pubget" "$f" pub get)
  ok "app pub get xong: $APP"
}

# ---------------------------------------------------------------- module
cmd_module() {
  local mod="${1:-}"; shift || true
  # Entry MAC DINH = wrapper module trong ../app_package (host luon la $ROOT/app,
  # module luon la thu muc anh em app_package — duong dan tu ROOT chay).
  [ -n "$mod" ] || mod="$ROOT/../app_package/modules/home_content.dart"
  # Resolve ve abs: dart2bytecode chay trong cwd=$APP nen path tuong doi
  # (repo root hoac cwd khac) se trỏ sai chỗ — khong thi loi "No such file".
  case "$mod" in
    /*) : ;;
    *)
      if [ -f "$mod" ]; then
        mod="$(cd "$(dirname "$mod")" && pwd)/$(basename "$mod")"
      elif [ -f "$ROOT/$mod" ]; then
        mod="$ROOT/$mod"
      else
        die "không thấy module '$mod' (tìm ở cwd và $ROOT) — dùng: module [module.dart] (mặc định $ROOT/../app_package/modules/home_content.dart — sau convert_to_package chạy: bash tools/cmd/modprep.sh apply)"
      fi
      ;;
  esac
  [ -f "$mod" ] || die "không thấy module $mod"
  local entry_host="lib/main.dart" outf=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --entry) entry_host="${2:?}"; shift 2 ;;
      -o) outf="${2:?}"; shift 2 ;;
      *) die "cờ lạ: $1" ;;
    esac
  done
  local H="$OUT/host_release_arm64"
  local AOT="$H/dart-sdk/bin/dartaotruntime"
  [ -x "$AOT" ] || die "chưa có engine host (dart2bytecode nằm ở đó) — chạy: engine host"
  local P; P="$(ls "$OUT"/*/flutter_patched_sdk/platform_strong.dill 2>/dev/null | head -1)"
  [ -n "$P" ] || die "không thấy platform_strong.dill"
  local pkg; pkg="$(awk '/^name:/{print $2; exit}' "$APP/pubspec.yaml")"
  local rel; rel="$entry_host"
  # Chấp nhận cả `lib/main.dart` lẫn `package:<pkg>/main.dart` (plan G4 dùng dạng
  # package URI) — tránh ghép thành "package:app/package:app/main.dart".
  case "$rel" in
    package:*) : ;;
    lib/*)      rel="${rel#lib/}" ;;
    *)          die "--entry phải là lib/main.dart hoặc package:<pkg>/main.dart, nhận '$entry_host'" ;;
  esac
  local uri="package:$pkg/$rel"
  if grep -qE "^import '\.\./lib/" "$mod"; then
    die "$mod import bằng đường dẫn tương đối ../lib/ → đổi sang 'package:$pkg/...' (nếu không host và module lệch kiểu)"
  fi
  [ -n "$outf" ] || outf="$ENGINE_HOME/modules/$(basename "${mod%.dart}").bytecode"
  mkdir -p "$(dirname "$outf")"
  local anchor="${outf%.bytecode}.anchor.dill"
  local IF; IF="$(iface_for_app)"
  [ -f "$IF" ] || die "không thấy $IF"
  # Anchor = host program → annotator dùng BẢN HOST; dart2bytecode --validate
  # (dòng dưới) vẫn dùng bản đầy đủ $IF.
  local IF_HOST; IF_HOST="$(host_iface "$IF")" || die "sinh dynamic_interface.host.yaml thất bại"
  echo "== module $mod (host entry $uri, iface $IF) =="
  (cd "$APP" && with_log anchor "$AOT" "$H/gen/gen_kernel_aot.dart.snapshot" --platform "$P" --target flutter \
     --no-aot --no-link-platform --packages "$APP/.dart_tool/package_config.json" \
     --dynamic-interface "$IF_HOST" -Ddart.vm.product=true --output "$anchor" "$uri")
  (cd "$APP" && with_log dart2bytecode "$AOT" "$H/gen/dart2bytecode.dart.snapshot" --platform "$P" --target flutter \
     --import-dill "$anchor" --validate "$IF" --packages "$APP/.dart_tool/package_config.json" \
     --allow-dynamic-calls-in-dynamic-modules \
     -Ddart.vm.product=true --output "$outf" "$mod")
  ok "$outf ($(stat -f%z "$outf") B, sha256 $(shasum -a 256 "$outf" | cut -c1-16)…)"
  info "anchor phải khớp ĐÚNG entry của app đã build (-t). Đổi host → compile lại module."
}

# ---------------------------------------------------------------- watch
# Doi build nen xong -> notification + file DONE/FAIL.
cmd_watch() {
  local what="${1:-host}"
  local od="$what"
  case "$what" in
    host) od=host_release_arm64 ;;
    android) od=android_release_arm64 ;;
    ios) od=ios_release ;;
  esac
  local bin="$SRC/out/$od"
  case "$od" in
    host_release_arm64) bin="$SRC/out/$od/FlutterMacOS.framework/Versions/A/FlutterMacOS" ;;
    android*) bin="$SRC/out/$od/libflutter.so" ;;
    ios*) bin="$SRC/out/$od/Flutter.framework/Flutter" ;;
  esac
  local log; log="$(ls -t "$LOGDIR"/ninja-"$od"*.log 2>/dev/null | head -1)"
  [ -n "${log:-}" ] || die "khong thay log ninja cho $od trong $LOGDIR"
  local done_f="$LOGDIR/${od}_DONE.txt"
  local fail_f="$LOGDIR/${od}_FAIL.txt"
  rm -f "$done_f" "$fail_f"
  echo "[watch] doi out/$od — log: $log"
  while pgrep -f "ninja.*$od" >/dev/null; do
    tail -n 1 "$log" 2>/dev/null | cut -c1-160; echo ""
    sleep 60
  done
  if [ -f "$bin" ] && LC_ALL=C grep -a -q "Unexpected Dart bytecode magic" "$bin" 2>/dev/null; then
    { echo "$od OK $(date)"; tail -n 5 "$log"; } | tee "$done_f"
    osascript -e "display notification \"Engine $od build xong, co interpreter\" with title \"dynmod build\"" 2>/dev/null || true
    echo "BUILD_XONG_OK ($done_f)"
  else
    { echo "$od FAIL hoac thieu interpreter $(date)"; tail -n 30 "$log"; } | tee "$fail_f"
    osascript -e "display notification \"Engine $od build FAIL — xem log\" with title \"dynmod build\"" 2>/dev/null || true
    echo "BUILD_XONG_FAIL ($fail_f)"
  fi
}

# ---------------------------------------------------------------- backup
# flutter_tools chỉ cần <src>/out/<engine> (runner/local_engine.dart: _tryEnginePath kiểm tra
# đúng thư mục out/). obj/ = object trung gian (host ~17GB) → bỏ, chỉ cần khi build lại.
cmd_backup() {
  # Mặc định ra ../engine = chỗ mọi tool tự dùng (xem _ENG_DEF ở đầu file).
  local dest="${1:-$(dirname "$ROOT")/engine}"
  local src_out="$SRC/out"
  [ -d "$src_out" ] || die "không có $src_out"
  mkdir -p "$dest/out"
  echo "== backup engine → $dest =="
  local od n=0
  for od in host_release_arm64 android_release_arm64 android_release_arm64_sjfix ios_release; do
    [ -d "$src_out/$od" ] || continue
    if ! OUT="$src_out" has_interpreter "$(OUT="$src_out" engine_binary "$od")"; then
      info "bỏ qua out/$od (chưa build xong / không có interpreter)"; continue
    fi
    if [ "$od" = ios_release ]; then ios_dsym "$src_out/$od"; fi
    rsync -a --delete --exclude='obj/' --exclude='*_unittests' --exclude='*_unittests.*' \
      --exclude='compile_commands.json' --exclude='gn_trace.json' --exclude='gen/*_test.dart.dill*' \
      "$src_out/$od/" "$dest/out/$od/"
    ok "out/$od → $(du -sh "$dest/out/$od" | cut -f1)"
    n=$((n+1))
  done
  [ "$n" -gt 0 ] || die "không có engine nào để backup"
  # Nguồn SDK cho tools/cmd/dyniface/*.py (quét khai báo dart:* / dart:ui) — ~14MB
  mkdir -p "$dest/flutter/third_party/dart/sdk" "$dest/flutter/lib"
  rsync -a --delete "$SRC/flutter/third_party/dart/sdk/lib" "$dest/flutter/third_party/dart/sdk/"
  rsync -a --delete "$SRC/flutter/lib/ui" "$dest/flutter/lib/"
  # package dynamic_modules (app path-dep, ~1MB) — xem dynmod_pkg_dir
  mkdir -p "$dest/flutter/third_party/dart/pkg"
  rsync -a --delete "$SRC/flutter/third_party/dart/pkg/dynamic_modules" "$dest/flutter/third_party/dart/pkg/"
  # Flutter framework + CLI (bin/flutter, bin/dart, cache, .git) — BỎ engine/src
  # (~53GB, chỉ cần khi build lại engine) → mọi tool DÙNG chỉ cần mỗi ../engine.
  mkdir -p "$dest/flutter-framework"
  rsync -a --delete --exclude='/engine/src/' "$FF_SRC/" "$dest/flutter-framework/"
  ok "flutter-framework → $(du -sh "$dest/flutter-framework" | cut -f1) (không gồm engine/src)"
  {
    echo "dynmod engine backup — $(date)"
    echo "flutter_version: $REV   (configs/flutter.json)"
    echo "flutter_rev: $(git -C "$FF_SRC" rev-parse HEAD 2>/dev/null || echo "$REV")"
    echo "dart_rev: $(awk -F'\"' '/^dart_version/{print $2}' "$dest/out/"*/args.gn 2>/dev/null | head -1)"
    echo "machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null) / macOS $(sw_vers -productVersion)"
    echo
    echo "Dùng lại (framework PHẢI cùng revision flutter_rev ở trên):"
    echo "  DYNMOD_ENGINE_SRC=$dest bash tools/cmd/dynmod.sh app <android|ios>"
    echo "  hoặc: flutter build ... --local-engine-src-path $dest --local-engine=<out> --local-engine-host=host_release_arm64"
    echo
    echo "sha256 binary engine:"
    for od in "$dest"/out/*; do
      local b; b="$(OUT="$dest/out" engine_binary "$(basename "$od")")"
      [ -f "$b" ] && echo "  $(shasum -a 256 "$b" | cut -c1-64)  ${b#$dest/}"
    done
  } > "$dest/MANIFEST.txt"
  if [ -f "$SJ_FILE" ] && [ -d "$dest/out/android_release_arm64_sjfix" ]; then
    info "android_release_arm64_sjfix là bản VÁ thử nghiệm (xem docs/dyn_modules_speed_result.md §4)"
  fi
  ok "tổng: $(du -sh "$dest" | cut -f1) — MANIFEST: $dest/MANIFEST.txt"
}

# ---------------------------------------------------------------- env
cmd_env() {
  echo "DYNMOD_WORK=$WORK"
  echo "DYNMOD_REV=$REV"
  echo "DYNMOD_APP=$APP"
  echo "DYNMOD_IFACE=$IFACE"
  echo "DYNMOD_ENGINE_SRC=$ENGINE_SRC"
  echo "FF=$FF   (dùng)"
  echo "FF_SRC=$FF_SRC   (build engine)"
  echo "ENGINE_HOME=$ENGINE_HOME"
  echo "SRC=$SRC"
  echo "OUT=$OUT"
  echo "DEPOT=$DEPOT"
  echo "LOGDIR=$LOGDIR"
}

# ---------------------------------------------------------------- status
cmd_status() {
  echo "== Engine out dirs ($OUT) =="
  local od
  for od in host_release_arm64 android_release_arm64 android_release_arm64_sjfix ios_release; do
    if [ -d "$OUT/$od" ]; then
      if has_interpreter "$(engine_binary "$od")"; then ok "out/$od (có interpreter)"
      else info "out/$od tồn tại nhưng chưa build xong / không có interpreter"; fi
    else
      info "out/$od: chưa build"
    fi
  done
}

case "${1:-}" in
  sync)   cmd_sync ;;
  watch)  shift; cmd_watch "$@" ;;
  env)    cmd_env ;;
  engine) shift; cmd_engine "$@" ;;
  app)    shift; cmd_app "$@" ;;
  pubget) cmd_pubget ;;
  module) shift; cmd_module "$@" ;;
  status) cmd_status ;;
  backup) shift; cmd_backup "$@" ;;
  dsym)   ios_dsym "$SRC/out/ios_release" ;;
  *) sed -n '2,22p' "$0"; exit 1 ;;
esac
