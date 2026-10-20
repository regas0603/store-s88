#!/usr/bin/env bash
# tools/cmd/ensure_deps.sh — Tự cài SDK thiếu (trừ Xcode) qua brew. Idempotent.
# Được tools/setup.sh gọi ở bước 0. Chạy lẻ cũng được:
#   bash tools/cmd/ensure_deps.sh [--dry-run] [--no-install]
# Env tương đương: DRY_RUN=1 / NO_INSTALL=1
# Quy tắc: thiếu cái nào cài cái đó. Xcode là NGOẠI LỆ DUY NHẤT —
# không script được (App Store + Apple ID + ~15GB) nên chỉ kiểm tra.
set -uo pipefail
DRY_RUN="${DRY_RUN:-0}"; NO_INSTALL="${NO_INSTALL:-0}"
for a in "$@"; do case "$a" in --dry-run|-n) DRY_RUN=1;; --no-install) NO_INSTALL=1;; esac; done
RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' RST=$'\033[0m'
say(){ local c=""; case "$1" in PASS) c=$GRN;; WARN) c=$YEL;; FAIL) c=$RED;; esac; echo "  ${c}[$1]${c:+$RST} $2"; }
[ "$(uname -s)" = Darwin ] || { say FAIL "OS $(uname -s) — tool viết cho macOS"; exit 1; }
# 0a. brew itself
if ! command -v brew >/dev/null 2>&1; then
  if [ "$NO_INSTALL" = 1 ]; then say FAIL "thiếu brew (--no-install: cài tay rồi chạy lại)"; exit 1
  elif [ "$DRY_RUN" = 1 ]; then say dry-run 'cài brew (official install.sh)'; 
  else
    echo "  ${YEL}[WARN]${RST} chưa có brew — cài ngay (hỏi password 1 lần)"; /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
  fi
fi
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
command -v brew >/dev/null 2>&1 && say PASS "brew: $(command -v brew)" || { say FAIL "chưa có brew"; exit 1; }
# helper: $1=label $2=binary $3..=brew args
ensure(){ local l="$1" c="$2"; shift 2
  if command -v "$c" >/dev/null 2>&1; then say SKIP "$l đã có ($(command -v "$c"))"; return 0; fi
  if [ "$NO_INSTALL" = 1 ]; then say FAIL "thiếu $l (brew install $*)"; return 1; fi
  if [ "$DRY_RUN" = 1 ]; then say dry-run "brew install $*"; return 0; fi
  echo "  ${YEL}[WARN]${RST} thiếu $l — cài: brew install $*"; brew install "$@" || { say FAIL "brew install $* thất bại"; return 1; }
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  command -v "$c" >/dev/null 2>&1 && say PASS "$l vừa cài" || { say FAIL "$l cài xong vẫn thiếu '$c' — mở terminal mới"; return 1; }; }
ensure_cask(){ local l="$1" s="$2"; shift 2
  if [ -e "$s" ]; then say SKIP "$l đã có"; return 0; fi
  if [ "$NO_INSTALL" = 1 ]; then say FAIL "thiếu $l (brew install $*)"; return 1; fi
  if [ "$DRY_RUN" = 1 ]; then say dry-run "brew install $*"; return 0; fi
  echo "  ${YEL}[WARN]${RST} thiếu $l — cài: brew install $*"; brew install "$@" || { say FAIL "brew install $* thất bại"; return 1; }; }
