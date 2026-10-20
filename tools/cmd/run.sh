#!/usr/bin/env bash
# tools/cmd/run.sh — Chạy app Flutter (`app/`) lúc DEV trên Android / iOS.
#
# Script này chỉ lo DEV RUN (debug/profile/release) — bằng Flutter của engine
# (../engine/flutter-framework), KHÔNG dùng flutter trong PATH. Build release lên store + build engine dynamic-modules KHÔNG đi qua đây —
# dùng `tools/cmd/dynmod.sh` (engine) rồi `tools/cmd/dynpush.sh` (đăng release/module).
#
# Chạy:
#   bash tools/cmd/run.sh ios                    # máy iOS bất kỳ (thật/simulator)
#   bash tools/cmd/run.sh ios-sim                # CHỈ simulator iOS
#   bash tools/cmd/run.sh android                # máy Android bất kỳ
#   bash tools/cmd/run.sh android-emu            # CHỈ emulator Android
#   bash tools/cmd/run.sh ios-sim --release
#   APP_ENV=pre bash tools/cmd/run.sh ios-sim
#   bash tools/cmd/run.sh devices                # liệt kê device đang thấy
#
# LƯU Ý: `flutter run -d` chỉ khớp theo ID hoặc TÊN device, KHÔNG khớp theo
# tên platform — `-d ios` luôn báo "No supported devices found with name or
# id matching 'ios'". Nên script tự tra ID thật qua `flutter devices
# --machine` rồi mới truyền vào `-d`.
#
# Mọi tham số phía sau platform được truyền thẳng cho `flutter run`.
#
# Env override:
#   APP_ENV     prod | pre (mặc định prod) → --dart-define=APP_ENV=...
#               Chỉ là tag đóng vào bản build; KHÔNG có code nào trong repo
#               này đọc nó (phần đọc nằm ở code chạy sau khi update). Script
#               chặn giá trị lạ vì gõ sai sẽ không ai phát hiện ra.
#   APP_ID      bundle id của app cần chạy (apps/<bundleId>/). Không đặt →
#               apps/ chỉ có 1 app thì dùng app đó, nhiều app thì hỏi chọn.
#   DEVICE      ID device cụ thể — bỏ qua bước tự tra ở trên
#   FLUTTER     đường dẫn flutter khác (mặc định: ../engine/flutter-framework/bin/flutter)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/app"
# CHỈ Flutter của engine (CLAUDE.md §1) — KHÔNG dùng flutter trong PATH (khác
# version → ghi lại pubspec.lock → lệch ABI host). Đè được bằng env FLUTTER.
_ENG_FLUTTER="$(dirname "$ROOT")/engine/flutter-framework/bin/flutter"
[ -x "$_ENG_FLUTTER" ] || _ENG_FLUTTER="$(dirname "$ROOT")/dart-sdk-build/flutter-framework/bin/flutter"
FLUTTER="${FLUTTER:-$_ENG_FLUTTER}"

[ -x "$FLUTTER" ] || {
  echo "Không thấy $FLUTTER — chạy: bash tools/setup.sh (Flutter của engine ở ../engine/flutter-framework)"
  exit 1
}

[ -d "$APP" ] || { echo "Không thấy thư mục app/ ở $APP"; exit 1; }

APP_ENV="${APP_ENV:-prod}"
case "$APP_ENV" in
  prod|pre) ;;
  *) echo "APP_ENV không hợp lệ: '$APP_ENV' (chỉ nhận: prod | pre)"; exit 1 ;;
esac

usage() {
  echo "Dùng: bash tools/cmd/run.sh {ios|ios-sim|android|android-emu|devices} [cờ flutter run...]"
  echo
  echo "Ví dụ:"
  echo "  bash tools/cmd/run.sh ios-sim"
  echo "  bash tools/cmd/run.sh android --release"
  echo "  APP_ENV=pre bash tools/cmd/run.sh ios-sim"
  echo "  DEVICE=<id> bash tools/cmd/run.sh ios        # chỉ định thẳng"
}

PLATFORM="${1:-}"
[ $# -gt 0 ] && shift || true

case "$PLATFORM" in
  ios)         PLAT_PREFIX="ios";     WANT_EMU="any" ;;
  ios-sim)     PLAT_PREFIX="ios";     WANT_EMU="yes" ;;
  android)     PLAT_PREFIX="android"; WANT_EMU="any" ;;
  android-emu) PLAT_PREFIX="android"; WANT_EMU="yes" ;;
  devices)     exec "$FLUTTER" devices ;;
  *)           usage; exit 1 ;;
esac

