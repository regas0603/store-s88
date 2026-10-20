#!/usr/bin/env bash
# tools/cmd/dynpush.sh — PUBLISH CLI cho chuỗi Dart Dynamic Modules (dynmod).
# Thay CLI code-push của Shorebird, nhưng artifact là `.bytecode` (interpreter)
# chứ không phải diff `libapp.so` — xem docs/dynmod_replace_shorebird_plan.md G5/G6.
#
# LUỒNG MỚI (manifest TĨNH — KHÔNG còn server API):
#   app runtime chỉ làm 2 việc: GET api_domain+bundleId (mở khoá) rồi
#   GET {rs_domain}/app/bytecode.manifest → tải {rs_domain}/app/<file>.
#   CLI tự gen manifest mỗi lần patch (tăng version, hash, tên file…).
#
# NHANH TAY (workflow hằng ngày):
#   bash tools/cmd/dynpush.sh patch --version 2       # 1. build + gen manifest
#        (entry mặc định ../app_package/modules/home_content.dart)
#   bash tools/cmd/dynpush.sh check --rs <rs_domain> --module-version 0
#                                         # 2. host đang có v0 sẽ nhận gì?
#   bash tools/cmd/dynpush.sh fetch --rs <rs_domain>  # 3. tải về + verify (E2E)
#
# ĐẦY ĐỦ LỆNH:
#   patch   [--entry <file.dart>] [--version <int>] [--bytecode <file>]
#        (entry mặc định ../app_package/modules/home_content.dart)
#        [--build] [--no-anchor-hash] [--min-force-update <int>]
#        (alias cũ: `module`)
#        (a) build .bytecode — ủy quyền tools/cmd/dynmod.sh module
#        (b) sha256 CONTENT file .bytecode → rename <ten>_<hash8>.bytecode
#        (c) anchor_hash = sha256 anchor.dill (chống lệch ABI; --no-anchor-hash tắt)
#        (d) GEN manifest: publish/app/bytecode.manifest + copy .bytecode
#            cạnh nó — upload thư mục này lên $rs_domain/app/ khi nào cần
#            (tính năng upload TẠM CHƯA làm — rs_domain là nginx tĩnh/S3…).
#            Version: --version rõ ràng, không thì cũ + 1 — TRỪ khi content
#            y hệt manifest cũ (cùng file + hash) → GIỮ version (idempotent).
#            min_force_update (ngưỡng FORCE UPDATE): --min-force-update rõ
#            ràng, không thì GIỮ giá trị manifest cũ (0 nếu chưa có). Máy đang
#            chạy module version NHỎ hơn ngưỡng → sau khi tải bản mới app sẽ
#            hiện popup restart; đã đủ ngưỡng → không popup, bản mới tự áp ở
#            lần mở app sau.
#   check   --rs <rs_domain> [--module-version N] [--anchor-hash H]
#        # GET đúng manifest runtime app GET → in ra host sẽ nhận patch nào.
#   fetch   --rs <rs_domain> [-o file.bytecode] [--module-version N]
#        # Tải .bytecode theo manifest + verify sha256 (giống hệt
#        # loading_kit/dyn_loader làm lúc chạy) → E2E không cần máy thật.
#   release --version 1.0.4+7 --build [--platform android] [--arch arm64]
#        # build APK host bằng engine ddm (KHÔNG upload, KHÔNG nhúng pubkey).
#        # iOS cần ký tay → build .ipa bằng Xcode.
#   verify  --file <f.bytecode> [--hash <sha256hex>]
#        # Verify offline (sha256). Thiếu --hash thì tự tính.
#   doctor                              # sức khoẻ máy build (tools/cmd/doctor.sh)
#
# Env: DYNPUSH_RS         rs_domain cho check/fetch (hoặc truyền --rs)
#      DYNPUSH_MODULE_NAME (mặc định app_content)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RS="${DYNPUSH_RS:-}"
MODULE_NAME="${DYNPUSH_MODULE_NAME:-app_content}"
# Thư mục publish (TRACK GIT — khác dist/): bytecode.manifest + file .bytecode
# đang phát hành — copy cả 2 lên $rs_domain/app/ là app nhận bản mới. Version
# auto so với manifest ở đây → commit folder này để biết lần patch có lên ver.
STAGE="${DYNPUSH_STAGE:-$ROOT/publish/app}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
die() { echo "LỖI: $*" >&2; exit 1; }
info() { echo "  [dynpush] $*"; }
ok()   { echo "  ${GRN}[PASS]${RST} $*"; }
warn() { echo "  ${YEL}[WARN]${RST} $*"; }