FAIL=0
ensure "git" git git || FAIL=1
ensure "python3" python3 python@3.12 || FAIL=1
if command -v node >/dev/null 2>&1; then
  NJ="$(node --version | sed 's/^v//' | cut -d. -f1)"
  if [ "${NJ:-0}" -ge 20 ]; then say SKIP "node đã có $(node --version) (>= 20)"
  elif [ "$NO_INSTALL" = 1 ]; then say FAIL "node $(node --version) quá cũ (cần >= 20)"; FAIL=1
  elif [ "$DRY_RUN" = 1 ]; then say dry-run "brew install node  # nâng $(node --version) lên >= 20"
  else echo "  ${YEL}[WARN]${RST} node $(node --version) quá cũ — nâng (>= 20)"; brew install node || FAIL=1
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true; fi
else ensure "node (>= 20)" node node || FAIL=1; fi
# KHÔNG cài flutter qua brew: repo chỉ dùng Flutter của engine
# (../engine/flutter-framework — CLAUDE.md §1); setup bước 2 lo phần đó.
ensure "CocoaPods (pod, iOS cần)" pod cocoapods || FAIL=1
if command -v java >/dev/null 2>&1; then say SKIP "java đã có ($(java -version 2>&1 | head -1))"
else ensure_cask "Java 17 (temurin)" "/Library/Java/JavaVirtualMachines/temurin-17.jdk" --cask temurin@17 || FAIL=1; fi
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
BREW_CT="/opt/homebrew/share/android-commandlinetools/cmdline-tools"
# Gradle chỉ cần SDK có platforms + build-tools + licenses (vd SDK của Android
# Studio — không có cmdline-tools vẫn build được) → đủ thì không cài gì.
if ls -d "$SDK_DIR"/platforms/android-* "$SDK_DIR"/build-tools/* >/dev/null 2>&1 \
   && [ -f "$SDK_DIR/licenses/android-sdk-license" ]; then
  say SKIP "Android SDK đã có ($SDK_DIR: platforms + build-tools + licenses)"
else
  ensure_cask "Android cmdline-tools" "$BREW_CT" --cask android-commandlinetools || FAIL=1
  if [ "$DRY_RUN" = 1 ]; then say dry-run 'sdkmanager --install platform-tools "platforms;android-36" "build-tools;36.0.0" + accept licenses'
  elif [ "$NO_INSTALL" = 0 ]; then
    SDKM="$(find "$SDK_DIR/cmdline-tools" "$BREW_CT" -name sdkmanager -type f 2>/dev/null | head -1)"
    if [ -n "${SDKM:-}" ] && [ -x "$SDKM" ]; then
      # --sdk_root: cài VÀO $SDK_DIR (sdkmanager của brew mặc định cài vào thư mục brew — Gradle không thấy)
      echo "  ${YEL}[WARN]${RST} cài packages Android cơ bản vào $SDK_DIR"; mkdir -p "$SDK_DIR"
      "$SDKM" --sdk_root="$SDK_DIR" --install "platform-tools" "platforms;android-36" "build-tools;36.0.0" 2>&1 | tail -2 || echo "  ${YEL}[WARN]${RST} sdkmanager thất bại — cài tay trong Android Studio"
      yes | "$SDKM" --sdk_root="$SDK_DIR" --licenses >/dev/null 2>&1 && say PASS "đã accept Android licenses" || echo "  ${YEL}[WARN]${RST} accept licenses thất bại — chạy tay: yes | $SDKM --sdk_root=$SDK_DIR --licenses"
      [ -n "${ANDROID_HOME:-}" ] || echo "  ${YEL}[WARN]${RST} nên đặt trong ~/.zshrc: export ANDROID_HOME=$SDK_DIR"
    else echo "  ${YEL}[WARN]${RST} chưa thấy sdkmanager — cài tay trong Android Studio > SDK Manager"; fi
  fi
fi
if xcrun metal --version >/dev/null 2>&1; then say SKIP "Metal Toolchain đã có (engine host cần)"
elif [ "$NO_INSTALL" = 1 ]; then echo "  ${YEL}[WARN]${RST} Metal thiếu — chạy: xcodebuild -downloadComponent MetalToolchain"
elif [ "$DRY_RUN" = 1 ]; then say dry-run "xcodebuild -downloadComponent MetalToolchain"
else echo "  ${YEL}[WARN]${RST} thiếu Metal Toolchain — tải ngay (hỏi sudo)"; xcodebuild -downloadComponent MetalToolchain 2>&1 | tail -2 && say PASS "Metal vừa cài" || echo "  ${YEL}[WARN]${RST} tải Metal thất bại — chạy tay lệnh trên"; fi
if xcode-select -p >/dev/null 2>&1; then say SKIP "Xcode đã có ($(xcodebuild -version 2>/dev/null | head -1)) — NGOẠI LỆ: luôn cài tay"
else say FAIL "Xcode — CÀI TAY trên App Store (~15GB), rồi: sudo xcode-select --switch /Applications/Xcode.app; sudo xcodebuild -runFirstLaunch"; FAIL=1; fi
exit "$FAIL"
