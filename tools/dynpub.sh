#!/usr/bin/env bash
# tools/dynpub.sh — TOOL PUBLISH theo release registry
# (docs/release_registry_design.md): build host từng app, ra patch, quản lý
# trạng thái store / app thay thế / force, deploy manifest.
#
# Env (staging / pre / prod — configs/deploy.json): mỗi app thuộc 1 env
# (configs/apps/<bundle>.json "env"), mỗi env 1 rs_domain + 1 manifest. Patch
# chọn env lúc ra, đưa lên env khác sau ([4]).
#
#   bash tools/dynpub.sh              # WIZARD — chọn số, không cần tham số
#
#   ── Hằng ngày
#   [1] Ra patch                       app_package → .bytecode → chọn env → registry → manifest
#   [2] Deploy lên rs_domain           theo env / theo app: bytecode → manifest lên server, rồi chép config sang ../configs/apps
#   [3] Xem kế hoạch (plan)            ai chạy tới patch nào, ai bị mời/ép, mở đâu
#   [4] Đưa patch lên env khác         vd staging → pre → prod
#   ── Phát hành bản app
#   [5] Build host (release app)       chọn app → platform → kiểu build → ngày unlock (version_code tự tăng mỗi lần build)
#                                      → ghi registry/hosts/ + ngày unlock vào loading_kit + tự commit (KHÔNG deploy — máy build không có VPN)
#   [6] Trạng thái store 1 bản build   submitted / live / removed / rejected → registry/store/ (chỉ file này vào manifest)
#   ── Sự cố / ép
#   [7] Rút patch lỗi (retract)        rút khỏi mọi env
#   [8] Ép cập nhật / ép restart       gom các kiểu ép:
#        [1] Bắt cập nhật theo version_code  lỗi ở app: build < N phải lên store
#        [2] Cấm patch cũ (block-below)      theo env — máy bị cấm update chính app nếu có bản cao hơn, không thì app thay thế chung
#        [3] Ép restart (min_force_update)   patch đã ra: máy chạy patch < M, tải xong sẽ hiện popup khởi động lại
#        [4] App thay thế chung (prod)       Android + iOS: app chết → mời sang; bị ép mà không có bản cao hơn → ép sang
#   ── Ít dùng
#   [9] Quản lý app                    thêm app (chọn env) / đổi env / đánh dấu app chết / Apple ID
#   [10] Kiểm link store / app thay thế (cron)
#   [11] Đổi package host (ABI)        app_package đòi version package host khác → pub get → xác nhận → chụp mốc + commit lock
#   [12] Đổi rs_domain của env         ghi lại config mọi app của env đó rồi deploy
#   [13] Đổi api_domain của env        ghi api_domain của env vào deploy.json + mọi config app của env đó
#   ── Dev
#   [14] Chạy thử app trên simulator   chọn app → tools/cmd/run.sh ios-sim (chưa bật simulator thì tự mở)
#
# Không tương tác (CI / cron):
#   bash tools/dynpub.sh release --app <bundleId> --platform ios|android [--version 1.0.5+5] [--mode M] [--unlock D]
#        (bỏ --version = tự tăng; --unlock như wizard: 2026-10-20 | 20/10/2026 | +3 | 0 | -1 — bỏ = giữ ngày đang có trong code)
#   bash tools/dynpub.sh patch --envs staging[,pre,prod] [--min-force-update N]
#   bash tools/dynpub.sh reg <lệnh registry…>     # vd: reg check-links | reg plan | reg deploy --env staging
#
# Mode build:
#   Android : ddm (mặc định — engine ddm, module OTA) | debug (engine stock, không đăng ký registry)
#   iOS     : adhoc (mặc định) | appstore | debug | profile (debug/profile không đăng ký registry)
#
# Mỗi app: apps/<bundleId>/ (app.yaml + main_app/ + assets/) — menu [9] tạo khung.
# apps/_reference/main_app: host THAM CHIẾU khi compile patch + khung cho app mới
# (thư mục bắt đầu bằng "_" không phải app, wizard bỏ qua).
# Env: DYNMOD_FF (checkout flutter build engine), DYNMOD_WORK / DYNMOD_ENGINE_SRC,
#      DYNPUB_YES=1 (tự trả lời Y cho câu hỏi deploy/commit).

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/tools/cmd"
REGPY="$ROOT/tools/registry/registry.py"
IDPY="$ROOT/tools/registry/app_identity.py"
APPS_DIR="${REGISTRY_APPS_DIR:-$ROOT/apps}"

die() { echo "LỖI: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'; }
info() { echo "  [dynpub] $*"; }
reg() { python3 -B "$REGPY" "$@"; }
idt() { python3 -B "$IDPY" "$@"; }

# ── helpers tương tác ────────────────────────────────────────────────────────
# Hỏi 1 dòng: ask <prompt> [default] → $REPLY. EOF → die.
ask() {
  local p="$1" def="${2:-}"
  if [ -n "$def" ]; then
    read -r -p "$p [$def]: " REPLY || die "EOF (Ctrl-D) — dừng"
    REPLY="${REPLY:-$def}"
  else
    read -r -p "$p: " REPLY || die "EOF (Ctrl-D) — dừng"
  fi
  [ -n "$REPLY" ] || die "không được rỗng: $p"
}

# yes_no <prompt> <Y|N mặc định> → 0 = có.
yes_no() {
  local p="$1" def="$2" a
  if [ "${DYNPUB_YES:-0}" = 1 ]; then return 0; fi
  if [ "$def" = Y ]; then read -r -p "$p [Y/n]: " a || a=n; a="${a:-y}"
  else read -r -p "$p [y/N]: " a || a=n; a="${a:-n}"; fi
  case "$a" in y|Y|yes|có|co) return 0 ;; *) return 1 ;; esac
}

# Chọn số: choose <tiêu đề> <lựa 1> ... → $CHOICE (1-based). Không hợp lệ → hỏi lại.
# choose "<tiêu đề>" <mục>… → $CHOICE (1-based, chỉ đếm mục). Mục bắt đầu
# bằng "--" = dòng tiêu đề nhóm (không đánh số, không chọn được).
choose() {
  local title="$1" i=1 opt
  shift
  echo
  echo "$title"
  for opt in "$@"; do
    if [[ "$opt" == --* ]]; then printf '  ── %s\n' "${opt#--}"; continue; fi
    printf '  [%d] %s\n' "$i" "$opt"; i=$((i + 1))
  done
  while true; do
    read -r -p "Chọn [1-$((i - 1))]: " CHOICE || die "EOF — dừng"
    if [[ "${CHOICE:-}" =~ ^[0-9]+$ ]] \
        && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le $((i - 1)) ]; then
      return 0
    fi
    echo "  nhập số trong [1-$((i - 1))]"
  done
}

# Ngày unlock (BootConfig.appReleaseDate trong loading_kit): máy mới cài, trước
# ngày này chạy demo. Hỏi tới khi hợp lệ → $UNLOCK_DATE (YYYY-MM-DD).
ask_unlock() {
  local cur x
  cur="$(python3 -B "$T/unlockdate.py" show)" || die "không đọc được ngày unlock trong loading_kit"
  echo
  echo "Ngày unlock (trước ngày này máy mới cài chạy demo) — hôm nay $(date +%F), code đang ghi $cur"
  echo "  ngày:  2026-10-20 | 20/10/2026 | 20/10 (năm nay)"
  echo "  hoặc số ngày so với hôm nay:  +3 (3 ngày nữa) | 0 (hôm nay) | -1 (hôm qua = mở ngay)"
  while true; do
    read -r -p "Ngày unlock: " x || die "EOF — dừng"
    [ -n "$x" ] || { echo "  bắt buộc nhập"; continue; }
    UNLOCK_DATE="$(python3 -B "$T/unlockdate.py" parse "$x")" || continue
    yes_no "  đúng ngày này?" Y && return 0
  done
}

