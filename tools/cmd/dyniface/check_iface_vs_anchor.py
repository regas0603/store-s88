#!/usr/bin/env python3
# Scan dist/dynamic_interface.yaml, tìm entry sẽ làm crash host build:
#   "The library 'X' has not been indexed"   — lib không có trong anchor
#   "Container 'X' not found in library 'L'"  — class không có trong program
# Entry có `member:` dùng LibraryIndex.getMember (crash thấy trong build);
# entry chỉ có class dùng container lookup.
# Class của lib `dart:*` nằm trong platform_strong.dill chứ không trong anchor
# → truyền thêm platform dill để tránh false-positive.
# Dùng: python3 check_iface_vs_anchor.py [yaml] [anchor] [platform_strong.dill]
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
yaml_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist/dynamic_interface.yaml")
anchor_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "dist/app_content.anchor.dill")
if len(sys.argv) > 3:
    platform_path = sys.argv[3]
else:
    cands = sorted(glob.glob(
        os.path.join(os.environ.get("DYNMOD_ENGINE_SRC", ""), "out/*/flutter_patched_sdk/platform_strong.dill"))
        + glob.glob(os.path.join(ROOT, "../engine/out/*/flutter_patched_sdk/platform_strong.dill"))
        + glob.glob(os.path.join(ROOT, "../dart-sdk-build/flutter-framework/engine/src/out/"
                                       "*/flutter_patched_sdk/platform_strong.dill")))
    platform_path = cands[0] if cands else None

anchor = open(anchor_path, "rb").read()
platform = open(platform_path, "rb").read() if platform_path and os.path.exists(platform_path) else b""

lines = open(yaml_path, encoding="utf-8").read().splitlines()
lib_pat = re.compile(r"library: '([^']+)'")
cls_pat = re.compile(r"class: (?:\[([^\]]*)\]|'([^']+)')")
mem_pat = re.compile(r"member: '")

missing_lib = {}      # lib -> [(line, section)]
member_no_cls = []    # (line, lib, class, member) — class vắng → getMember crash
class_only_no_cls = []  # (line, lib, class) — container crash (nếu lookup)
section = None

for i, ln in enumerate(lines, 1):
    if re.match(r"^[A-Za-z][A-Za-z0-9-]*:\s*$", ln):
        section = ln.strip()[:-1]
    m = lib_pat.search(ln)
    if not m:
        continue
    lib = m.group(1)
    has_member = bool(mem_pat.search(ln))
    blob = platform if lib.startswith("dart:") else anchor
    if lib.encode() not in (anchor + platform if lib.startswith("dart:") else anchor):
        missing_lib.setdefault(lib, []).append((i, section))
        continue
    c = cls_pat.search(ln)
    if not c:
        continue
    names = ([x.strip().strip("'\"") for x in c.group(1).split(",")]
             if c.group(1) is not None else [c.group(2)])
    mem = re.search(r"member: '([^']+)'", ln)
    for n in names:
        if not n or n.encode() in blob:
            continue
        if has_member and mem:
            member_no_cls.append((i, lib, n, mem.group(1)))
        else:
            class_only_no_cls.append((i, lib, n))

print("anchor:   %s (%d B)" % (anchor_path, len(anchor)))
print("platform: %s (%d B)" % (platform_path or "-", len(platform)))
print("yaml:     %s (%d dòng)" % (yaml_path, len(lines)))
crash = {k: v for k, v in missing_lib.items()
         if any(s == "dynamically-callable" for _, s in v)}
safe = {k: v for k, v in missing_lib.items() if k not in crash}
print("\n[1] dynamically-callable + lib vắng → CRASH \"has not been indexed\""
      " (phải gỡ ở bản host): %d lib" % len(crash))
for lib, ls in sorted(crash.items()):
    print("    %-88s dòng %s" % (lib, ",".join(str(n) for n, _ in ls)))
print("\n[1b] section khác + lib vắng → KHÔNG crash (CFE tự load từ yaml)"
      " — gen_host_iface.py chỉ CẢNH BÁO: %d lib" % len(safe))
for lib, ls in sorted(safe.items()):
    secs = sorted({s for _, s in ls})
    print("    %-80s %s dòng %s" % (lib, ",".join(secs),
                                    ",".join(str(n) for n, _ in ls)))
print("\n[2] entry member:, class vắng → crash getMember: %d" % len(member_no_cls))
for i, lib, n, mem in member_no_cls[:80]:
    print("    dòng %-6d %-36s member=%-22s %s" % (i, n, mem, lib))
print("\n[3] entry chỉ có class, class vắng → có thể crash container: %d" % len(class_only_no_cls))
for i, lib, n in class_only_no_cls[:80]:
    print("    dòng %-6d %-40s %s" % (i, n, lib))

