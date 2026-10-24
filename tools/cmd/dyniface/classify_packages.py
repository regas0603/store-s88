#!/usr/bin/env python3
"""P1 — Phân tầng package host / module (docs/dynmod_build_once_plan.md §P1).

Đọc app/.dart_tool/package_config.json + pubspec từng package, xếp MỖI package
vào đúng 1 tầng:

  sdk                 flutter, sky_engine — engine mang sẵn
  t0_required         plugin native, FFI, *_platform_interface, code host dùng
  t1_frozen_pure_dart pure-Dart ổn định/nóng — AOT trong host, ĐÓNG BĂNG version
  module_allowed      pure-Dart bên thứ ba đi theo module (nâng version được)
  module_internal     code của ../app_package (+ packages/*) — module
  excluded            web/desktop/dev tooling — không ở đâu cả

Luật bắc cầu: dep của package host (t0/t1) cũng phải ở host (host không được
phụ thuộc package module) → tự đẩy tầng lên.

Dùng:
  python3 classify_packages.py                 # dry-run: in báo cáo + bản nháp
  python3 classify_packages.py --write         # ghi/merge configs/abi/host_packages.yaml
                                               # (giữ lựa chọn t1<->module_allowed + planned_native đã duyệt)
  python3 classify_packages.py --write --force # sinh lại sạch, bỏ lựa chọn đã duyệt
  python3 classify_packages.py check           # kiểm manifest vs package_config (exit 1 nếu lệch)
"""
import argparse
import json
import os
import re
import sys

_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
APP = os.environ.get("DYNMOD_APP", os.path.join(_ROOT, "app"))
PKG_CONFIG = os.environ.get("DYNMOD_PKG_CONFIG", os.path.join(APP, ".dart_tool", "package_config.json"))
MODULE_PKG = os.environ.get("DYNMOD_MODULE_PKG", "app_package")
MAIN_APP_PKG = "main_app_package"
MAIN_ONLY = set()  # classify() điền: package chỉ main_app hiện tại kéo vào
MANIFEST = os.environ.get("DYNMOD_HOST_PACKAGES", os.path.join(_ROOT, "configs", "abi", "host_packages.yaml"))

# File host tự viết tay để ghim lib — sẽ được thay bằng bản sinh (P4.1), không
# tính là "code host dùng" (nếu không, mọi thứ nó ghim đều thành t0).
PIN_FILES = {"dynmod_shared_libs_pin.dart", "host_packages.g.dart"}

TIERS = ["sdk", "t0_required", "t1_frozen_pure_dart", "module_allowed", "module_internal", "excluded"]
RANK = {"excluded": -1, "module_internal": 0, "module_allowed": 0, "t1_frozen_pure_dart": 1, "t0_required": 2, "sdk": 3}

SDK_PACKAGES = {"flutter", "sky_engine"}
FFI_PACKAGES = {"ffi", "jni", "objective_c"}
EXCLUDED_NAMES = {"web", "dio_web_adapter", "flutter_web_plugins"}
EXCLUDED_SUFFIXES = ("_web", "_windows", "_linux", "_macos")

# Đề xuất mặc định t1 (P1.3) — người duyệt sửa trong manifest sau khi --write.
T1_DEFAULT = {
    "flutter_riverpod", "riverpod", "state_notifier", "go_router", "dio", "http",
    "intl", "protobuf", "fixnum", "json_annotation", "freezed_annotation",
    "collection", "meta", "crypto", "uuid", "clock", "rxdart", "flutter_svg",
    "vector_graphics", "vector_graphics_codec", "path_parsing",
    "cached_network_image", "cached_network_image_platform_interface",
    "flutter_cache_manager", "octo_image", "hive", "hive_flutter",
    "google_fonts", "isolate_manager", "web_socket_channel", "web_socket",
    "async", "path", "typed_data", "characters", "material_color_utilities",
    "vector_math", "string_scanner", "source_span", "logging",
    "rive",  # khoá version cứng với rive_native (FFI, t0)
}


