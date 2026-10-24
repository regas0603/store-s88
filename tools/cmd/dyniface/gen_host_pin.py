#!/usr/bin/env python3
"""Sinh app/lib/shell/host_packages.g.dart từ configs/abi/host_packages.yaml.

Sinh 2 thứ:
  - `kHostPackages`: tên package nằm ở host (sdk + t0_required +
    t1_frozen_pure_dart) → `HostServices.capabilities` (P3).
  - import (có prefix, không dùng) MỌI library public (lib/*.dart, không phải
    part, an toàn cho VM) của các package host đó → kernel host + anchor chứa
    TRỌN package (P4.1). File này nằm trên cây import của main.dart (qua
    dynmod_host_services.dart) nên không cần gọi hàm ghim nào.

Không import (vẫn ở host nếu plugin kéo vào, nhưng KHÔNG lộ cho module — khai
cả library sẽ giữ hàng nghìn binding FFI/desktop trong host):
  NOT_EXPOSED (win32, dbus, jni, objective_c, …).

Dùng: python3 gen_host_pin.py [--check]   (--check: exit 1 nếu file lệch)
"""
import argparse
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # không để lại __pycache__/classify_packages.pyc
sys.path.insert(0, _HERE)
import classify_packages as cp  # noqa: E402

OUT = os.environ.get("DYNMOD_HOST_PIN", os.path.join(cp.APP, "lib", "shell", "host_packages.g.dart"))
HOST_TIERS = ("sdk", "t0_required", "t1_frozen_pure_dart")

# Ở host (plugin import) nhưng module không bao giờ gọi thẳng → không pin,
# không khai interface (tránh phình host).
NOT_EXPOSED = {
    "sky_engine",  # = dart:ui (khai qua dart:ui)
    "win32", "win32_registry", "dbus", "nm", "posix", "xdg_directories",
    "ffi", "jni", "objective_c",
}

WEB_DART = {"dart:html", "dart:js_interop", "dart:js_util", "dart:ui_web", "dart:js",
            "dart:js_interop_unsafe"}
WEB_PKG = {"web", "flutter_web_plugins"}
VM_TRUE = {"dart.library.io", "dart.library.ffi", "dart.library.isolate",
           "dart.library.core", "dart.library.async"}
DIRECTIVE = re.compile(r"^\s*(?:import|export)\s+([^;]*);", re.M | re.S)


def lib_roots():
    """{package: thư mục lib/} từ package_config của host."""
    import json
    pc = json.load(open(cp.PKG_CONFIG))
    base = os.path.dirname(os.path.abspath(cp.PKG_CONFIG))
    out = {}
    for p in pc["packages"]:
        r = p["rootUri"].replace("file://", "")
        if not r.startswith("/"):
            r = os.path.normpath(os.path.join(base, r))
        out[p["name"]] = os.path.join(r, p.get("packageUri", "lib/").rstrip("/"))
    return out


def vm_uri(directive):
    for cond, uri in re.findall(r"if\s*\(\s*([\w.]+)\s*\)\s*'([^']+)'", directive):
        if cond in VM_TRUE:
            return uri
    uris = re.findall(r"'([^']+)'", directive)
    return uris[0] if uris else None


class WebProbe:
    """Library (theo nhánh VM) có chạm web không — đi bắc cầu, có cache."""

    def __init__(self, roots):
        self.roots = roots
        self.memo = {}

    def touches_web(self, path, stack=None):
        if path in self.memo:
            return self.memo[path]
        stack = stack or set()
        if path in stack or not os.path.isfile(path):
            return False
        stack.add(path)
        hit = False
        src = open(path, encoding="utf-8", errors="replace").read()
        for m in DIRECTIVE.finditer(src):
            uri = vm_uri(m.group(1))
            if not uri:
                continue
            if uri.startswith("dart:"):
                hit = uri in WEB_DART
            elif uri.startswith("package:"):
                if "/" not in uri:
                    continue
                name, rest = uri[len("package:"):].split("/", 1)
                hit = name in WEB_PKG or (name in self.roots and
                                          self.touches_web(os.path.join(self.roots[name], rest), stack))
            else:
                hit = self.touches_web(os.path.normpath(os.path.join(os.path.dirname(path), uri)), stack)
            if hit:
                break
        stack.discard(path)
        self.memo[path] = hit
        return hit