usage() { sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; }

# Thư mục checkout flutter dùng engine ddm (build host / compile module).
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
# indexed"). Bản đầy đủ vẫn dùng cho `dart2bytecode --validate` lúc compile
# module. Xem: tools/cmd/dyniface/gen_host_iface.py
host_iface() {
  local src="$1" out="$ROOT/dist/dynamic_interface.host.yaml"
  # report của python → stderr để `$(host_iface ...)` chỉ captures đường dẫn
  python3 "$ROOT/tools/cmd/dyniface/gen_host_iface.py" --src "$src" --out "$out" >&2 \
    || { echo "LỖI: sinh dynamic_interface.host.yaml thất bại" >&2; return 1; }
  echo "$out"
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

# ---- parse --key value ------------------------------------------------------
# Gán vào biến cùng tên: RS, VERSION, MODULE_VERSION, ENTRY, FILE, PLATFORM,
# ARCH, BYTECODE, ANCHOR_HASH, HASH, OUT, MIN_FORCE_UPDATE; cờ --build /
# --no-anchor-hash đặt BUILD=1 / NO_ANCHOR=1.
args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --rs)              RS="$2"; shift 2 ;;
      --version)         VERSION="$2"; shift 2 ;;
      --module-version)  MODULE_VERSION="$2"; shift 2 ;;
      --entry)           ENTRY="$2"; shift 2 ;;
      --file)            FILE="$2"; shift 2 ;;
      --platform)        PLATFORM="$2"; shift 2 ;;
      --arch)            ARCH="$2"; shift 2 ;;
      --bytecode)        BYTECODE="$2"; shift 2 ;;
      --anchor-hash)     ANCHOR_HASH="$2"; shift 2 ;;
      --hash)            HASH="$2"; shift 2 ;;
      --min-force-update) MIN_FORCE_UPDATE="$2"; shift 2 ;;
      -o|--out)          OUT="$2"; shift 2 ;;
      --build)           BUILD=1; shift ;;
      --no-anchor-hash)  NO_ANCHOR=1; shift ;;
      -h|--help|help)    usage; exit 0 ;;
      *) die "flag lạ: $1 (xem: bash tools/cmd/dynpush.sh --help) — server-based flags cũ (--app/--release/--channel/--module) đã bỏ" ;;
    esac
  done
}

# $1=file $2=hash_hex → 0 nếu sha256 khớp. GiốNG hệt verify của app
# (loading_kit/dyn_loader): chỉ so sha256(bytes) == hash — KHÔNG verify chữ ký.
verify_bytes() {
  local f="$1" hash="$2" actual
  actual="$(shasum -a 256 "$f" | awk '{print $1}')"
  if [ "$actual" != "$(printf '%s' "$hash" | tr 'A-Z' 'a-z')" ]; then
    warn "sha256 KHÔNG khớp: file=$actual server=$hash"
    return 1
  fi
  ok "sha256 khớp ($hash)"
}

jsonget() { # $1=json $2=key đường dẫn "a.b.c" (dùng node, không thêm dep)
  printf '%s' "$1" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try { const o=JSON.parse(s); const k=process.argv[1];
        const v = k.split(".").reduce((a,p)=>a?.[p], o);
        if (v === undefined) process.exit(3);
        process.stdout.write(typeof v === "string" ? v : JSON.stringify(v));
      } catch(e) { process.stderr.write(s); process.exit(2); }
    });' "$2"
}