# ---------------------------------------------------------------- đọc dữ liệu
def load_packages():
    pc = json.load(open(PKG_CONFIG))
    base = os.path.dirname(os.path.abspath(PKG_CONFIG))
    pkgs = {}
    for p in pc["packages"]:
        root = p["rootUri"].replace("file://", "")
        if not root.startswith("/"):
            root = os.path.normpath(os.path.join(base, root))
        pkgs[p["name"]] = root
    return pkgs


def read_pubspec(root):
    try:
        return open(os.path.join(root, "pubspec.yaml"), encoding="utf-8").read()
    except OSError:
        return ""


def pubspec_deps(text):
    """Tên package trong section `dependencies:` top-level (bỏ dev_dependencies)."""
    deps, inside = [], False
    for ln in text.splitlines():
        if re.match(r"^\S", ln):
            inside = ln.split("#")[0].strip() == "dependencies:"
            continue
        if inside:
            m = re.match(r"^  ([A-Za-z0-9_]+)\s*:", ln)
            if m:
                deps.append(m.group(1))
    return deps


def is_plugin(text):
    return re.search(r"^flutter:\s*\n(?:[ \t].*\n|\s*\n)*?\s+plugin:", text, re.M) is not None


def dart_registered(text):
    """Plugin có phần Dart bị dart_plugin_registrant kéo vào kernel host trên
    android/ios (`dartPluginClass`) hoặc là FFI plugin. Plugin chỉ có
    `pluginClass` (đăng ký native, nói chuyện qua MethodChannel) thì phần Dart
    KHÔNG bắt buộc nằm ở host."""
    for plat in ("android", "ios"):
        m = re.search(r"^(\s+)%s:\s*\n((?:\1\s+.*\n|\s*\n)*)" % plat, text, re.M)
        if m and re.search(r"dartPluginClass:|ffiPlugin:\s*true", m.group(2)):
            return True
    return False


def has_assets(text):
    """Package khai assets/fonts trong section flutter: — .bytecode không mang asset."""
    m = re.search(r"^flutter:\s*\n((?:[ \t].*\n|\s*\n)*)", text, re.M)
    return bool(m and re.search(r"^  (?:assets|fonts):", m.group(1), re.M))


def uses_ffi(root):
    lib = os.path.join(root, "lib")
    for dp, _, files in os.walk(lib):
        for f in files:
            if f.endswith(".dart"):
                try:
                    if "import 'dart:ffi'" in open(os.path.join(dp, f), encoding="utf-8", errors="replace").read():
                        return True
                except OSError:
                    pass
    return False


_DIRECTIVE = re.compile(r"^\s*(?:import|export)\b[^;]*;", re.M | re.S)
_PKG_URI = re.compile(r"package:([A-Za-z0-9_]+)/")


def imported_packages(dirs):
    """Package được import/export trong các thư mục (gồm mọi nhánh conditional import)."""
    out = set()
    for d in dirs:
        for dp, _, files in os.walk(d):
            for f in files:
                if f.endswith(".dart") and f not in PIN_FILES:
                    try:
                        src = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
                    except OSError:
                        continue
                    for m in _DIRECTIVE.finditer(src):
                        out.update(_PKG_URI.findall(m.group(0)))
    return out


def read_lock(path):
    """{name: version} từ pubspec.lock."""
    vers, cur = {}, None
    try:
        for ln in open(path, encoding="utf-8"):
            m = re.match(r"^  ([A-Za-z0-9_]+):\s*$", ln)
            if m:
                cur = m.group(1)
            m = re.match(r'^    version: "([^"]+)"', ln)
            if m and cur:
                vers[cur] = m.group(1)
    except OSError:
        pass
    return vers