def web_branch_only(d):
    """File trong lib/ mà package chỉ trỏ tới qua nhánh web của import/export
    điều kiện (vd spine_flutter: `'init.dart' if (dart.library.html)
    'init_web.dart'`) — trên VM không ai nạp, và thường không biên dịch được
    (kiểu web_ffi_fork lệch dart:ffi) dù không import thẳng dart:html."""
    web, vm = set(), set()
    for root, _, files in os.walk(d):
        for f in files:
            if not f.endswith(".dart"):
                continue
            p = os.path.join(root, f)
            src = open(p, encoding="utf-8", errors="replace").read()
            for m in DIRECTIVE.finditer(src):
                directive = m.group(1)
                conds = re.findall(r"if\s*\(\s*([\w.]+)\s*\)\s*'([^']+)'", directive)
                if not conds:
                    continue
                v = vm_uri(directive)
                for uri in [u for _, u in conds] + re.findall(r"'([^']+)'", directive)[:1]:
                    if uri.startswith("dart:") or uri.startswith("package:"):
                        continue
                    t = os.path.normpath(os.path.join(root, uri))
                    (vm if uri == v else web).add(t)
    return web - vm


def public_libs(pkg, roots, probe):
    """lib/*.dart không phải part, không chạm web trên nhánh VM."""
    d = roots.get(pkg)
    if not d or not os.path.isdir(d):
        return [], []
    web_only = web_branch_only(d)
    keep, skipped = [], []
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if not f.endswith(".dart") or not os.path.isfile(p):
            continue
        head = open(p, encoding="utf-8", errors="replace").read(4096)
        if re.search(r"^\s*part\s+of\b", head, re.M):
            continue
        if os.path.normpath(p) in web_only or probe.touches_web(p):
            skipped.append("package:%s/%s" % (pkg, f))
            continue
        keep.append("package:%s/%s" % (pkg, f))
    return keep, skipped


def render(names, imports):
    lines = [
        "// GENERATED — KHÔNG SỬA TAY. Nguồn: configs/abi/host_packages.yaml",
        "// Sinh lại: bash tools/cmd/dyniface.sh packages --write",
        "//",
        "// Import (không dùng) mọi library public của package host → kernel host +",
        "// anchor chứa trọn package; module dùng chung, không tự mang bản riêng",
        "// (tránh \"already loaded\"). docs/dynmod_build_once_plan.md P4.1.",
        "// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use",
        "",
    ]
    lines += ["import '%s' as h%d;" % (u, i) for i, u in enumerate(imports)]
    lines += [
        "",
        "/// Package nằm ở host (sdk + t0_required + t1_frozen_pure_dart) —",
        "/// `HostServices.capabilities` (docs/dynmod_build_once_plan.md P3).",
        "const Set<String> kHostPackages = <String>{",
    ]
    lines += ["  '%s'," % n for n in names]
    lines += ["};", ""]
    return "\n".join(lines)


def build():
    tiers = cp.parse_manifest(cp.MANIFEST)
    names = sorted(n for t in HOST_TIERS for n in tiers.get(t, []))
    roots = lib_roots()
    probe = WebProbe(roots)
    imports, skipped = [], []
    for n in names:
        if n in NOT_EXPOSED:
            continue
        keep, skip = public_libs(n, roots, probe)
        imports += keep
        skipped += skip
    return names, imports, skipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if not os.path.isfile(cp.MANIFEST):
        print("\033[31m[FAIL]\033[0m chưa có %s — chạy: bash tools/cmd/dyniface.sh packages --write" % cp.MANIFEST)
        return 1
    names, imports, skipped = build()
    text = render(names, imports)
    rel = os.path.relpath(OUT, cp._ROOT)
    if a.check:
        cur = open(OUT, encoding="utf-8").read() if os.path.isfile(OUT) else ""
        if cur != text:
            print("\033[31m[FAIL]\033[0m %s lệch manifest — chạy: bash tools/cmd/dyniface.sh packages --write" % rel)
            return 1
        print("\033[32m[PASS]\033[0m %s khớp manifest (%d package, %d import)" % (rel, len(names), len(imports)))
        return 0
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("\033[32m[PASS]\033[0m đã ghi %s (%d package, %d import, bỏ %d lib chạm web)" % (rel, len(names), len(imports), len(skipped)))
    for s in skipped:
        print("         bỏ (web): %s" % s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