# GET manifest từ rs_domain — ĐÚNG URL runtime app GET (`{rs}/app/bytecode.manifest`).
# → stdout JSON manifest; lỗi mạng/HTTP → JSON lỗi (caller die).
fetch_manifest() {
  curl -sSf "${RS%/}/app/bytecode.manifest" 2>&1 \
    || echo '{"error":"khong goi duoc rs_domain — kiem tra --rs / DYNPUSH_RS"}'
}


# ─── release: build APK host bằng engine ddm (KHÔNG upload) ─────────────────
cmd_release() {
  args "$@"
  : "${VERSION:?--version bắt buộc (vd 1.0.4+7)}"
  PLATFORM="${PLATFORM:-android}"
  ARCH="${ARCH:-arm64}"

  # Build APK release bằng engine ddm — KHÔNG nhúng pubkey (không ký/verify).
  # iOS cần ký tay (Apple) → build .ipa bằng Xcode (không qua CLI này).
  [ "$PLATFORM" = "android" ] || die "release --build hiện chỉ hỗ trợ android (iOS: build tay bằng Xcode)"
  local FF; FF="$(engine_ff)"
  [ -x "$FF/bin/flutter" ] || die "không thấy $FF/bin/flutter (engine ddm chưa build? bash tools/cmd/dynmod.sh engine)"
  local IFACE="$ROOT/dist/dynamic_interface.yaml"
  [ -f "$IFACE" ] || die "thiếu $IFACE — sinh trước: bash tools/cmd/dyniface.sh gen"
  local IFACE_HOST; IFACE_HOST="$(host_iface "$IFACE")" \
    || die "sinh dynamic_interface.host.yaml thất bại"
  mkdir -p "$ROOT/dist"
  info "build APK ddm (engine $FF)…"
  (cd "$ROOT/app" && "$FF/bin/flutter" build apk --release \
    --local-engine-src-path "$(engine_src)" \
    --local-engine=android_release_arm64 \
    --local-engine-host=host_release_arm64 \
    --extra-front-end-options="--dynamic-interface=$IFACE_HOST" \
    --build-name="${VERSION%%+*}" \
    --build-number="${VERSION##*+}" \
    ) || die "build APK thất bại"
  local apk="$ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
  info "APK: $apk ($(stat -f%z "$apk") bytes)"
  echo "App gate đọc rs_domain từ Git JSON (configs/apps/<bundleId>.json) — không cần dart-define URL."
}

