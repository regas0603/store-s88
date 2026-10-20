#!/usr/bin/env bash
# tools/cmd/abicheck.sh — nhiều app (mỗi app 1 main_app) dùng CHUNG 1 bytecode:
# kiểm host / main_app / app_package so với "ABI đóng băng" (configs/abi/module_abi.json).
#
#   bash tools/cmd/abicheck.sh snapshot                 # chụp ABI host hiện tại (dynpub release tự gọi)
#   bash tools/cmd/abicheck.sh host                     # host app/ có lệch ABI không
#   bash tools/cmd/abicheck.sh main-app [<dir>]         # main_app ở <dir> (mặc định main_app/)
#                                                       # dùng chung bytecode được không
#   bash tools/cmd/abicheck.sh app-package [<dir>] [--accept]
#        # app_package (mặc định ../app_package) có đòi version package khác
#        # host đóng băng không + báo ràng buộc đổi so với mốc (AI tự nâng ver…).
#        # dynpub patch tự gọi (qua modprep check).
#
# Chi tiết: tools/cmd/abicheck/abi.py, docs/dynmod_build_once_plan.md (P5).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "${1:-}" in
  snapshot|host|main-app|app-package) exec python3 "$ROOT/tools/cmd/abicheck/abi.py" "$@" ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
