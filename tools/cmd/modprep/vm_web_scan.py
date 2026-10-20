#!/usr/bin/env python3
"""Quét nhánh VM (iOS/Android) của module: có file nào import web không.

Đi theo import/export/part từ entry, chọn nhánh conditional import đúng như
CFE khi compile cho VM (dart.library.io/ffi/isolate = true; js_interop/html =
false). Chỉ đi sâu vào code của module (app_package + packages nội bộ) —
package bên ngoài do host/pub lo.

Lỗi nếu nhánh VM chạm dart:html / dart:js_interop / dart:js_util / dart:ui_web /
package:web / package:flutter_web_plugins — những thứ đó không compile cho VM.

Dùng: vm_web_scan.py --pkg ../app_package --package-config app/.dart_tool/package_config.json [entry.dart ...]
Exit 0 = sạch, 1 = có import web trên nhánh VM.
"""
import argparse
import json
import os
import re
import sys

VM_TRUE = {"dart.library.io", "dart.library.ffi", "dart.library.isolate",
           "dart.library.core", "dart.library.async"}
WEB_DART = {"dart:html", "dart:js_interop", "dart:js_util", "dart:ui_web", "dart:js"}
WEB_PKG = {"web", "flutter_web_plugins"}
DIRECTIVE = re.compile(r"^\s*(?:import|export|part)\s+([^;]*);", re.M | re.S)
DEFAULT_ENTRIES = ["modules/home_content.dart", "lib/sun_sports.dart", "lib/sun_sports_init.dart",
                   "lib/sun_sports_root.dart", "lib/app.dart"]


def load_roots(pkg_config):
    pc = json.load(open(pkg_config))
    base = os.path.dirname(os.path.abspath(pkg_config))
    roots = {}
    for p in pc["packages"]:
        r = p["rootUri"].replace("file://", "")
        if not r.startswith("/"):
            r = os.path.normpath(os.path.join(base, r))
        roots[p["name"]] = os.path.join(r, p.get("packageUri", "lib/").rstrip("/"))
    return roots


def vm_uri(directive):
    """URI CFE chọn cho VM: nhánh `if (cond)` đầu tiên đúng, không thì URI mặc định."""
    for cond, uri in re.findall(r"if\s*\(\s*([\w.]+)\s*\)\s*'([^']+)'", directive):
        if cond in VM_TRUE:
            return uri
    uris = re.findall(r"'([^']+)'", directive)
    return uris[0] if uris else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pkg", required=True, help="thư mục module (../app_package)")
    ap.add_argument("--package-config", required=True)
    ap.add_argument("entries", nargs="*")
    a = ap.parse_args()

    pkg = os.path.abspath(a.pkg)
    roots = load_roots(a.package_config)
    module_pkgs = {n for n, r in roots.items() if r == os.path.join(pkg, "lib") or r.startswith(pkg + "/")}
    entries = [os.path.join(pkg, e) for e in (a.entries or DEFAULT_ENTRIES)]
    missing = [e for e in entries if not os.path.isfile(e)]
    for e in missing:
        print("  \033[33m[WARN]\033[0m không có entry %s" % os.path.relpath(e, pkg))

    seen, bad, stack = set(), set(), [e for e in entries if e not in missing]
    while stack:
        f = stack.pop()
        if f in seen or not os.path.isfile(f):
            continue
        seen.add(f)
        src = open(f, encoding="utf-8", errors="replace").read()
        for m in DIRECTIVE.finditer(src):
            uri = vm_uri(m.group(1))
            if not uri:
                continue
            if uri.startswith("dart:"):
                if uri in WEB_DART:
                    bad.add((f, uri))
                continue
            if uri.startswith("package:"):
                name, rest = uri[len("package:"):].split("/", 1)
                if name in WEB_PKG:
                    bad.add((f, uri))
                elif name in module_pkgs:
                    stack.append(os.path.join(roots[name], rest))
                continue
            stack.append(os.path.normpath(os.path.join(os.path.dirname(f), uri)))

    print("  [i]    nhánh VM: %d file module" % len(seen))
    if bad:
        print("  \033[31m[FAIL]\033[0m %d import web trên nhánh VM (không compile được cho iOS/Android):" % len(bad))
        for f, uri in sorted(bad):
            print("           %s -> %s" % (os.path.relpath(f, pkg), uri))
        return 1
    print("  \033[32m[PASS]\033[0m nhánh VM không chạm web")
    return 0


if __name__ == "__main__":
    sys.exit(main())