# ─── patch (alias module): build .bytecode + GEN manifest ───────────────────
cmd_patch() {
  args "$@"

  # Version manifest: --version tường minh → validate ngay (fail nhanh); KHÔNG
  # truyền → quyết SAU khi có hash content (xem mục (d) dưới): content y hệt
  # manifest cũ → GIỮ version (patch/setup chạy lại không tạo "update" giả),
  # khác → manifest cũ + 1.
  local version="${VERSION:-}"
  if [ -n "$version" ]; then
    case "$version" in
      *[!0-9]*) die "--version phải là số nguyên (nhận được: $version)" ;;
    esac
  fi

  # Ngưỡng FORCE UPDATE (`min_force_update` trong manifest): --min-force-update
  # rõ ràng, không thì GIỮ giá trị manifest staging cũ, không thì 0.
  # App chỉ hiện popup restart khi module version đang chạy < ngưỡng này.
  local min_force="${MIN_FORCE_UPDATE:-}"
  if [ -z "$min_force" ]; then
    min_force=0
    if [ -f "$STAGE/bytecode.manifest" ]; then
      min_force="$(jsonget "$(cat "$STAGE/bytecode.manifest")" min_force_update 2>/dev/null || echo 0)"
      [ "$min_force" = "null" ] && min_force=0
      case "$min_force" in ''|*[!0-9]*) min_force=0 ;; esac
      info "không truyền --min-force-update → giữ manifest cũ: $min_force"
    else
      info "không truyền --min-force-update → min_force_update = 0 (không ép restart)"
    fi
  fi
  case "$min_force" in
    ''|*[!0-9]*) die "--min-force-update phải là số nguyên >= 0 (nhận được: $min_force)" ;;
  esac

  # (a) compile bytecode — ủy quyền cho dynmod.sh (anchor + dart2bytecode --validate)
  local out
  if [ -n "${BYTECODE:-}" ] && [ -f "$BYTECODE" ]; then
    out="$BYTECODE"
    info "dùng bytecode có sẵn: $out"
  else
  # MAC DINH: module luon la ../app_package (host = repo/app, module = app_package).
  [ -n "${ENTRY:-}" ] || ENTRY="$ROOT/../app_package/modules/home_content.dart"
  [ -f "$ENTRY" ] || die "không thấy entry $ENTRY (mặc định ../app_package/modules/home_content.dart — sau convert_to_package chạy: bash tools/cmd/modprep.sh apply)"
  # Gen ra <ten>.bytecode (mặc định app_content.bytecode) — bước (b) bên dưới
  # sẽ hash content rồi rename thành <ten>_<hash8>.bytecode (content-addressed).
  out="$ROOT/dist/${MODULE_NAME}.bytecode"
  mkdir -p "$ROOT/dist"
  info "build module qua tools/cmd/dynmod.sh (anchor + dart2bytecode --validate)…"
  bash "$ROOT/tools/cmd/dynmod.sh" module "$ENTRY" -o "$out" \
    || die "compile module thất bại (log trong \$DYNMOD_WORK/logs)"
  fi
  [ -f "$out" ] || die "không tìm thấy bytecode $out"
  local size; size="$(stat -f%z "$out")"
  info "bytecode: $size bytes"

  # (b) sha256 CONTENT — chỉ chống file hỏng/truncated (KHÔNG ký chữ ký).
  #     Rồi RENAME file thành <ten>_<hash8>.bytecode (8 ký tự đầu sha256) —
  #     content-addressed: cùng nội dung → cùng tên, khác nội dung → khác tên.
  local hash stem
  hash="$(shasum -a 256 "$out" | awk '{print $1}')"
  stem="$(basename "${out%.bytecode}")"
  # Đã rename từ lần chạy trước (qua --bytecode truyền file cũ) → bỏ suffix.
  case "$stem" in
    *_[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) stem="${stem%_*}" ;;
  esac
  local renamed="$(dirname "$out")/${stem}_${hash:0:8}.bytecode"
  if [ "$out" != "$renamed" ]; then
    mv -f "$out" "$renamed"
    info "rename content-addressed: $(basename "$renamed")"
    out="$renamed"
  fi
  info "sha256 = $hash"

  # (c) anchor_hash: dynmod.sh đặt anchor.dill cạnh file .bytecode TRƯỚC khi
  # rename (app_content.anchor.dill). App so `min_host_anchor` trong manifest
  # với anchor của host → chặn lệch ABI.
  local anchor_hash="${ANCHOR_HASH:-}"
  if [ -z "$anchor_hash" ] && [ -z "${NO_ANCHOR:-}" ]; then
    local anchor="$(dirname "$out")/${stem}.anchor.dill"
    if [ -f "$anchor" ]; then
      anchor_hash="$(shasum -a 256 "$anchor" | awk '{print $1}')"
      info "anchor_hash = ${anchor_hash:0:16}… (từ $(basename "$anchor"))"
    else
      warn "không thấy anchor.dill cạnh bytecode → không ghi min_host_anchor"
    fi
  fi

  local file="$(basename "$out")"

  # (d) Version auto — SAU khi có $file + $hash: content y hệt manifest cũ
  # (cùng file + hash) → GIỮ version — patch/setup chạy lại không tạo "update"
  # giả cho app; khác → manifest cũ + 1. --version tường minh (ở trên) vẫn thắng.
  if [ -z "$version" ]; then
    local old=0 old_file="" old_hash=""
    if [ -f "$STAGE/bytecode.manifest" ]; then
      old="$(jsonget "$(cat "$STAGE/bytecode.manifest")" version 2>/dev/null || echo 0)"
      [ "${old:-}" = "null" ] && old=0
      case "$old" in ''|*[!0-9]*) old=0 ;; esac
      old_file="$(jsonget "$(cat "$STAGE/bytecode.manifest")" file 2>/dev/null || echo '')"
      [ "${old_file:-}" = "null" ] && old_file=""
      old_hash="$(jsonget "$(cat "$STAGE/bytecode.manifest")" hash 2>/dev/null || echo '')"
      [ "${old_hash:-}" = "null" ] && old_hash=""
    fi
    if [ -n "$old_file" ] && [ "$old_file" = "$file" ] \
        && [ "$(printf '%s' "$old_hash" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$hash" | tr 'A-Z' 'a-z')" ]; then
      version="$old"
      info "content không đổi ($file) → GIỮ manifest version v$version"
    else
      version=$((old + 1))
      info "manifest version: v$old → v$version (content khác manifest cũ / chưa có manifest)"
    fi
  fi

  # GEN manifest vào publish/app/ (track git) — KHÔNG còn server API.
  # Cặp (bytecode.manifest + file .bytecode) copy lên $rs_domain/app/ là xong.
  mkdir -p "$STAGE"
  cp -f "$out" "$STAGE/$file"
  # JSON.stringify qua node để escape đúng (hash là hex nhưng safe; vẫn
  # dùng node cho nhất quán + thêm generated_at).
  node -e '
    const fs = require("fs");
    const m = {
      module: process.argv[1],
      version: Number(process.argv[2]),
      file: process.argv[3],
      hash: process.argv[4],
      min_host_anchor: process.argv[5] || null,
      min_force_update: Number(process.argv[8] || 0),
      size: Number(process.argv[6]),
      generated_at: new Date().toISOString(),
    };
    fs.writeFileSync(process.argv[7], JSON.stringify(m, null, 2) + "\n");
  ' "$MODULE_NAME" "$version" "$file" "$hash" "$anchor_hash" "$size" \
    "$STAGE/bytecode.manifest" "$min_force"
  # Dọn bytecode cũ trong staging (chỉ giữ bản hiện tại — kể cả file tên cũ
  # app_b_v*.bytecode) — file cũ trên
  # rs_domain giữ nguyên (rollback = copy lại file cũ / revert manifest).
  find "$STAGE" -name "*.bytecode" ! -name "$file" -delete 2>/dev/null || true

  ok "manifest v$version đã gen:"
  echo "  $STAGE/bytecode.manifest"
  echo "  $STAGE/$file"
  echo "  min_force_update = $min_force (app chỉ ép popup restart khi module version đang chạy < $min_force)"
  echo
  echo "Deploy (chưa tự động — rs_domain là host tĩnh của bạn):"
  echo "  scp $STAGE/* user@rs-domain:/var/www/app/   # hoặc cp lên S3/nginx"
  echo "Kiểm chứng:  bash tools/cmd/dynpush.sh check --rs <rs_domain> --module-version <N>"
}