# ---------------------------------------------------------------- phân tầng
def classify():
    pkgs = load_packages()
    texts = {n: read_pubspec(r) for n, r in pkgs.items()}
    plugin = {n for n, t in texts.items() if is_plugin(t)}
    # Cạnh RUNTIME n -> d: d khai trong dependencies VÀ lib/ của n import d.
    # Dep chỉ dùng ở hook/build.dart (jni/objective_c -> hooks, code_assets,
    # yaml, args…) không vào kernel → không tính. Ngoại lệ: plugin -> plugin
    # (cài đặt federated như path_provider -> path_provider_android) vào kernel
    # qua dart_plugin_registrant dù không ai import.
    deps = {}
    for n, t in texts.items():
        used = imported_packages([os.path.join(pkgs[n], "lib")])
        deps[n] = [d for d in pubspec_deps(t) if d in pkgs and (d in used or (n in plugin and d in plugin))]
    module_root = pkgs.get(MODULE_PKG)
    tier, why = {}, {}

    def set_tier(n, t, reason):
        if n not in tier or RANK[t] > RANK[tier[n]]:
            tier[n], why[n] = t, reason

    # 1. Chỉ lấy package thật sự vào bản build (dependencies, không dev).
    app_name = "app"
    roots = [d for d in pubspec_deps(read_pubspec(APP)) if d in pkgs]

    def is_excluded_name(n):
        return n in EXCLUDED_NAMES or n.endswith(EXCLUDED_SUFFIXES)

    def reach_from(skip_main_app, extra=()):
        reach, stack = set(), list(roots) + list(extra)
        while stack:
            n = stack.pop()
            if n in reach or is_excluded_name(n):
                continue
            reach.add(n)
            if not (skip_main_app and n == MAIN_APP_PKG):
                stack.extend(deps.get(n, []))
        return reach

    reach = reach_from(False)
    # Package CHỈ main_app hiện tại kéo vào (flame, share_plus… của 1 app): riêng
    # app đó, không thuộc bộ host chung → không xếp tầng, không vào manifest
    # (abicheck main-app kiểm từng app). Package đã có trong manifest (vd
    # flutter_localizations: đã duyệt đưa lên host cho mọi main_app) vẫn là chung.
    listed = set()
    if os.path.isfile(MANIFEST):
        listed = {n for names in parse_manifest(MANIFEST).values() for n in names if n in pkgs}
    MAIN_ONLY.clear()
    MAIN_ONLY.update(reach - reach_from(True, listed))

    # Dep KHAI trong pubspec phía module nhưng chưa import ở đâu: không vào
    # kernel hôm nay, nhưng module được phép dùng sau → module_allowed.
    module_declared = set()
    for n, r in pkgs.items():
        if n == MODULE_PKG or (module_root and r.startswith(module_root.rstrip("/") + "/")):
            module_declared.update(d for d in pubspec_deps(texts[n]) if d in pkgs)

    for n in pkgs:
        if n == app_name or n in SDK_PACKAGES:
            continue
        if is_excluded_name(n):
            set_tier(n, "excluded", "web/desktop-only")
        elif n not in reach and n in module_declared:
            set_tier(n, "module_allowed", "khai trong pubspec module nhưng chưa import (dep thừa?)")
        elif n not in reach:
            set_tier(n, "excluded", "dev/tooling hoặc chỉ qua gói bị loại")

    live = [n for n in pkgs if n != app_name and tier.get(n) != "excluded"]

    # 2. Tầng theo luật trực tiếp.
    # KHÔNG tính main_app_package: ../main_app_package là main_app của app build
    # gần nhất (đổi theo app) — nó không được quyết định tầng của bộ host chung.
    # Package main_app import chỉ cần ở host (t1 đạt) — xem bước 3.
    host_code = imported_packages([
        os.path.join(APP, "lib"),
        *[os.path.join(pkgs[p], "lib") for p in ("loading_kit", "content_kit", "dyn_loader") if p in pkgs],
    ])
    internal = {n for n in live if module_root and pkgs[n].startswith(os.path.dirname(module_root.rstrip("/")) + "/" + MODULE_PKG)}

    for n in live:
        if tier.get(n) == "module_allowed":
            continue  # dep thừa đã xếp ở trên
        if n in SDK_PACKAGES:
            set_tier(n, "sdk", "Flutter SDK")
        elif n in plugin and n in internal and not dart_registered(texts[n]):
            # Plugin NỘI BỘ chỉ đăng ký native: native build vào host qua
            # pubspec, phần Dart theo module (hot được) — giao thức
            # MethodChannel phía native đóng băng theo host.
            set_tier(n, "module_internal", "plugin nội bộ chỉ đăng ký native — Dart theo module, GIỮ giao thức channel")
        elif n in plugin:
            set_tier(n, "t0_required", "plugin: Dart phải khớp version native trong host")
        elif has_assets(texts[n]):
            set_tier(n, "t0_required", "có assets/fonts (module không mang asset)")
        elif n in FFI_PACKAGES or uses_ffi(pkgs[n]):
            set_tier(n, "t0_required", "FFI (module không gọi được FFI)")
        elif n.endswith("_platform_interface"):
            set_tier(n, "t0_required", "platform_interface của plugin")
        elif n in host_code and n not in internal and n != MODULE_PKG:
            set_tier(n, "t0_required", "code host (app/loading_kit/…) import")
        elif n in internal or n == MODULE_PKG:
            set_tier(n, "module_internal", "code app_package")
        elif n in T1_DEFAULT:
            set_tier(n, "t1_frozen_pure_dart", "đề xuất mặc định t1")
        else:
            set_tier(n, "module_allowed", "pure-Dart, giữ khả năng nâng version")

    # 3. Bắc cầu: dep của host-tier phải cùng ở host (lặp tới điểm bất động).
    pulled = {}
    changed = True
    while changed:
        changed = False
        for n in live:
            if RANK[tier[n]] < 1:
                continue
            want = "t0_required" if tier[n] in ("t0_required", "sdk") and n != MAIN_APP_PKG else "t1_frozen_pure_dart"
            for d in deps.get(n, []):
                if tier.get(d) == "excluded" or d not in tier:
                    continue
                if RANK[tier[d]] < RANK[want]:
                    if tier[d] == "module_internal":
                        pulled[d] = n
                    tier[d], why[d] = want, "dep bắc cầu của %s" % n
                    changed = True
    for n in MAIN_ONLY:
        tier.pop(n, None)
        why.pop(n, None)
    return pkgs, deps, tier, why, pulled