# Đọc stdout của lệnh thành mảng LINES (bash 3.2 không có mapfile).
read_lines() {
  LINES=()
  local l
  while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < <("$@")
}

# Chọn app: pick_bundle <cho phép nhập mới: 1|0> → $BUNDLE.
# Danh sách = bundle trong registry + thư mục apps/ chưa đăng ký.
pick_bundle() {
  local allow_new="$1" b d l
  local -a ids=() labels=()
  read_lines reg list-bundles
  for l in ${LINES[@]+"${LINES[@]}"}; do
    IFS=$'\t' read -r b st e <<< "$l"
    ids+=("$b"); labels+=("$b  ($st, env $e)")
  done
  if [ -d "$APPS_DIR" ]; then
    for d in "$APPS_DIR"/*/; do
      [ -d "$d" ] || continue
      b="$(basename "$d")"
      case "$b" in _*) continue ;; esac   # _reference… không phải app
      case " ${ids[*]-} " in *" $b "*) continue ;; esac
      ids+=("$b"); labels+=("$b  (có apps/ nhưng chưa đăng ký)")
    done
  fi
  if [ "$allow_new" = 1 ]; then labels+=("(nhập bundle id khác)"); fi
  [ ${#labels[@]} -gt 0 ] || die "chưa có app nào — menu [9] → Thêm app"
  choose "Bundle id:" "${labels[@]}"
  if [ "$CHOICE" -le ${#ids[@]} ]; then
    BUNDLE="${ids[$((CHOICE - 1))]}"
  else
    ask "Nhập bundle id (vd com.example.app)"
    BUNDLE="$REPLY"
  fi
}

is_registered() { reg list-bundles | cut -f1 | grep -qx "$1"; }

# Đảm bảo bundle đã đăng ký + có apps/<bundle>/ (hỏi trước khi tạo) + đã gán env
# (app chưa có env thì không vào manifest nào → [6] submitted/live vô tác dụng).
ensure_bundle() {
  local b="$1" e
  e="$(reg env-of "$b")"
  if ! is_registered "$b" || [ ! -f "$APPS_DIR/$b/app.yaml" ]; then
    yes_no "App $b chưa có trong registry / apps/. Tạo mới?" Y || die "dừng"
    if [ -z "$e" ]; then choose_env "App $b thuộc env nào?"; e="$SEL_ENV"; fi
    reg bundle-add "$b" --env "$e"
  elif [ -z "$e" ]; then
    # Không dùng bundle-add: app có sẵn → nó xoá trắng trường ký trong app.yaml.
    info "App $b chưa gán env (thiếu configs/apps/$b.json) — chưa vào manifest nào"
    choose_env "App $b thuộc env nào?"
    reg set-env "$b" "$SEL_ENV" || die "gán env thất bại"
  fi
}

# Chọn 1 env: choose_env <tiêu đề> → $SEL_ENV.
choose_env() {
  local l; local -a ids=() labels=()
  read_lines reg list-envs
  [ ${#LINES[@]} -gt 0 ] || die "chưa có env — tạo configs/deploy.json (mẫu: tools/README.md)"
  for l in "${LINES[@]}"; do
    IFS=$'\t' read -r e rs n _ <<< "$l"
    ids+=("$e"); labels+=("$e  ($rs — $n app)")
  done
  choose "${1:-Env:}" "${labels[@]}"
  SEL_ENV="${ids[$((CHOICE - 1))]}"
}

# Chọn nhiều env: choose_envs <tiêu đề> <mặc định csv> [env bỏ qua…] → $ENVS (csv).
choose_envs() {
  local title="$1" def="$2" l x n; shift 2
  local -a ids=()
  read_lines reg list-envs
  echo; echo "$title"
  for l in ${LINES[@]+"${LINES[@]}"}; do
    IFS=$'\t' read -r e rs _ _ <<< "$l"
    case " $* " in *" $e "*) continue ;; esac
    ids+=("$e"); printf '  [%d] %s  (%s)\n' "${#ids[@]}" "$e" "$rs"
  done
  [ ${#ids[@]} -gt 0 ] || die "không còn env nào để chọn"
  while true; do
    read -r -p "Chọn (vd 1 hoặc 1,2 — Enter = $def): " x || die "EOF — dừng"
    if [ -z "$x" ]; then ENVS="$def"; return 0; fi
    ENVS=""
    for n in $(echo "$x" | tr ',' ' '); do
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#ids[@]} ]; then
        ENVS="${ENVS:+$ENVS,}${ids[$((n - 1))]}"
      else ENVS=""; break; fi
    done
    [ -n "$ENVS" ] && return 0
    echo "  nhập số trong [1-${#ids[@]}], cách nhau dấu phẩy"
  done
}

choose_platform() {
  choose "Platform:" "iOS" "Android"
  if [ "$CHOICE" = 1 ]; then PLATFORM=ios; else PLATFORM=android; fi
}

# Chọn app (trong <env>) có bản <platform> live: pick_redirect <platform> <min_patch|-> <env> [exclude]
# → $REDIRECT (rỗng = bỏ trống). Dùng cho app thay thế chung ([8] → App thay thế chung).
pick_redirect() {
  local p="$1" mp="$2" env="$3" ex="${4:-}" l
  local -a args=(redirect-candidates "$p" --env "$env") ids=() labels=()
  [ "$mp" != "-" ] && args+=(--min-patch "$mp")
  [ -n "$ex" ] && args+=(--exclude "$ex")
  read_lines reg "${args[@]}"
  for l in ${LINES[@]+"${LINES[@]}"}; do
    ids+=("${l%%$'\t'*}"); labels+=("${l%%$'\t'*}  (${l##*$'\t'})")
  done
  labels+=("Bỏ trống (không có app thay thế)")
  choose "App thay thế cho $(echo "$p" | tr a-z A-Z):" "${labels[@]}"
  if [ "$CHOICE" -le ${#ids[@]} ]; then REDIRECT="${ids[$((CHOICE - 1))]}"; else REDIRECT=""; fi
}

# Sau mỗi bước ghi registry: hỏi deploy + commit.
# Chỉ hỏi deploy các env có manifest/config đổi (registry ghi dấu, deploy xong tự xoá).
# Deploy XONG (hoặc không có env cần deploy) → tự commit cho git khớp server.
# Deploy lỗi / hoãn → KHÔNG commit (git không ghi trạng thái server chưa có):
# lưu lời nhắn vào $PENDING_COMMIT, menu [2] deploy xong sẽ tự commit.
PENDING_COMMIT="$ROOT/dist/.dynpub_pending_commit"
after_write() {
  local msg="$1" e
  local -a args=()
  echo
  read_lines reg changed-envs
  for e in ${LINES[@]+"${LINES[@]}"}; do args+=(--env "$e"); done
  if [ ${#args[@]} -eq 0 ]; then
    info "manifest / config các env không đổi — không cần deploy"
  elif yes_no "Deploy env ${LINES[*]} lên rs_domain ngay?" Y; then
    if ! reg deploy "${args[@]}"; then
      echo "  [dynpub] deploy chưa xong — sửa rồi chạy menu [2] (tool vẫn nhớ env cần deploy)"
      defer_commit "$msg"; return 0
    fi
  else
    info "chưa deploy ${LINES[*]} — menu [2] khi sẵn sàng"
    defer_commit "$msg"; return 0
  fi
  do_commit "$msg"
}

defer_commit() {
  mkdir -p "$(dirname "$PENDING_COMMIT")" && echo "$1" >>"$PENDING_COMMIT"
  info "CHƯA commit (server chưa nhận) — deploy xong ở menu [2] sẽ tự commit"
}

# Commit registry/ + publish/ + configs/ (không hỏi); xong thì xoá lời nhắn đang chờ.
do_commit() {
  local msg="$1"
  (cd "$ROOT" && git add -A registry publish configs/apps configs/deploy.json apps 2>/dev/null || true
   if git diff --cached --quiet; then info "không có thay đổi để commit"
   else git commit -q -m "dynpub: $msg" && info "đã commit: dynpub: $msg"; fi) || return 1
  rm -f "$PENDING_COMMIT"
}

# Sau build host: CHỈ commit thông tin bản build (registry/hosts|abis|bundles|compat
# + configs/apps/<b>.json + ngày unlock trong loading_kit),
# không hỏi deploy — bản build chưa lên store nên manifest không đổi. Chỉ commit
# đúng các file này (thay đổi khác trong repo giữ nguyên).
commit_build() {
  local b="$1" msg="$2"
  local -a paths=(registry/hosts/"$b".json registry/abis registry/bundles.json registry/compat.json
                  "$UNLOCK_SRC")
  # config app vừa gán env lúc build (ensure_bundle) — commit cùng bản build
  [ -f "$ROOT/configs/apps/$b.json" ] && paths+=(configs/apps/"$b".json)
  (cd "$ROOT" && git add -- "${paths[@]}" 2>/dev/null || true
   if git diff --cached --quiet -- "${paths[@]}"; then info "registry không đổi — không có gì để commit"
   else git commit -q -m "dynpub: $msg" -- "${paths[@]}" && info "đã commit: dynpub: $msg"; fi)
}

# Flutter DÙNG: ../engine/flutter-framework (gom 1 chỗ), chưa có thì checkout build.
engine_ff() {
  if [ -n "${DYNMOD_FF:-}" ]; then echo "$DYNMOD_FF"; return; fi
  local e="$(dirname "$ROOT")/engine/flutter-framework"
  if [ -x "$e/bin/flutter" ]; then echo "$e"; else echo "$(dirname "$ROOT")/dart-sdk-build/flutter-framework"; fi
}
# Engine DÙNG cho --local-engine-src-path: ưu tiên ../engine (bản chép gọn — dynmod.sh backup)
engine_src() {
  if [ -n "${DYNMOD_ENGINE_SRC:-}" ]; then echo "$DYNMOD_ENGINE_SRC"
  elif [ -d "$(dirname "$ROOT")/engine/out" ]; then echo "$(dirname "$ROOT")/engine"
  else echo "$(engine_ff)/engine/src"; fi
}

# Sinh ban dynamic_interface CHO HOST BUILD: gỡ entry `dynamically-callable` trỏ
# library KHÔNG có trong host program (giữ = annotator crash "has not been
# indexed" → kernel_snapshot_program failed). Bản đầy đủ vẫn dùng cho
# `dart2bytecode --validate` lúc compile module. Xem:
# tools/cmd/dyniface/gen_host_iface.py
host_iface() {
  local src="$1" out="$ROOT/dist/dynamic_interface.host.yaml"
  # report của python → stderr để `$(host_iface ...)` chỉ captures đường dẫn
  python3 "$ROOT/tools/cmd/dyniface/gen_host_iface.py" --src "$src" --out "$out" >&2 \
    || { echo "LỖI: sinh dynamic_interface.host.yaml thất bại" >&2; return 1; }
  echo "$out"
}

# Đóng băng hợp đồng host ngay trước khi build host ddm: build lại anchor
# từ app/main.dart + sinh lại dist/dynamic_interface.yaml. Module sau này
# compile đúng cặp anchor/iface này (P4).
#
# Release registry: host lệch configs/abi/module_abi.json KHÔNG còn chặn build —
# mỗi bản build có ABI riêng, registry tự tính bản build chạy được tới patch
# nào. module_abi.json chỉ còn là mốc tham chiếu cho check.sh (app_package vs
# host compile) → chụp lại theo host vừa build.
freeze_iface() {
  # bootstrap tự áp modules/ vào ../app_package trước khi sinh iface.
  info "đóng băng hợp đồng host: build lại anchor + interface…"
  bash "$T/dyniface.sh" bootstrap || die "build anchor/interface thất bại"
  # DYNMOD_IFACE_HASH qua --dart-define: cache build flutter/gradle KHÔNG coi
  # NỘI DUNG file --dynamic-interface là input (cùng đường dẫn) → iface đổi mà
  # Dart không đổi sẽ giữ libapp.so CŨ. dart-define nằm trong khoá cache →
  # buộc build lại.
  if [ ! -f "$ROOT/configs/abi/module_abi.json" ] || ! bash "$T/abicheck.sh" host >/dev/null 2>&1; then
    info "ABI host khác mốc tham chiếu → bản build này có ABI riêng (registry tự tính patch chạy được)"
    bash "$T/abicheck.sh" snapshot >/dev/null || die "chụp ABI thất bại"
  fi
  IFACE_HASH="$(shasum -a 256 "$ROOT/dist/dynamic_interface.yaml" | cut -d' ' -f1)"
  HOST_DEFINES=(--dart-define=DYNMOD_IFACE_HASH="$IFACE_HASH")
  info "iface ${IFACE_HASH:0:16}…"
}

# "1.0.4+7" → VN_NAME=1.0.4 VN_NUM=7 (thiếu "+n" → VN_NUM=1).
split_version() {
  VN_NAME="${1%%+*}"
  if [ "$VN_NAME" = "$1" ]; then VN_NUM=1; else VN_NUM="${1##*+}"; fi
}

# ── builds ───────────────────────────────────────────────────────────────────
# APK Android: $1=version $2=release-ddm|debug → set $FILE
build_apk() {
  local ver="$1" mode="$2"
  local FF
  FF="$(engine_ff)"
  [ -x "$FF/bin/flutter" ] \
    || die "không thấy $FF/bin/flutter (engine ddm chưa build? bash tools/cmd/dynmod.sh engine)"
  split_version "$ver"
  if [ "$mode" = "release-ddm" ]; then
    freeze_iface
    local IFACE="$ROOT/dist/dynamic_interface.yaml"
    [ -f "$IFACE" ] || die "thiếu $IFACE sau bootstrap"
    local IFACE_HOST; IFACE_HOST="$(host_iface "$IFACE")" \
      || die "sinh dynamic_interface.host.yaml thất bại"
    info "build APK release bằng engine ddm (module OTA hoạt động)…"
    (cd "$ROOT/app" && "$FF/bin/flutter" build apk --release \
      --local-engine-src-path "$(engine_src)" \
      --local-engine=android_release_arm64 \
      --local-engine-host=host_release_arm64 \
      --extra-front-end-options="--dynamic-interface=$IFACE_HOST" \
      "${HOST_DEFINES[@]}" \
      --build-name="$VN_NAME" --build-number="$VN_NUM") || die "build APK release thất bại"
    FILE="$ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
  else
    info "build APK debug (engine stock — module sẽ fail-open về app gốc, đúng hành vi máy dev)…"
    (cd "$ROOT/app" && "$FF/bin/flutter" build apk --debug \
      --build-name="$VN_NAME" --build-number="$VN_NUM") || die "build APK debug thất bại"
    FILE="$ROOT/app/build/app/outputs/flutter-apk/app-debug.apk"
  fi
  [ -f "$FILE" ] || die "không thấy $FILE"
  info "APK: $FILE ($(stat -f%z "$FILE") bytes)"
}

# rive_native tải lib native iOS 1 lần / pub-cache (đánh dấu bằng marker). Script
# trong podspec của nó tự chạy setup nhưng với cwd = ios/Pods (không có
# pubspec.yaml) → archive fail trên máy chưa setup. Chạy trước từ app/.
rive_setup_ios() {
  local FF="$1" dir
  dir="$(python3 -c '
import json, sys
from urllib.parse import unquote, urlparse
for p in json.load(open(sys.argv[1]))["packages"]:
    if p["name"] == "rive_native":
        print(unquote(urlparse(p["rootUri"]).path))
' "$ROOT/app/.dart_tool/package_config.json" 2>/dev/null)" || return 0
  [ -n "$dir" ] || return 0
  [ -f "$dir/ios/rive_marker_ios_setup_complete" ] && return 0
  info "rive_native chưa setup iOS trên máy này → dart run rive_native:setup…"
  (cd "$ROOT/app" && "$FF/bin/dart" run rive_native:setup --verbose --platform ios) \
    || die "rive_native setup iOS thất bại"
  lock_verify
}

# IPA iOS: $1=debug|profile|adhoc|appstore $2=version $3=export plist (adhoc/appstore) → set $FILE
#   debug/profile : engine stock → module fail-open (dev/test flow).
#   adhoc/appstore: engine ddm (ios_release) + dynamic-interface → module OTA.
#   appstore ký Automatic (không có profile Development trên máy): archive Automatic
#   luôn ký Development → Apple đòi team có device → chỉ archive KHÔNG ký
#   ($FILE = .xcarchive), người dùng tự Distribute trong Xcode Organizer.
build_ipa() {
  local mode="$1" ver="$2" plist="${3:-}"
  local FF IFACE
  FF="$(engine_ff)"
  split_version "$ver"
  local -a mode_args engine_args=()
  local -a export_args=()
  local archive_only=0
  if [ "$mode" = appstore ] && grep -q '^APP_SIGN_STYLE = Automatic' "$XCCONFIG_OUT" 2>/dev/null; then
    archive_only=1
  fi
  case "$mode" in
    debug)   mode_args=(--debug --export-method development --dart-define=DYNMOD_ENABLE=false) ;;
    profile) mode_args=(--profile --export-method development --dart-define=DYNMOD_ENABLE=false) ;;
    # Export options sinh theo app.yaml (profile Ad Hoc / App Store của
    # đúng bundle). KHÔNG dùng --export-method song song — flutter từ chối.
    adhoc|appstore)
      mode_args=(--release --dart-define=DYNMOD_ENABLE=true)
      [ -f "$plist" ] || die "thiếu export options plist cho $mode"
      if [ "$archive_only" = 1 ]; then
        export_args=(--no-codesign)
      else
        export_args=(--export-options-plist="$plist")
      fi ;;
    *) die "build_ipa mode lạ: $mode" ;;
  esac
  case "$mode" in
    adhoc|appstore)
      [ -x "$FF/bin/flutter" ] || die "không thấy $FF/bin/flutter (engine ddm chưa build?)"
      freeze_iface
      IFACE="$ROOT/dist/dynamic_interface.yaml"
      [ -f "$IFACE" ] || die "thiếu $IFACE sau bootstrap"
      local IFACE_HOST; IFACE_HOST="$(host_iface "$IFACE")" \
        || die "sinh dynamic_interface.host.yaml thất bại"
      engine_args=(
        "--local-engine-src-path=$(engine_src)"
        "--local-engine=ios_release"
        "--local-engine-host=host_release_arm64"
        "--extra-front-end-options=--dynamic-interface=$IFACE_HOST"
        "${HOST_DEFINES[@]}"
      ) ;;
  esac

  rive_setup_ios "$FF"
  info "build ipa mode=${mode}…"
  (cd "$ROOT/app" && "$FF/bin/flutter" build ipa "${mode_args[@]}" \
    ${export_args[@]+"${export_args[@]}"} \
    --build-name="$VN_NAME" --build-number="$VN_NUM" \
    ${engine_args[@]+"${engine_args[@]}"}) \
    || die "build ipa thất bại (kiểm tra signing / profile trong apps/<bundle>/app.yaml)"
  if [ "$archive_only" = 1 ]; then
    FILE="$ROOT/app/build/ios/archive/Runner.xcarchive"
    [ -d "$FILE" ] || die "không thấy $FILE"
    info "không có profile Development trên máy → chỉ archive (chưa ký): $FILE"
    return
  fi
  FILE="$(ls -t "$ROOT"/app/build/ios/ipa/*.ipa 2>/dev/null | head -1)"
  [ -n "$FILE" ] || die "không thấy .ipa trong app/build/ios/ipa"
  info "IPA: $FILE ($(stat -f%z "$FILE") bytes)"
}

# ── chặn lệch Flutter / lock (CLAUDE.md §1) ─────────────────────────────────
# Flutter dùng phải đúng configs/flutter.json (cùng commit).
check_flutter() {
  local ff want have
  ff="$(engine_ff)"
  [ -x "$ff/bin/flutter" ] || die "không thấy $ff/bin/flutter — chạy: bash tools/setup.sh"
  want="$(bash "$T/flutter_version.sh" --commit 2>/dev/null || true)"
  have="$(git -C "$ff" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    die "Flutter $ff ở ${have:0:10}, configs/flutter.json cần ${want:0:10} — chạy: bash tools/setup.sh"
  fi
}

LOCK_TRACKED=0
git -C "$ROOT" cat-file -e HEAD:app/pubspec.lock 2>/dev/null && LOCK_TRACKED=1
# Trước khi xuất main_app: lock hiện tại không được trôi version (thay đổi cố ý
# phải commit trước) → đưa về lock tham chiếu để app nào cũng resolve từ cùng mốc.
lock_reset() {
  [ "$LOCK_TRACKED" = 1 ] || { info "app/pubspec.lock chưa commit — bỏ qua kiểm lock (nên commit)"; return 0; }
  python3 -B "$T/lockcheck.py" >/dev/null || {
    python3 -B "$T/lockcheck.py" || true
    die "app/pubspec.lock đang đổi version so với bản commit — cố ý thì commit trước, không thì: git checkout -- app/pubspec.lock"
  }
  git -C "$ROOT" checkout -- app/pubspec.lock
}
# Sau pub get với main_app của app: chỉ được THÊM package, không đổi version.
lock_verify() {
  [ "$LOCK_TRACKED" = 1 ] || return 0
  python3 -B "$T/lockcheck.py" || die "pubspec.lock trôi version sau pub get — dừng (không build trên lock lệch)"
}

# ── danh tính app: áp trước build, gỡ sau build (kể cả build lỗi) ─────────────
ICON_BACKUP="$ROOT/.dynpub_icon_backup"
XCCONFIG_OUT="$ROOT/app/ios/Flutter/AppIdentity.xcconfig"
UNLOCK_SRC=loading_kit/loading_kit/lib/flow/boot_config.dart
UNLOCK_PREV=""   # ngày unlock trước khi build — build lỗi / không đăng ký thì trả lại
cleanup_identity() {
  idt icons-restore "$ICON_BACKUP" >/dev/null 2>&1 || true
  if [ -n "$UNLOCK_PREV" ]; then
    python3 -B "$T/unlockdate.py" set "$UNLOCK_PREV" >/dev/null 2>&1 || true
    UNLOCK_PREV=""
  fi
  rm -f "$XCCONFIG_OUT"
  # Lock về bản tham chiếu (package riêng của app vừa build không ở lại).
  [ "$LOCK_TRACKED" = 1 ] && git -C "$ROOT" checkout -- app/pubspec.lock 2>/dev/null || true
}
# Lần chạy trước bị ngắt giữa chừng → khôi phục icon/xcconfig ngay khi mở tool.
[ -d "$ICON_BACKUP" ] && cleanup_identity

# Xuất main_app của app → ../main_app_package, pub get lại host, áp env/xcconfig/icon.
apply_identity() {
  local b="$1" p="$2"
  idt check "$b" || die "apps/$b chưa đủ để build — sửa theo [FAIL] ở trên"
  python3 -B "$T/gentexts.py" --check \
    || die "text host chưa khớp nguồn — chạy: python3 tools/cmd/gentexts.py (rồi commit)"
  check_flutter
  eval "$(idt env "$b")"
  lock_reset
  trap cleanup_identity EXIT
  info "xuất main_app của ${b}…"
  bash "$T/build_main_app.sh" --src "$APP_MAIN_APP_SRC" --no-verify \
    || die "xuất main_app thất bại"
  bash "$T/dynmod.sh" pubget || die "pub get host thất bại"
  lock_verify
  if [ "$p" = android ] && [ -n "${APP_KEYSTORE:-}" ]; then
    [ -n "${APP_KEYSTORE_PASSWORD:-}" ] || { read -r -s -p "Mật khẩu keystore $APP_KEYSTORE: " APP_KEYSTORE_PASSWORD; echo; }
    [ -n "${APP_KEY_PASSWORD:-}" ] || APP_KEY_PASSWORD="$APP_KEYSTORE_PASSWORD"
    export APP_KEYSTORE_PASSWORD APP_KEY_PASSWORD
  fi
  if [ "$p" = ios ]; then
    idt ios-check "$b" || die "thiếu team/profile iOS cho $b — xem LỖI ở trên"
    idt xcconfig "$b" "$XCCONFIG_OUT"
  fi
  idt icons-apply "$b" "$ICON_BACKUP"
}

# build_host <bundle> <platform> <version> <mode> [unlock — rỗng = giữ ngày trong code]
build_host() {
  local b="$1" p="$2" ver="$3" m="$4" unlock="${5:-}" plist="" reg_mode=""
  apply_identity "$b" "$p"
  UNLOCK_PREV="$(python3 -B "$T/unlockdate.py" show)" || die "không đọc được ngày unlock trong loading_kit"
  if [ -n "$unlock" ]; then
    unlock="$(python3 -B "$T/unlockdate.py" set "$unlock")" || die "ngày unlock lạ: $unlock"
  else
    unlock="$UNLOCK_PREV"
    info "giữ ngày unlock trong code: $unlock"
  fi
  if [ "$p" = android ]; then
    case "$m" in
      ddm|release) build_apk "$ver" release-ddm; reg_mode=ddm ;;
      debug)       build_apk "$ver" debug ;;
      *) die "mode android lạ: $m (dùng: ddm|debug)" ;;
    esac
  else
    case "$m" in
      adhoc|appstore)
        plist="$(mktemp -t dynpub_export).plist"
        idt xcconfig "$b" "$XCCONFIG_OUT" "$m"
        idt export-plist "$b" "$m" "$plist"
        build_ipa "$m" "$ver" "$plist"; reg_mode="$m" ;;
      debug|profile) build_ipa "$m" "$ver" ;;
      *) die "mode ios lạ: $m (dùng: adhoc|appstore|debug|profile)" ;;
    esac
  fi
  # bản đăng ký registry giữ ngày unlock mới (commit cùng bản build); debug/profile trả lại
  if [ -n "$reg_mode" ]; then UNLOCK_PREV=""; fi
  cleanup_identity
  trap - EXIT
  split_version "$ver"
  local out="$ROOT/dist/builds"
  mkdir -p "$out"
  local dst="$out/${b}_${p}_${VN_NAME}+${VN_NUM}.${FILE##*.}"
  rm -rf "$dst"
  cp -R "$FILE" "$dst"
  info "bản build: $dst"
  if [ "${FILE##*.}" = xcarchive ]; then
    open "$dst" || true
    info "đã mở archive trong Xcode Organizer → Distribute App → App Store Connect (Xcode ký Automatic bằng tài khoản đã đăng nhập)"
  fi
  if [ -n "$reg_mode" ]; then
    reg register-host --bundle "$b" --platform "$p" --version-name "$VN_NAME" \
      --version-code "$VN_NUM" --mode "$reg_mode" --unlock-date "$unlock" \
      || die "đăng ký registry thất bại (bản build vẫn ở $dst)"
    commit_build "$b" "build $b $p $VN_NAME+$VN_NUM, unlock $unlock"
    info "ngày unlock: $unlock (loading_kit + registry/hosts/$b.json)"
    echo
    info "bản build CHƯA vào manifest (chưa lên store) → máy cài bản này chạy không patch (fail-open)."
    info "Lên store / phát cho tester: máy có VPN → menu [6] (submitted / live) → deploy"
  else
    info "build engine stock — không đăng ký registry"
  fi
}

# ── menu ─────────────────────────────────────────────────────────────────────
menu_build() {
  pick_bundle 1
  ensure_bundle "$BUNDLE"
  choose_platform
  local ver m
  if [ "$PLATFORM" = android ]; then
    choose "Kiểu build:" \
      "Release engine ddm (KHUYẾN NGHỊ — module OTA, đăng ký registry)" \
      "Debug engine stock (module fail-open, không đăng ký)"
    m=$([ "$CHOICE" = 1 ] && echo ddm || echo debug)
  else
    choose "Kiểu build:" \
      "Ad-hoc RELEASE (engine ddm — module OTA, đăng ký registry)" \
      "App Store (engine ddm — module OTA, đăng ký registry)" \
      "Debug (engine stock, không đăng ký)" \
      "Profile (engine stock, không đăng ký)"
    case "$CHOICE" in 1) m=adhoc ;; 2) m=appstore ;; 3) m=debug ;; 4) m=profile ;; esac
  fi
  ask_unlock
  # Mỗi lần build tự tăng version_code (kể cả debug / không lên store).
  ver="$(reg reserve-version "$BUNDLE")" || die "không lấy được version"
  info "version: $ver (tự tăng — build lỗi thì số này bỏ qua, lần sau lấy số mới)"
  build_host "$BUNDLE" "$PLATFORM" "$ver" "$m" "$UNLOCK_DATE"
}

# Patch luôn compile với host THAM CHIẾU (apps/_reference/main_app) để kết quả không phụ
# thuộc app nào vừa build trước đó (main_app khác có thể kéo version package
# host khác → requires lệch).
do_patch() {
  local mfu="${1:-0}" envs="${2:-}"
  echo
  echo "\$ bash tools/cmd/modprep.sh apply"
  bash "$T/modprep.sh" apply || die "modprep apply thất bại — xử lý [FAIL] ở trên rồi chạy lại (FAIL vì app_package đòi version package host khác → menu [11])"
  check_flutter
  info "host tham chiếu: xuất apps/_reference/main_app + pub get + build lại anchor/interface…"
  lock_reset
  bash "$T/build_main_app.sh" --no-verify || die "xuất apps/_reference/main_app thất bại"
  bash "$T/dynmod.sh" pubget || die "pub get host thất bại"
  lock_verify
  bash "$T/dyniface.sh" bootstrap || die "build anchor/interface thất bại"
  echo
  echo "\$ bash tools/cmd/dyniface.sh compile"
  bash "$T/dyniface.sh" compile || die "compile module thất bại — xem log dyniface-loop-*.log (bash tools/cmd/dyniface.sh status)"
  local bc
  bc="$(ls -t "$ROOT"/dist/app_content_*.bytecode 2>/dev/null | head -1 || true)"
  [ -n "$bc" ] || die "compile xong nhưng không thấy dist/app_content_<hash8>.bytecode"
  if [ -z "$envs" ]; then
    choose_envs "Patch $(basename "$bc") xong — đưa lên env nào? (sau này đưa thêm: menu [4])" staging
    envs="$ENVS"
  fi
  reg register-patch --bytecode "$bc" --envs "$envs" --min-force-update "$mfu" || die "đăng ký patch thất bại"
}

menu_patch() {
  do_patch 0
  after_write "patch"
}

# app_package (s88) đòi version package host khác (vd shared_preferences ^2.5.6):
# [1] dừng ở modprep check, [5] dừng ở lock_verify. Option này nhận version mới
# làm mốc host: pub get → lock đổi → xác nhận → anchor/iface → chụp mốc → commit.
# Sau đó [5] build lại app (ABI mới) → [1] ra patch.
menu_host_pkg() {
  check_flutter
  lock_reset
  echo
  echo "\$ bash tools/cmd/modprep.sh apply   (FAIL ràng buộc version ở đây là bình thường)"
  bash "$T/modprep.sh" apply || true
  info "host tham chiếu + pub get theo ràng buộc mới của app_package…"
  bash "$T/build_main_app.sh" --no-verify || die "xuất apps/_reference/main_app thất bại"
  bash "$T/dynmod.sh" pubget || die "pub get host thất bại"
  echo
  if python3 -B "$T/lockcheck.py"; then
    # Lock không đổi nhưng ràng buộc app_package có thể đổi mà host cũ vẫn
    # thoả (vd ^2.2.0 → ^2.5.0, host 2.5.5) → chỉ cần nhận mốc ràng buộc.
    local out
    # exit 2 = chỉ ràng buộc đổi so với mốc (đúng việc option này nhận); 1 = vi phạm ABI.
    local rc=0
    out="$(bash "$T/abicheck.sh" app-package 2>&1)" || rc=$?
    [ "$rc" = 1 ] && { echo "$out"; die "app_package còn vi phạm ABI host — xem [FAIL] ở trên"; }
    if ! grep -q "ĐỔI so với mốc" <<<"$out"; then
      info "không package host nào đổi version, ràng buộc không đổi — không có gì để nhận"
      return 0
    fi
    echo "$out"
    info "host không đổi version (ABI giữ nguyên) — chỉ ghi lại mốc ràng buộc"
    yes_no "Nhận ràng buộc mới làm mốc?" Y || { info "huỷ"; return 0; }
    bash "$T/abicheck.sh" app-package --accept >/dev/null || die "ghi mốc ràng buộc thất bại"
    (cd "$ROOT" && git add configs/abi/app_package_deps.json \
       && git commit -q -m "dynpub: nhận mốc ràng buộc app_package" -- configs/abi/app_package_deps.json \
       && info "đã commit: dynpub: nhận mốc ràng buộc app_package")
    return 0
  fi
  echo
  info "nhận = ĐỔI ABI host: bản build cũ dừng ở patch hiện tại; patch mới chỉ chạy trên bản build lại"
  if ! yes_no "Nhận version mới ở trên làm mốc host?" N; then
    git -C "$ROOT" checkout -- app/pubspec.lock
    bash "$T/dynmod.sh" pubget >/dev/null || true
    info "huỷ — lock về bản commit"
    return 0
  fi
  info "cập nhật host_packages.yaml theo lock mới…"
  bash "$T/dyniface.sh" packages --write || die "cập nhật host_packages.yaml thất bại"
  bash "$T/dyniface.sh" bootstrap || die "build anchor/interface thất bại"
  bash "$ROOT/tools/snapshot.sh" -y || die "chụp mốc thất bại — xem [FAIL] ở trên (lock CHƯA commit)"
  (cd "$ROOT" && git add app/pubspec.lock configs/abi/module_abi.json configs/abi/app_package_deps.json configs/abi/host_packages.yaml \
     && git commit -q -m "dynpub: đổi package host (ABI mới)" \
       -- app/pubspec.lock configs/abi/module_abi.json configs/abi/app_package_deps.json \
     && info "đã commit: dynpub: đổi package host (ABI mới)")
  echo
  info "tiếp: [5] build lại các app còn cập nhật → [6] live → [1] ra patch → deploy"
  info "máy chạy bản build cũ dừng ở patch hiện tại (ép lên store: [8] → Cấm patch cũ)"
}

# Ép popup restart tách khỏi [1]: lúc ra patch chưa biết thay đổi lớn hay nhỏ.
menu_force_restart() {
  read_lines reg list-patches
  local -a ids=() labels=() l
  for l in ${LINES[@]+"${LINES[@]}"}; do
    IFS=$'\t' read -r v st at envs mfu <<< "$l"
    [ "$st" = active ] || continue
    ids+=("$v")
    labels+=("v$v  (env $envs — $at) — ép restart: $([ "${mfu:-0}" -gt 0 ] && echo "máy < v$mfu" || echo "tắt")")
  done
  [ ${#ids[@]} -gt 0 ] || die "không có patch nào đang active"
  choose "Patch nào? (chỉ có tác dụng khi patch này là bản đích máy sẽ tải)" "${labels[@]}"
  local v="${ids[$((CHOICE - 1))]}"
  info "máy đang chạy patch NHỎ HƠN số nhập vào, khi tải xong v$v sẽ hiện popup khởi động lại"
  info "$v = mọi máy chưa có v$v; 0 = tắt (bản mới tự áp ở lần mở app sau)"
  ask "min_force_update của v$v" "$v"
  local m="$REPLY"
  [[ "$m" =~ ^[0-9]+$ ]] || die "cần số nguyên: $m"
  reg patch-force "$v" "$m" || return 1
  after_write "patch v$v min_force_update=$m"
}

menu_store() {
  pick_bundle 0
  read_lines reg list-builds "$BUNDLE"
  [ ${#LINES[@]} -gt 0 ] || die "$BUNDLE chưa có bản build nào trong registry"
  local -a labels=() l
  for l in "${LINES[@]}"; do
    IFS=$'\t' read -r _ p vc name st _ <<< "$l"
    labels+=("$p vc$vc ($name) — đang: $st")
  done
  choose "Bản build:" "${labels[@]}"
  IFS=$'\t' read -r _ p vc _ _ _ <<< "${LINES[$((CHOICE - 1))]}"
  choose "Trạng thái store mới:" "built (chưa nộp — bỏ khỏi registry/store, không vào manifest)" \
    "submitted (đã nộp, chờ duyệt — vào manifest)" "live (đang trên store)" \
    "removed (đã gỡ / bị gỡ khỏi store — vẫn giữ trong manifest cho máy đã cài)" \
    "rejected (store từ chối — chỉ từ submitted; bỏ khỏi manifest, bản trước giữ nguyên)"
  local st; case "$CHOICE" in 1) st=built ;; 2) st=submitted ;; 3) st=live ;; 4) st=removed ;; 5) st=rejected ;; esac
  reg store "$BUNDLE" "$p" "$vc" "$st" || return 1
  after_write "store $BUNDLE $p vc$vc $st"
}

menu_app() {
  pick_bundle 1
  if ! is_registered "$BUNDLE" || [ ! -f "$APPS_DIR/$BUNDLE/app.yaml" ]; then
    ensure_bundle "$BUNDLE"
    info "sửa apps/$BUNDLE/app.yaml (tên, icon, ký) + configs/apps/$BUNDLE.json (api_domain) — rs_domain theo env, tool tự ghi"
    after_write "add app $BUNDLE"
    return 0
  fi
  local cur_env; cur_env="$(reg env-of "$BUNDLE")"
  choose "$BUNDLE (env ${cur_env:-chưa gán}) — làm gì:" \
    "Đánh dấu app ĐÃ CHẾT (bị gỡ khỏi store / không cập nhật được nữa)" \
    "App sống lại (bỏ đánh dấu chết)" \
    "Khai Apple ID của app iOS (khi tool không tự tìm ra)" \
    "Đổi env của app (staging / pre / prod)"
  case "$CHOICE" in
    1)
      if [ "$cur_env" = prod ]; then
        info "user của $BUNDLE sẽ được mời sang app thay thế chung (menu [8] → App thay thế chung)"
      else
        info "$BUNDLE ở env ${cur_env:-?} — chỉ prod có app thay thế chung, user sẽ KHÔNG được mời sang app khác"
      fi
      yes_no "Đánh dấu $BUNDLE đã chết?" N || { info "huỷ"; return 0; }
      reg bundle-retire "$BUNDLE" || return 1
      after_write "app chết $BUNDLE" ;;
    2)
      reg bundle-activate "$BUNDLE" || return 1
      after_write "app sống lại $BUNDLE" ;;
    3)
      ask "Apple ID (số, trong link apps.apple.com/app/id<SỐ>)"
      reg ios-app-id "$BUNDLE" "$REPLY" || return 1
      after_write "ios-app-id $BUNDLE" ;;
    4)
      choose_env "Chuyển $BUNDLE (đang ${cur_env:-chưa gán}) sang env:"
      [ "$SEL_ENV" != "$cur_env" ] || { info "đã ở env $SEL_ENV"; return 0; }
      info "máy đang cài $BUNDLE sẽ đọc manifest của env $SEL_ENV sau khi deploy (deploy xong chép config sang ../configs — bạn tự commit + push lên GitHub)"
      yes_no "Chuyển $BUNDLE sang $SEL_ENV?" N || { info "huỷ"; return 0; }
      reg set-env "$BUNDLE" "$SEL_ENV" || return 1
      after_write "env $BUNDLE → $SEL_ENV" ;;
  esac
}

# Mọi kiểu ép (popup store không đóng được / popup restart) gom 1 chỗ.
menu_force() {
  choose "Ép cập nhật / ép restart:" \
    "Bắt cập nhật app theo số build (version_code) — lỗi ở app, không liên quan patch" \
    "Cấm patch cũ (block-below) — theo env" \
    "Ép restart máy chạy patch cũ (min_force_update)" \
    "App thay thế chung (prod) — cho app chết / app bị ép"
  case "$CHOICE" in
    1) menu_force_vc ;;
    2) menu_block ;;
    3) menu_force_restart ;;
    4) menu_replacement ;;
  esac
}

menu_force_vc() {
  pick_bundle 0
  is_registered "$BUNDLE" || die "$BUNDLE chưa đăng ký — menu [9] → Thêm app"
  choose_platform
  ask "Bắt cập nhật mọi bản build $PLATFORM có version_code NHỎ HƠN (0 = bỏ)" "0"
  local below="$REPLY"
  [ "$below" != 0 ] && info "mở store của chính $BUNDLE nếu đã có bản live >= $below; không thì app thay thế chung (prod)"
  reg force-vc "$BUNDLE" "$PLATFORM" "$below" || return 1
  after_write "bắt cập nhật $BUNDLE $PLATFORM <$below"
}

menu_block() {
  choose_env "Cấm patch cũ cho env nào?"
  local env="$SEL_ENV"
  echo
  reg list-patches | awk -F'\t' -v e="$env" '$4 == "*" || index("," $4 ",", "," e ",") {printf "  v%s  %s\n", $1, $2}' | tail -15
  ask "[$env] Cấm chơi patch NHỎ HƠN"
  local n="$REPLY"
  info "máy bị cấm: mở store của chính app nếu đã có bản live chạy được >= v$n; không thì app thay thế chung (prod, menu [8] → App thay thế chung)"
  echo
  echo "== Xem trước (chưa ghi) =="
  if ! reg block-below "$n" --env "$env" --dry-run; then
    echo; info "validator chặn — lên store bản mới đủ ngưỡng, hoặc đặt app thay thế chung ([8] → App thay thế chung)"; return 1
  fi
  yes_no "Áp dụng: [$env] cấm patch < v$n?" N || { info "huỷ"; return 0; }
  reg block-below "$n" --env "$env" >/dev/null || return 1
  after_write "block-below $env $n"
}

# App thay thế CHUNG (chỉ prod), mỗi platform 1 app: app chết → mời sang;
# app bị ép (cấm patch cũ / bắt cập nhật) mà store không có bản cao hơn → ép sang.
menu_replacement() {
  local a i
  info "app thay thế chung chỉ áp cho env prod — chọn app prod đang có bản live"
  pick_redirect android - prod; a="$REDIRECT"
  pick_redirect ios - prod; i="$REDIRECT"
  reg replacement-app --android "${a:-none}" --ios "${i:-none}" || return 1
  after_write "app thay thế chung android→${a:-none} ios→${i:-none}"
}

menu_retract() {
  read_lines reg list-patches
  local -a ids=() labels=() l
  for l in ${LINES[@]+"${LINES[@]}"}; do
    IFS=$'\t' read -r v st at envs _ <<< "$l"
    [ "$st" = active ] || continue
    ids+=("$v"); labels+=("v$v  ($at, env $envs)")
  done
  [ ${#ids[@]} -gt 0 ] || die "không có patch nào đang active"
  choose "Rút patch nào — khỏi MỌI env (máy CHƯA tải sẽ dừng ở bản trước; máy đã tải giữ nguyên):" "${labels[@]}"
  local v="${ids[$((CHOICE - 1))]}"
  yes_no "Rút v$v?" N || { info "huỷ"; return 0; }
  reg retract "$v" || return 1
  after_write "retract v$v"
}

menu_plan() {
  choose "Xem:" "Tất cả env" "1 env" "1 app"
  case "$CHOICE" in
    1) reg plan || true ;;
    2) choose_env; reg plan --env "$SEL_ENV" || true ;;
    3) pick_bundle 0; reg plan --bundle "$BUNDLE" || true ;;
  esac
}

menu_deploy() {
  local -a args=() opts=() pending=() l
  read_lines reg changed-envs
  pending=(${LINES[@]+"${LINES[@]}"})
  [ ${#pending[@]} -gt 0 ] && opts+=("Env có thay đổi chưa deploy: ${pending[*]}")
  opts+=("Tất cả env" "1 env" "1 app (manifest env của app + chép config của app)")
  choose "Deploy gì?" "${opts[@]}"
  [ ${#pending[@]} -gt 0 ] || CHOICE=$((CHOICE + 1))
  case "$CHOICE" in
    1) for l in "${pending[@]}"; do args+=(--env "$l"); done ;;
    2) ;;
    3) choose_env; args=(--env "$SEL_ENV") ;;
    4) pick_bundle 0; args=(--bundle "$BUNDLE") ;;
  esac
  if yes_no "Chạy thử (dry-run) trước?" N; then
    reg deploy "${args[@]+"${args[@]}"}" --dry-run || return 1
    yes_no "Deploy thật?" Y || { info "huỷ"; return 0; }
  fi
  reg deploy "${args[@]+"${args[@]}"}" || return 1
  # Thay đổi đã lên server → tự commit các bước bị hoãn (deploy lỗi / chưa deploy)
  if [ -s "$PENDING_COMMIT" ]; then
    echo; info "thay đổi chờ commit:"; sed 's/^/    - /' "$PENDING_COMMIT"
    read_lines reg changed-envs
    [ ${#LINES[@]} -gt 0 ] && info "lưu ý: còn env chưa deploy: ${LINES[*]}"
    do_commit "$(paste -sd ';' "$PENDING_COMMIT" | sed 's/;/; /g')"
  fi
}

menu_promote() {
  read_lines reg list-patches
  local -a ids=() labels=() cur=() l
  for l in ${LINES[@]+"${LINES[@]}"}; do
    IFS=$'\t' read -r v st at envs _ <<< "$l"
    [ "$st" = active ] || continue
    ids+=("$v"); cur+=("$envs"); labels+=("v$v  (đang ở: $envs — $at)")
  done
  [ ${#ids[@]} -gt 0 ] || die "không có patch nào đang active"
  choose "Patch nào?" "${labels[@]}"
  local v="${ids[$((CHOICE - 1))]}" have="${cur[$((CHOICE - 1))]}"
  [ "$have" != "*" ] || die "v$v là patch cũ (trước khi có env) — đang ở mọi env"
  choose_envs "Đưa v$v lên thêm env nào?" "" $(echo "$have" | tr ',' ' ')
  [ -n "$ENVS" ] || { info "huỷ"; return 0; }
  reg patch-envs "$v" --add "$ENVS" || return 1
  after_write "patch v$v → $ENVS"
}

menu_rs_domain() {
  choose_env "Đổi rs_domain của env nào?"
  local env="$SEL_ENV" rs path l
  read_lines reg list-envs
  for l in "${LINES[@]}"; do
    IFS=$'\t' read -r e r _ p <<< "$l"
    [ "$e" = "$env" ] && { rs="$r"; path="$p"; }
  done
  echo
  info "[$env] rs_domain hiện tại: $rs   ssh.path: $path"
  info "app của env: $(reg apps-in-env "$env" | tr '\n' ' ')"
  ask "rs_domain mới (vd https://rs.example.com)"
  local new="$REPLY"
  ask "Thư mục SSH trên server ứng với domain mới (<path>/app/…)" "$path"
  local np="$REPLY"
  echo
  info "sẽ ghi configs/deploy.json + rs_domain mọi config app env $env, rồi deploy:"
  info "  manifest + bytecode lên $new/app/ TRƯỚC → kiểm hash qua SFTP → chép config sang ../configs (bạn tự commit + push SAU)"
  yes_no "Đổi rs_domain env $env → $new?" N || { info "huỷ"; return 0; }
  reg set-rs-domain "$env" "$new" --ssh-path "$np" || return 1
  after_write "rs_domain $env → $new"
}

menu_api_domain() {
  choose_env "Đổi api_domain của env nào?"
  local env="$SEL_ENV" api l
  api=$(python3 - "$ROOT" "$env" <<'PY'
import json, os, sys
root, env = sys.argv[1], sys.argv[2]
cfg = json.load(open(os.path.join(root, "configs", "deploy.json")))
for t in cfg.get("targets", []):
    if t.get("name") == env:
        print(t.get("api_domain") or "-")
        break
else:
    print("-")
PY
)
  echo
  info "[$env] api_domain hiện tại: $api"
  info "app của env: $(reg apps-in-env "$env" | tr '\n' ' ')"
  ask "api_domain mới (vd https://api.example.com/?)"
  local new="$REPLY"
  echo
  info "sẽ ghi configs/deploy.json + api_domain mọi config app env $env:"
  yes_no "Đổi api_domain env $env → $new?" N || { info "huỷ"; return 0; }
  reg set-api-domain "$env" "$new" || return 1
  after_write "api_domain $env → $new"
}

# Chạy thử 1 app trên iOS simulator (debug, qua tools/cmd/run.sh — tự xuất
# main_app, áp tên/bundle/icon, thoát thì trả icon gốc). Chưa simulator nào
# bật → mở Simulator; nhiều máy đang bật → hỏi chọn.
menu_run() {
  pick_bundle 0
  [ -f "$APPS_DIR/$BUNDLE/app.yaml" ] || die "apps/$BUNDLE/app.yaml chưa có — không chạy thử được"
  local l; local -a udids=() labels=()
  booted_sims() {
    xcrun simctl list devices booted 2>/dev/null \
      | sed -nE 's/^ +(.+) \(([0-9A-F-]{36})\) \(Booted\).*/\2\t\1/p'
  }
  read_lines booted_sims
  if [ ${#LINES[@]} -eq 0 ]; then
    info "chưa có simulator nào bật — mở Simulator…"
    open -a Simulator
    for _ in $(seq 60); do
      read_lines booted_sims
      [ ${#LINES[@]} -gt 0 ] && break
      sleep 1
    done
    [ ${#LINES[@]} -gt 0 ] || die "Simulator chưa boot máy nào — mở 1 máy trong Simulator rồi chạy lại"
  fi
  for l in "${LINES[@]}"; do udids+=("${l%%$'\t'*}"); labels+=("${l#*$'\t'}"); done
  if [ ${#udids[@]} -eq 1 ]; then
    CHOICE=1
  else
    choose "Simulator:" "${labels[@]}"
  fi
  info "chạy $BUNDLE trên ${labels[$((CHOICE - 1))]}…"
  DEVICE="${udids[$((CHOICE - 1))]}" APP_ID="$BUNDLE" bash "$T/run.sh" ios-sim
}

main_menu() {
  choose "Việc cần làm:" \
    "--Hằng ngày" \
    "Ra patch" \
    "Deploy lên rs_domain" \
    "Xem kế hoạch (plan)" \
    "Đưa patch lên env khác (staging → pre → prod)" \
    "--Phát hành bản app" \
    "Build host (release app)" \
    "Cập nhật trạng thái store của 1 bản build" \
    "--Sự cố / ép" \
    "Rút patch lỗi (retract)" \
    "Ép cập nhật / ép restart (bắt cập nhật · cấm patch cũ · min_force_update · app thay thế)" \
    "--Ít dùng" \
    "Quản lý app (thêm app / đánh dấu app chết / Apple ID / đổi env)" \
    "Kiểm link store / app thay thế" \
    "Nhận đổi version package host (đổi ABI)" \
    "Đổi rs_domain của env" \
    "Đổi api_domain của env" \
    "--Dev" \
    "Chạy thử app trên simulator"
  case "$CHOICE" in
    1) menu_patch ;;
    2) menu_deploy ;;
    3) menu_plan ;;
    4) menu_promote ;;
    5) menu_build ;;
    6) menu_store ;;
    7) menu_retract ;;
    8) menu_force ;;
    9) menu_app ;;
    10) reg check-links ;;
    11) menu_host_pkg ;;
    12) menu_rs_domain ;;
    13) menu_api_domain ;;
    14) menu_run ;;
  esac
}

# ── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
  "") main_menu ;;
  reg) shift; reg "$@" ;;
  patch)
    shift; MFU=0; PENVS=staging
    while [ $# -gt 0 ]; do
      case "$1" in
        --min-force-update) MFU="${2:?--min-force-update cần giá trị}"; shift 2 ;;
        --envs) PENVS="${2:?--envs cần giá trị (vd staging,pre)}"; shift 2 ;;
        *) die "cờ lạ: $1 (patch: --envs E1,E2 --min-force-update N)" ;;
      esac
    done
    do_patch "$MFU" "$PENVS" ;;
  release)
    shift; APP_ID="" PLATFORM="" VERSION_ARG="" MODE="" UNLOCK_ARG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --app)      APP_ID="${2:?--app cần giá trị}"; shift 2 ;;
        --platform) PLATFORM="${2:?--platform cần giá trị}"; shift 2 ;;
        --version)  VERSION_ARG="${2:?--version cần giá trị}"; shift 2 ;;
        --mode)     MODE="${2:?--mode cần giá trị}"; shift 2 ;;
        --unlock)   UNLOCK_ARG="${2:?--unlock cần giá trị (vd 2026-10-20 hoặc +3)}"; shift 2 ;;
        *) die "cờ lạ: $1 (release: --app/--platform/--version/--mode/--unlock)" ;;
      esac
    done
    if [ -z "$APP_ID" ] || [ -z "$PLATFORM" ]; then
      die "release không tương tác cần --app --platform [--version] (hoặc chạy wizard: bash tools/dynpub.sh)"
    fi
    case "$PLATFORM" in 1|ios|iOS) PLATFORM=ios ;; 2|android|Android) PLATFORM=android ;; *) die "--platform lạ: $PLATFORM" ;; esac
    # parse sớm: sai ngày thì dừng trước khi giữ version_code
    [ -z "$UNLOCK_ARG" ] || UNLOCK_ARG="$(python3 -B "$T/unlockdate.py" parse "$UNLOCK_ARG")" || die "--unlock lạ"
    is_registered "$APP_ID" || reg bundle-add "$APP_ID"
    [ -n "$MODE" ] || MODE=$([ "$PLATFORM" = android ] && echo ddm || echo adhoc)
    VERSION_ARG="$(reg reserve-version "$APP_ID" ${VERSION_ARG:+--version "$VERSION_ARG"})" \
      || die "không lấy được version"
    info "version: $VERSION_ARG"
    DYNPUB_YES="${DYNPUB_YES:-0}" build_host "$APP_ID" "$PLATFORM" "$VERSION_ARG" "$MODE" "$UNLOCK_ARG" ;;
  *) die "lệnh lạ '$1' (xem: bash tools/dynpub.sh help)" ;;
esac