# ─── check: host đang chạy sẽ nhận patch nào? ─────────────────────────────
# GET ĐÚNG manifest runtime app GET → so sánh version/anchor như dyn_loader.
cmd_check() {
  args "$@"
  : "${RS:?--rs bắt buộc (rs_domain — hoặc env DYNPUSH_RS)}"
  local modver="${MODULE_VERSION:-0}" resp
  resp="$(fetch_manifest)"
  echo "$resp" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let o; try{o=JSON.parse(s)}catch(e){console.log("  \x1b[31m[FAIL]\x1b[0m manifest không phải JSON: "+s);process.exit(1)}
      if(o.error){console.log("  \x1b[31m[FAIL]\x1b[0m "+o.error);process.exit(1)}
      const cur=Number(process.argv[2]);
      const anchor=process.argv[3]||"";
      console.log("== bytecode.manifest @ "+process.argv[1]+" (máy đang có v"+cur+") ==");
      console.log("  version          : v"+o.version+"  file="+o.file+"  size="+o.size);
      console.log("  hash             : "+o.hash);
      console.log("  min_host_anchor  : "+(o.min_host_anchor??"(khong rang buoc)"));
      const minForce = Number(o.min_force_update||0);
      console.log("  min_force_update : "+(minForce>0?minForce:"0 (khong ep restart)"));
      const anchorMismatch = !!(o.min_host_anchor && anchor &&
        o.min_host_anchor.toLowerCase() !== anchor.toLowerCase());
      if(anchorMismatch){console.log("  update_available : false — anchor KHÔNG khớp (lech ABI)");process.exit(0)}
      if(!(o.version>cur)){console.log("  update_available : false — host GIỮ NGUYÊN bản đang chạy");process.exit(0)}
      console.log("  update_available : true  → sẽ tải "+o.file);
      console.log("  force_restart    : "+(cur<minForce
        ? "true — dang chay v"+cur+" < min_force_update "+minForce+" → app hiện POPUP RESTART sau khi tải"
        : "false — đã đủ ngưỡng → KHÔNG popup, bản mới tự áp ở lần mở app sau"));
      console.log("  download_url     : "+process.argv[4]+"/app/"+o.file);
    });' "$RS" "$modver" "${ANCHOR_HASH:-}" "${RS%/}"
}