# ---------------------------------------------------------------- xuất
REVIEWABLE = ("t1_frozen_pure_dart", "module_allowed")


def read_reviewed(path):
    """Lựa chọn đã duyệt trong manifest cũ: ({name: (tier, lý do)}, [dòng planned_native])."""
    choices, planned, sec, cur = {}, [], None, None
    for ln in open(path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if re.match(r"^\S", ln) and not ln.startswith("#"):
            sec = ln.split(":")[0]
            continue
        if sec == "planned_native" and re.match(r"^  - ", ln):
            planned.append(ln)
        elif sec == "tiers":
            m = re.match(r"^  ([a-z0-9_]+):", ln)
            if m:
                cur = m.group(1)
                continue
            m = re.match(r"^    - ([A-Za-z0-9_]+)\s*(?:#\s*\S+(?:\s+—\s+(.*))?)?$", ln)
            if m and cur in REVIEWABLE:
                choices[m.group(1)] = (cur, m.group(2) or "")
    return choices, planned


def render_manifest(tier, why, lock, planned=()):
    out = [
        "# configs/abi/host_packages.yaml — NGUỒN SỰ THẬT ranh giới host / module.",
        "# Sinh/merge:    bash tools/cmd/dyniface.sh packages --write   (giữ lựa chọn đã duyệt)",
        "# Sinh lại sạch: bash tools/cmd/dyniface.sh packages --write --force",
        "# Kiểm:          bash tools/cmd/dyniface.sh packages check",
        "# Chi tiết tầng: docs/dynmod_build_once_plan.md §P1.",
        "#",
        "# Người duyệt CHỈ chuyển package giữa t1_frozen_pure_dart <-> module_allowed",
        "# (sửa cả lý do sau dấu —). t0_required / sdk / excluded / module_internal do",
        "# luật quyết định — sửa luật trong tool, không sửa tay.",
        "# Package ở host (sdk/t0/t1) = ĐÓNG BĂNG version cho tới host release kế tiếp.",
        "host_id_version: 1",
        "",
        "# Plugin native dự phòng (P1.4): thêm vào app/pubspec.yaml TRƯỚC khi build host.",
        "planned_native:%s" % ("" if planned else " []"),
        *planned,
        "",
        "tiers:",
    ]
    for t in TIERS:
        names = sorted(n for n in tier if tier[n] == t)
        out.append("  %s:%s" % (t, "" if names else " []"))
        for n in names:
            out.append("    - %-44s # %s%s" % (n, lock.get(n, "?"), " — " + why[n] if why.get(n) else ""))
        out.append("")
    return "\n".join(out)


def parse_manifest(path):
    tiers, cur, in_tiers = {}, None, False
    for ln in open(path, encoding="utf-8"):
        s = ln.split("#")[0].rstrip()
        if not s:
            continue
        if re.match(r"^\S", s):
            in_tiers = s.strip() == "tiers:"
            continue
        if not in_tiers:
            continue
        m = re.match(r"^  ([a-z0-9_]+):\s*(\[\])?$", s)
        if m:
            cur = m.group(1)
            tiers.setdefault(cur, [])
            continue
        m = re.match(r"^    - ([A-Za-z0-9_]+)$", s)
        if m and cur:
            tiers[cur].append(m.group(1))
    return tiers


def report(pkgs, deps, tier, why, pulled):
    app_lock = read_lock(os.path.join(APP, "pubspec.lock"))
    mod_lock = read_lock(os.path.join(pkgs.get(MODULE_PKG, ""), "pubspec.lock")) if MODULE_PKG in pkgs else {}
    app_direct = set(pubspec_deps(read_pubspec(APP)))
    print("== Phân tầng %d package (%s) ==" % (len(tier), PKG_CONFIG))
    for t in TIERS:
        print("  %-22s %3d" % (t, sum(1 for v in tier.values() if v == t)))
    host = [n for n in tier if tier[n] in ("t0_required", "t1_frozen_pure_dart")]
    if pulled:
        print("\n[!] Package NỘI BỘ app_package bị kéo vào host (sẽ đóng băng theo host):")
        for d, by in sorted(pulled.items()):
            print("    %-30s <- %s" % (d, by))
    miss = sorted(n for n in host if n not in app_direct)
    print("\n[i] %d package host CHƯA là direct dep của app/pubspec.yaml (P4.1 cần thêm để pin import):" % len(miss))
    print("    " + ", ".join(miss))
    drift = sorted((n, app_lock[n], mod_lock[n]) for n in host if n in app_lock and n in mod_lock and app_lock[n] != mod_lock[n])
    print("\n[%s] Lệch version app/pubspec.lock vs app_package/pubspec.lock (package host): %d" % ("!" if drift else "ok", len(drift)))
    for n, a, b in drift:
        print("    %-36s host %-12s module %s" % (n, a, b))
    return app_lock


def cmd_check():
    if not os.path.isfile(MANIFEST):
        print("\033[31m[FAIL]\033[0m chưa có %s — chạy: classify_packages.py --write" % MANIFEST)
        return 1
    pkgs, deps, tier, why, pulled = classify()
    man = parse_manifest(MANIFEST)
    where = {}
    errs = []
    for t, names in man.items():
        if t not in TIERS:
            errs.append("tầng lạ: %s" % t)
        for n in names:
            if n in where:
                errs.append("%s nằm ở 2 tầng: %s, %s" % (n, where[n], t))
            where[n] = t
    # Package mới chưa ghi manifest, tách 2 loại: tầng host (sdk/t0/t1) = host
    # phải mang → BUILD LẠI HOST; tầng module/excluded = chỉ thiếu sổ sách.
    new_host, new_module = [], []
    for n in tier:
        if n not in where:
            (new_host if RANK[tier[n]] >= 1 else new_module).append(n)
    for n, t in where.items():
        if n not in tier:
            errs.append("%s có trong manifest nhưng không còn trong package_config" % n)
            continue
        fixed = tier[n] in ("sdk", "t0_required", "excluded", "module_internal")
        if fixed and t != tier[n]:
            errs.append("%s: manifest %s, luật bắt buộc %s (%s)" % (n, t, tier[n], why.get(n)))
        if not fixed and t not in ("t1_frozen_pure_dart", "module_allowed"):
            errs.append("%s: chỉ được t1_frozen_pure_dart hoặc module_allowed (đang %s)" % (n, t))
    # bắc cầu theo manifest (sau khi người duyệt chỉnh t1/module_allowed)
    rank = {t: RANK[t] for t in TIERS}
    for n, t in where.items():
        if rank.get(t, -1) < 1:
            continue
        for d in deps.get(n, []):
            td = where.get(d)
            if td and td != "excluded" and rank[td] < 1:
                errs.append("%s (%s) phụ thuộc %s (%s) — host không được phụ thuộc module" % (n, t, d, td))
    if errs or new_host or new_module:
        print("== check host_packages.yaml: %d lỗi ==" % (len(errs) + len(new_host) + len(new_module)))
        for e in errs:
            print("  \033[31m[FAIL]\033[0m " + e)
        if new_host:
            print("  \033[31m[FAIL]\033[0m %d package MỚI ở tầng host — CẦN BUILD LẠI HOST (đổi ABI):" % len(new_host))
            for n in sorted(new_host):
                print("           %-28s %-20s %s" % (n, tier[n], why.get(n, "")))
            print("           → bỏ package kéo chúng vào; hoặc nhận: bash tools/dynpub.sh → [11] → [2] Nhận ABI host mới → [5] build lại app")
        if new_module:
            print("  \033[33m[FAIL]\033[0m %d package mới ở tầng module — KHÔNG đổi host, chỉ cần ghi manifest:" % len(new_module))
            for n in sorted(new_module):
                print("           %-28s %s" % (n, tier[n]))
            print("           → bash tools/dynpub.sh → [11] → [1] Chỉ sửa manifest (tự ghi host_packages.yaml + commit)")
        # 2 = chỉ thiếu sổ sách tầng module (dynpub [11] tự sửa); 1 = phần còn lại.
        return 1 if errs or new_host else 2
    if MAIN_ONLY:
        print("  [i]    bỏ qua %d package riêng của main_app hiện tại (abicheck main-app kiểm): %s"
              % (len(MAIN_ONLY), ", ".join(sorted(MAIN_ONLY))))
    print("== check host_packages.yaml: OK (%d package, mỗi package đúng 1 tầng) ==" % len(where))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", nargs="?", default="plan", choices=["plan", "check"])
    ap.add_argument("--write", action="store_true", help="ghi %s" % MANIFEST)
    ap.add_argument("--force", action="store_true", help="sinh lại sạch, bỏ lựa chọn đã duyệt")
    a = ap.parse_args()
    if a.cmd == "check":
        return cmd_check()
    pkgs, deps, tier, why, pulled = classify()
    planned = []
    merged = os.path.exists(MANIFEST) and not a.force
    if merged:
        # Merge: package luật để ngỏ (t1 <-> module_allowed) giữ lựa chọn đã duyệt.
        choices, planned = read_reviewed(MANIFEST)
        for n, (t, reason) in choices.items():
            if tier.get(n) in REVIEWABLE:
                tier[n], why[n] = t, reason or why.get(n, "")
    lock = report(pkgs, deps, tier, why, pulled)
    text = render_manifest(tier, why, lock, planned)
    if not a.write:
        print("\n(dry-run — thêm --write để ghi %s)" % MANIFEST)
        return 0
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(text)
    print("\n\033[32m[PASS]\033[0m đã ghi %s%s" % (MANIFEST, " (merge lựa chọn đã duyệt)" if merged else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