# --- Tra ID device thật theo platform ------------------------------------
if [ -n "${DEVICE:-}" ]; then
  DEV="$DEVICE"
else
  command -v python3 >/dev/null 2>&1 || {
    echo "Cần python3 để tra device ID, hoặc chỉ định thẳng: DEVICE=<id> bash tools/cmd/run.sh $PLATFORM"
    exit 1
  }
  echo "… đang tra device $PLATFORM"
  DEVICES_JSON="$("$FLUTTER" devices --machine 2>/dev/null || echo '[]')"
  RESOLVED="$(
    PLAT_PREFIX="$PLAT_PREFIX" WANT_EMU="$WANT_EMU" \
    python3 -c '
import json, os, sys

prefix = os.environ["PLAT_PREFIX"]
want_emu = os.environ["WANT_EMU"]
try:
    devices = json.loads(sys.stdin.read() or "[]")
except ValueError:
    devices = []

matches = [
    d for d in devices
    if str(d.get("targetPlatform", "")).startswith(prefix)
    and d.get("isSupported", True)
    and (want_emu == "any" or bool(d.get("emulator")))
]
if len(matches) == 1:
    print("OK\t" + matches[0]["id"])
elif not matches:
    print("NONE")
else:
    print("MANY")
    for d in matches:
        kind = "simulator/emulator" if d.get("emulator") else "máy thật"
        print("  %s\t%s (%s)" % (d["id"], d.get("name", "?"), kind))
' <<<"$DEVICES_JSON"
  )"

  case "$(head -1 <<<"$RESOLVED")" in
    OK*) DEV="$(head -1 <<<"$RESOLVED" | cut -f2)" ;;
    NONE)
      echo "Không thấy device nào cho '$PLATFORM'."
      case "$PLAT_PREFIX" in
        ios)
          echo "  Mở simulator:  open -a Simulator"
          echo "  hoặc chọn máy: xcrun simctl list devices available | grep iPhone"
          echo "                 xcrun simctl boot <uuid>"
          ;;
        android)
          echo "  Liệt kê emulator: $FLUTTER emulators"
          echo "  Bật emulator:     $FLUTTER emulators --launch <emulator-id>"
          ;;
      esac
      exit 1
      ;;
    MANY)
      echo "Có nhiều device '$PLATFORM' — chọn 1 bằng DEVICE=<id>:"
      tail -n +2 <<<"$RESOLVED"
      [ "$PLAT_PREFIX" = "ios" ] && echo "  (hoặc dùng: bash tools/cmd/run.sh ios-sim để lấy simulator)"
      exit 1
      ;;
  esac
fi

# ── App cần chạy: danh tính (bundle id, tên…) + main_app theo apps/<bundleId>/ ──
APPS_DIR="$ROOT/apps"
if [ -z "${APP_ID:-}" ]; then
  APP_IDS=()
  for d in "$APPS_DIR"/*/; do [ -f "$d/app.yaml" ] && APP_IDS+=("$(basename "$d")"); done
  if [ ${#APP_IDS[@]} -eq 0 ]; then
    echo "Chưa có app nào trong apps/ — tạo bằng: bash tools/dynpub.sh → [9] Quản lý app → nhập bundle id"
    exit 1
  elif [ ${#APP_IDS[@]} -eq 1 ]; then
    APP_ID="${APP_IDS[0]}"
  else
    echo "Chạy app nào?"
    i=1; for b in "${APP_IDS[@]}"; do echo "  [$i] $b"; i=$((i + 1)); done
    read -r -p "Chọn [1-${#APP_IDS[@]}]: " n
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#APP_IDS[@]} ] || { echo "lựa chọn không hợp lệ"; exit 1; }
    APP_ID="${APP_IDS[$((n - 1))]}"
  fi
fi
IDPY="$ROOT/tools/registry/app_identity.py"
eval "$(python3 -B "$IDPY" env "$APP_ID")" || exit 1
bash "$ROOT/tools/cmd/build_main_app.sh" --src "$APP_MAIN_APP_SRC" --no-verify >/dev/null \
  || { echo "xuất main_app của $APP_ID thất bại"; exit 1; }
XCCONFIG="$APP/ios/Flutter/AppIdentity.xcconfig"
python3 -B "$IDPY" xcconfig "$APP_ID" "$XCCONFIG"
trap 'rm -f "$XCCONFIG"' EXIT

echo "▶ flutter run -d $DEV  (app=$APP_ID, APP_ENV=$APP_ENV)"
cd "$APP"
"$FLUTTER" run -d "$DEV" "--dart-define=APP_ENV=$APP_ENV" "$@"