# ─── fetch: tải .bytecode về + verify y hệt app lúc chạy ──────────────────
# Dùng để E2E không cần máy thật: cùng sha256 trên bytes.
cmd_fetch() {
  args "$@"
  : "${RS:?--rs bắt buộc (rs_domain — hoặc env DYNPUSH_RS)}"
  local modver="${MODULE_VERSION:-0}" resp
  resp="$(fetch_manifest)"
  if [ "$(jsonget "$resp" error 2>/dev/null)" != "" ] && \
     [ "$(jsonget "$resp" version 2>/dev/null)" = "" ]; then
    echo "$resp"
    die "không đọc được manifest từ $RS"
  fi
  if [ -n "${ANCHOR_HASH:-}" ]; then
    local m_anchor; m_anchor="$(jsonget "$resp" min_host_anchor 2>/dev/null || echo '')"
    [ "$m_anchor" = "null" ] && m_anchor=""
    if [ -n "$m_anchor" ] && [ "${m_anchor,,}" != "${ANCHOR_HASH,,}" ]; then
      die "anchor KHÔNG khớp (manifest ${m_anchor:0:16}… vs máy ${ANCHOR_HASH:0:16}…) — app sẽ bỏ update này"
    fi
  fi
  local num hash file
  num="$(jsonget "$resp" version)"
  if [ "$num" -le "$modver" ]; then
    echo "$resp"
    die "không có update để fetch (manifest v$num, máy đang có v$modver — host giữ nguyên)"
  fi
  hash="$(jsonget "$resp" hash)"
  file="$(jsonget "$resp" file)"
  local url="${RS%/}/app/$file"
  local out="${OUT:-$ROOT/dist/fetched_$file}"
  mkdir -p "$(dirname "$out")"
  info "tải module v$num: $url"
  curl -sSf -o "$out" "$url" || die "tải $url thất bại"
  info "lưu: $out ($(stat -f%z "$out") bytes)"
  verify_bytes "$out" "$hash" || die "VERIFY THẤT BẠI — app sẽ từ chối module này"
  echo
  echo "OK — bytecode này app sẽ nạp được (sha256 khớp)."
}

# ─── verify: check offline 1 file .bytecode ────────────────────────────────
cmd_verify() {
  args "$@"
  : "${FILE:?--file bắt buộc}"
  [ -f "$FILE" ] || die "không tìm thấy $FILE"
  local hash="${HASH:-}"
  [ -n "$hash" ] || hash="$(shasum -a 256 "$FILE" | awk '{print $1}')"
  echo "== verify $FILE ($(stat -f%z "$FILE") bytes) =="
  verify_bytes "$FILE" "$hash" || die "VERIFY THẤT BẠI"
  echo "OK"
}

cmd_doctor() { exec bash "$ROOT/tools/cmd/doctor.sh" "$@"; }

# ─── dispatch ──────────────────────────────────────────────────────────────
case "$CMD" in
  release)      cmd_release "$@" ;;
  patch|module) cmd_patch "$@" ;;
  check)        cmd_check "$@" ;;
  fetch|pull)   cmd_fetch "$@" ;;
  verify)       cmd_verify "$@" ;;
  doctor)       cmd_doctor "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
