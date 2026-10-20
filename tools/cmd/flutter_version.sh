#!/usr/bin/env bash
# tools/cmd/flutter_version.sh — đọc version Flutter (engine dynmod) từ
# configs/flutter.json — NGUỒN DUY NHẤT; đổi version = sửa file đó rồi chạy
# lại bash tools/setup.sh (tự sync + build lại engine + pub get + module).
#
#   bash tools/cmd/flutter_version.sh            # in version/ref (vd 3.47.0)
#   bash tools/cmd/flutter_version.sh --commit   # commit đầy đủ của ref trong checkout
#                                                # (rỗng + exit 1 nếu checkout chưa có ref)
#   bash tools/cmd/flutter_version.sh --stamp <out_dir>
#                                                # commit engine ở out_dir được build từ
#
# "version" là tag (3.47.0) hoặc commit flutter/flutter. Env DYNMOD_REV vẫn
# thắng file config (thử nghiệm tạm).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONF="$ROOT/configs/flutter.json"
WORK="${DYNMOD_WORK:-$(dirname "$ROOT")/dart-sdk-build}"
# Flutter DÙNG (CLI flutter/dart + framework): ../engine/flutter-framework (gom 1
# chỗ, tạo bằng: bash tools/cmd/dynmod.sh backup); chưa có thì checkout build.
ENGINE_HOME="${DYNMOD_ENGINE_HOME:-$(dirname "$ROOT")/engine}"
_FF_DEF="$ENGINE_HOME/flutter-framework"; [ -x "$_FF_DEF/bin/flutter" ] || _FF_DEF="$WORK/flutter-framework"
FF="${DYNMOD_FF:-$_FF_DEF}"
STAMP_NAME="dynmod_flutter_rev"   # file trong out/<engine>/ — ghi lúc build engine

ver() {
  if [ -n "${DYNMOD_REV:-}" ]; then echo "$DYNMOD_REV"; return; fi
  [ -f "$CONF" ] || { echo "thiếu $CONF" >&2; exit 2; }
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("version","").strip(); print(v) if v else sys.exit("configs/flutter.json thiếu \"version\"")' "$CONF"
}

case "${1:-}" in
  "")       ver ;;
  --commit) git -C "$FF" rev-parse --verify --quiet "$(ver)^{commit}" ;;
  --stamp)  f="${2:?--stamp cần out_dir}/$STAMP_NAME"; [ -f "$f" ] && head -1 "$f" || exit 1 ;;
  --stamp-name) echo "$STAMP_NAME" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
