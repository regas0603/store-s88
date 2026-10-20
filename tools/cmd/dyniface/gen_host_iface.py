#!/usr/bin/env python3
# Sinh dynamic_interface CHO HOST BUILD từ file đầy đủ (dùng cho module validate).
#
# Vì sao cần 2 file:
#   - Module compile (`dart2bytecode --validate`) cần entry cho CẢ library chỉ có
#     trong module (vd. package:clarity_flutter, package:sentry do module tự mang).
#   - Host build (`flutter build ... --dynamic-interface`) chạy annotator với
#     TOÀN BỘ yaml. Thư mục section `dynamically-callable` được lookup thẳng trong
#     host program (LibraryIndex.getMember) → library không có trong host = CRASH:
#         Unhandled exception: The library 'X' has not been indexed
#         DynamicInterfaceSpecification.findNodes ...
#         Target kernel_snapshot_program failed
#     (Các section khác — extendable / can-be-overridden / callable /
#      can-be-used-as-type — CFE tự load library từ yaml nên KHÔNG crash:
#      đã verify bằng thí nghiệm gen_kernel_aot.)
#
# Vậy: bản host = bản đầy đủ − entry `dynamically-callable` trỏ library không có
# trong host program (anchor). Không annotation mất đi vì host không có library đó.
#
# Dùng: python3 gen_host_iface.py [--src full.yaml] [--out host.yaml] [--anchor dill]
import argparse
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
ENTRY_LIB = re.compile(r"library: '([^']+)'")
SECTION = re.compile(r"^[A-Za-z][A-Za-z0-9-]*:\s*$")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(ROOT, "dist/dynamic_interface.yaml"))
    ap.add_argument("--out", default=os.path.join(ROOT, "dist/dynamic_interface.host.yaml"))
    ap.add_argument("--anchor", default=os.path.join(ROOT, "dist/app_content.anchor.dill"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for p in (args.src, args.anchor):
        if not os.path.isfile(p):
            print("thiếu file: %s" % p, file=sys.stderr)
            return 1

    anchor = open(args.anchor, "rb").read()
    lines = open(args.src, encoding="utf-8").read().splitlines(keepends=True)

    section = None
    kept, dropped = [], []
    warned = {}  # lib -> section (section khác, chỉ cảnh báo)
    for ln in lines:
        if SECTION.match(ln):
            section = ln.strip()[:-1]
        m = ENTRY_LIB.search(ln)
        if m:
            lib = m.group(1)
            if not lib.startswith("dart:") and lib.encode() not in anchor:
                # Mọi section (không chỉ dynamically-callable): entry trỏ library
                # không có trong anchor sẽ bị CFE force-load vào host program lúc
                # build (--dynamic-interface) → lib module-only (vd. app_package/
                # box_shadow) lọt vào host snapshot → runtime module load bị VM
                # reject "already loaded". Gỡ hết ở bản host; bản đầy đủ vẫn
                # là input validate của module (dart2bytecode --validate).
                if section == "dynamically-callable":
                    dropped.append((lib, ln.strip()))
                else:
                    warned.setdefault((section, lib), 0)
                    warned[(section, lib)] += 1
                    dropped.append((lib, ln.strip()))
                continue
        kept.append(ln)

    print("[host-iface] %s -> %s" % (os.path.basename(args.src), os.path.basename(args.out)))
    if dropped:
        print("  gỡ %d entry dynamically-callable (library không có trong host program):"
              % len(dropped))
        for lib, ln in dropped:
            print("    - %s" % ln)
    else:
        print("  không entry nào phải gỡ")
    if warned:
        print("  [note] %d entry section khác cũng trỏ library không có trong"
              " anchor — ĐÃ Gỡ (chống lọt lib module-only vào host):" % len(warned))
        for (sec, lib), n in warned.items():
            print("    - %s: %s (x%d)" % (sec, lib, n))

    if args.dry_run:
        print("DRY-RUN: chưa ghi")
        return 0
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    open(args.out, "w", encoding="utf-8").write("".join(kept))
    return 0


if __name__ == "__main__":
    sys.exit(main())
