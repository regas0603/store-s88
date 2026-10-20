#!/usr/bin/env python3
"""Sinh dist/dynamic_interface.yaml tu anchor dill (host kernel) + platform dill.

Module tu dong "thua" moi thu vien da co trong anchor (dio, json_annotation,
shared_preferences, flutter, ...) nen moi tham chieu tu module phai khai
capability o day (dynamic_interface.md — library item = toan bo public
class/member cua thu vien). Chay lai khi host doi (main/loading_kit/...).
"""
import json
import os
import re
import subprocess

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))  # repo root (tools/cmd/dyniface)
_WORK = os.environ.get(
    "DYNMOD_WORK",
    os.path.abspath(os.path.join(_ROOT, "..", "dart-sdk-build")))  # relative từ folder project

# Engine DÙNG: DYNMOD_ENGINE_SRC (dyniface.sh export) > ../engine (bản chép gọn) > checkout
_ENG = os.environ.get("DYNMOD_ENGINE_SRC") or next(
    (d for d in (os.path.join(os.path.dirname(_ROOT), "engine"),) if os.path.isdir(os.path.join(d, "out"))),
    _WORK + "/flutter-framework/engine/src")
_APP = os.environ.get("DYNMOD_APP", _ROOT + "/app")
ANCHOR = os.environ.get("DYNIFACE_ANCHOR", _ROOT + "/dist/app_content.anchor.dill")
PLATFORM = os.environ.get(
    "DYNIFACE_PLATFORM",
    _ENG + "/out/android_release_arm64/flutter_patched_sdk/platform_strong.dill",
)
OUT = os.environ.get("DYNMOD_IFACE", _ROOT + "/dist/dynamic_interface.yaml")

# Package LOAI BO khoi yaml (van co the xuat hien trong strings anchor do
# source text nhac den, nhung khong nam trong host closure / khong compile duoc
# tren VM target khi bi force-load boi getDynamicInterfaceUserLibraryUris).
EXCLUDE_PACKAGES = {
    "web",  # package:web (dart:js_interop/dom) — chi dung tren web, VM compile loi
    # Windows-only (transitive cua shared_preferences/path_provider qua *_windows):
    # class/member khong co trong kernel target flutter → validator CRASH
    # ('Container X not found'), augment khong sua duoc.
    "win32_registry",
    # Test-only packages lot vao closure host (qua dev_dependencies / transitive
    # cua flutter_test) — module khong bao gio cham, chi lam yaml phinh:
    "flutter_test", "matcher", "boolean_selector", "term_glyph", "fake_async",
    "leak_tracker", "leak_tracker_flutter_testing", "leak_tracker_testing",
    "test_api", "vm_service", "win32",
    # Ở host (plugin kéo vào) nhưng module không gọi thẳng — khai cả library
    # giữ hàng nghìn binding FFI/desktop trong host. Khớp NOT_EXPOSED của
    # gen_host_pin.py (P4.1).
    "dbus", "nm", "posix", "xdg_directories", "ffi", "jni", "objective_c",
}

# dart:* ma module co the cham vao (loc tu platform dill, bo qua mirrors/html/vmservice).
DART_LIBS = [
    "dart:core", "dart:async", "dart:collection", "dart:convert", "dart:io",
    "dart:math", "dart:typed_data", "dart:developer", "dart:ui", "dart:ffi",
    "dart:isolate", "dart:_internal", "dart:_http",
]


EXTRA = os.environ.get("DYNIFACE_EXTRA", _ROOT + "/configs/abi/dynamic_interface.extra.yaml")

# Đích dynamic call được phép (library-level) — xem main().
DYNAMIC_CALL_LIBS = ["dart:core", "dart:async", "dart:collection", "dart:convert",
                     "dart:math", "dart:typed_data"]


PKG_CONFIG = os.environ.get(
    "DYNMOD_PKG_CONFIG", _APP + "/.dart_tool/package_config.json")


SDK_LIB = os.environ.get(
    "DYNIFACE_SDK_LIB",
    _ENG + "/flutter/third_party/dart/sdk/lib",
)
SDK_FLUTTER_LIB = os.environ.get(
    "DYNIFACE_SDK_FLUTTER_LIB",
    _ENG + "/flutter/lib/ui",
)
DENY_FILE = os.environ.get(
    "DYNIFACE_DENY", os.path.join(os.path.dirname(os.path.abspath(__file__)), "dynmod_iface_deny.json"))

DECL_RE = re.compile(
    # chi class/mixin/enum (kernel luu trong library.classes). Khong bat
    # `extension type` — LibraryIndex.getClass se throw null cho extension.
    r"^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+|mixin\s+)*"
    r"(?:class|mixin|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)",
    re.M,
)
# khai báo noSuchMethod THẬT (không trúng comment/doc)
NSM_RE = re.compile(r"\b\w+\??\s+noSuchMethod\s*\(\s*Invocation\b")


def resolve_lib_files(uri: str) -> list[str]:
    """Các file source tạo nên 1 library (main + part)."""
    import glob
    if uri.startswith("package:"):
        pkg, _, rel = uri[len("package:"):].partition("/")
        try:
            with open(PKG_CONFIG) as f:
                cfg = json.load(f)
        except Exception:
            return []
        for p in cfg["packages"]:
            if p["name"] != pkg:
                continue
            root = p["rootUri"]
            if root.startswith("file://"):
                root = root[len("file://"):]
            if not os.path.isabs(root):
                root = os.path.join(os.path.dirname(PKG_CONFIG), root)
            main = os.path.normpath(os.path.join(root, p.get("packageUri", "lib/"), rel))
            if not os.path.isfile(main):
                return []
            files = [main]
            head = open(main, errors="ignore").read(8192)
            for m in re.finditer(r"^\s*part\s+['\"]([^'\"]+)['\"]", head, re.M):
                part = os.path.normpath(os.path.join(os.path.dirname(main), m.group(1)))
                if os.path.isfile(part):
                    files.append(part)
            return files
        return []
    if uri.startswith("dart:"):
        name = uri[len("dart:"):]
        # dart:ui nguon o flutter/lib/ui (khong phai sdk/lib/ui)
        if name == "ui" and os.path.isdir(SDK_FLUTTER_LIB):
            return sorted(glob.glob(os.path.join(SDK_FLUTTER_LIB, "*.dart")))
        d = os.path.join(SDK_LIB, name)
        if os.path.isdir(d):
            return sorted(glob.glob(os.path.join(d, "*.dart")))
        f = os.path.join(SDK_LIB, name + ".dart")
        return [f] if os.path.isfile(f) else []
    return []


def gen_dynamically_callable(host_libs: list[str]) -> list[str]:
    """dynamically-callable theo TUNG CLASS (không dùng library-level vì
    library-item sẽ expose cả class có noSuchMethod → validator chặn:
    'Cannot expose class X ... noSuchMethod'). Học deny từ lỗi trước đó."""
    try:
        with open(DENY_FILE) as f:
            deny = json.load(f)
    except FileNotFoundError:
        deny = {}
    exclude = set(deny.get("exclude_classes", []))
    deny_super = set(deny.get("deny_supertypes", []))
    entries = []
    n_excl = 0
    for uri in host_libs:
        files = resolve_lib_files(uri)
        if not files:
            continue
        classes = []
        for fp in files:
            try:
                text = open(fp, errors="ignore").read()
            except OSError:
                continue
            has_nsm = bool(NSM_RE.search(text))
            for cls in DECL_RE.findall(text):
                if has_nsm or cls in exclude or cls in deny_super:
                    n_excl += 1
                    continue
                classes.append(cls)
        if classes:
            lst = ", ".join(f"'{c}'" for c in sorted(set(classes)))
            entries.append(f"  - {{library: '{uri}', class: [{lst}]}}")
    if n_excl:
        print(f"dynamically-callable: loai {n_excl} class (noSuchMethod/deny)")
    return entries



def uris(path: str, pattern: str) -> set[str]:
    out = subprocess.run(["strings", path], capture_output=True, text=True).stdout
    return set(re.findall(pattern, out))


def read_yaml(path: str):
    """Doc yaml hien tai → (header, {section: [line]})."""
    header, sections, cur = [], {}, None
    for line in open(path):
        s = line.rstrip("\n")
        if s.endswith(":") and not s.startswith(" "):
            cur = s[:-1]
            sections.setdefault(cur, [])
        elif cur is not None and s.strip():
            sections[cur].append(s)
        elif cur is None:
            header.append(s)
    return header, sections


def valid_uri(uri: str) -> bool:
    """Loc URI khong hop le truoc khi dua vao yaml:
    - package khong co trong package_config → getDynamicInterfaceUserLibraryUris se
      them no vao additionalSources va compile that bai (Not found).
    - file la PART (part of ...) → khong phai Library, LibraryIndex throw.
    """
    import json
    import os
    import re
    pkg, _, rel = uri[len("package:"):].partition("/")
    with open(PKG_CONFIG) as f:
        cfg = json.load(f)
    for p in cfg["packages"]:
        if p["name"] != pkg:
            continue
        root = p["rootUri"]
        if root.startswith("file://"):
            root = root[len("file://"):]
        if not os.path.isabs(root):
            # rootUri tuong doi tinh tu vi tri package_config.json
            root = os.path.join(os.path.dirname(PKG_CONFIG), root)
        # package: xac dinh boi packageUri (thuong 'lib/'), khong phai goc goi.
        path = os.path.normpath(os.path.join(root, p.get("packageUri", "lib/"), rel))
        if not os.path.isfile(path):
            return False  # khong ton tai → bo, de validator bao ro neu thieu that
        with open(path, errors="ignore") as f:
            head = f.read(4096)
        return not bool(re.search(r"^\s*part\s+of\b", head, re.M))
    return False  # package khong co trong package_config


_VM_TRUE = {"dart.library.io", "dart.library.ffi", "dart.library.isolate",
            "dart.library.core", "dart.library.async"}
_DIRECTIVE = re.compile(r"^\s*(?:import|export)\s+([^;]*);", re.M | re.S)


def _vm_uri(directive: str):
    for cond, uri in re.findall(r"if\s*\(\s*([\w.]+)\s*\)\s*'([^']+)'", directive):
        if cond in _VM_TRUE:
            return uri
    found = re.findall(r"'([^']+)'", directive)
    return found[0] if found else None


def kernel_libs(entry: str = "package:app/main.dart") -> set[str]:
    """Library package: THẬT SỰ có trong kernel host: đi import/export từ
    main.dart theo đúng nhánh conditional import CFE chọn cho VM. Thay cho
    `strings anchor` — strings bắt cả URI chỉ là chuỗi (nhánh web của
    conditional import…) → khai library không có trong kernel → validator
    crash "library … has not been indexed"."""
    import posixpath
    with open(PKG_CONFIG) as f:
        cfg = json.load(f)
    base = os.path.dirname(os.path.abspath(PKG_CONFIG))
    roots = {}
    for p in cfg["packages"]:
        r = p["rootUri"].replace("file://", "")
        if not r.startswith("/"):
            r = os.path.normpath(os.path.join(base, r))
        roots[p["name"]] = os.path.join(r, p.get("packageUri", "lib/").rstrip("/"))
    seen, stack = set(), [entry]
    while stack:
        uri = stack.pop()
        if uri in seen:
            continue
        name, _, rel = uri[len("package:"):].partition("/")
        path = os.path.join(roots.get(name, "/nonexistent"), rel)
        if not os.path.isfile(path):
            continue
        seen.add(uri)
        src = open(path, encoding="utf-8", errors="replace").read()
        for m in _DIRECTIVE.finditer(src):
            u = _vm_uri(m.group(1))
            if not u or u.startswith("dart:"):
                continue
            if not u.startswith("package:"):
                u = "package:" + posixpath.normpath(posixpath.join(posixpath.dirname(uri[len("package:"):]), u))
            stack.append(u)
    return seen


def manifest_tiers() -> dict[str, list[str]]:
    import sys
    sys.dont_write_bytecode = True
    sys.path.insert(0, _HERE)
    import classify_packages as cp
    return cp.parse_manifest(cp.MANIFEST)


MODULE_ENTRY = os.environ.get(
    "DYNMOD_MODULE_ENTRY", os.path.join(_ROOT, "..", "app_package", "modules", "home_content.dart"))


def module_direct_packages(host: set[str], module_pkgs: set[str]) -> set[str]:
    """Package host mà code module import TRỰC TIẾP (nhánh VM), đi từ entry
    module qua mọi file của app_package + package nội bộ."""
    with open(PKG_CONFIG) as f:
        cfg = json.load(f)
    base = os.path.dirname(os.path.abspath(PKG_CONFIG))
    roots = {}
    for p in cfg["packages"]:
        r = p["rootUri"].replace("file://", "")
        if not r.startswith("/"):
            r = os.path.normpath(os.path.join(base, r))
        roots[p["name"]] = os.path.join(r, p.get("packageUri", "lib/").rstrip("/"))
    # Thiếu entry / app_package → không đi được import nào → iface chỉ còn t1,
    # mất package t0 module dùng (sentry, dio, archive…) — host build ra KHÔNG
    # chạy được patch nào (th1 android vc7). Dừng thay vì sinh bản rút gọn.
    # (`dyniface.sh bootstrap` tự áp modules/ trước khi gọi file này — tới đây
    # mà vẫn thiếu là chưa convert app_package hoặc gọi tay không qua bootstrap.)
    entry = os.path.abspath(MODULE_ENTRY)
    if not os.path.isfile(entry):
        raise SystemExit(
            f"\033[31m[FAIL]\033[0m không thấy module entry {entry}\n"
            "  Chưa có ../app_package → cd ../s88-flutter && bash convert_to_package.sh "
            "--env=prod --hardcode-version, rồi chạy lại.\n"
            "  (Gọi tay file này: chạy bash tools/cmd/dyniface.sh bootstrap — tự áp modules/.)")
    if "app_package" not in roots:
        raise SystemExit(f"\033[31m[FAIL]\033[0m {PKG_CONFIG} không có package app_package — "
                         "chạy: bash tools/cmd/dynmod.sh pubget, rồi chạy lại")
    used, seen, stack = set(), set(), [entry]
    while stack:
        f = stack.pop()
        if f in seen or not os.path.isfile(f):
            continue
        seen.add(f)
        src = open(f, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"^\s*(?:import|export|part)\s+([^;]*);", src, re.M | re.S):
            u = _vm_uri(m.group(1))
            if not u or u.startswith("dart:"):
                continue
            if u.startswith("package:"):
                if "/" not in u:
                    continue
                name, rest = u[len("package:"):].split("/", 1)
                if name in module_pkgs and name in roots:
                    stack.append(os.path.join(roots[name], rest))
                elif name in host:
                    used.add(name)
                continue
            stack.append(os.path.normpath(os.path.join(os.path.dirname(f), u)))
    return used


def exposed_packages(tiers, module_pkgs: set[str], expose_also: set[str]) -> set[str]:
    """Package được lộ (mức library) cho module (P4 — chống phình host):
    package host mà module import trực tiếp + tầng t1 (đóng băng vì module
    dùng) + `expose-packages:` trong configs/abi/dynamic_interface.extra.yaml
    (package xuất hiện trong API của các package trên). Lộ CẢ 125 package host
    làm libapp.so arm64 39MB → 88MB."""
    host = {n for t in ("sdk", "t0_required", "t1_frozen_pure_dart") for n in tiers.get(t, [])}
    direct = module_direct_packages(host, module_pkgs)
    want = direct | set(tiers.get("t1_frozen_pure_dart", [])) | expose_also | {"flutter"}
    print(f"lo cho module: {len(direct)} package module import truc tiep + t1 + "
          f"{len(expose_also)} expose-packages")
    return (host & want) - EXCLUDE_PACKAGES


def main() -> None:
    import sys
    reach = kernel_libs()
    tiers = manifest_tiers()
    # P4.5: host KHÔNG được chứa library của module — nếu có, dart2bytecode
    # bỏ nó khỏi .bytecode (coi là của host) nhưng host thật lại thiếu.
    module_pkgs = set(tiers.get("module_internal", [])) | set(tiers.get("module_allowed", []))
    leaked = sorted({u[len("package:"):].split("/")[0] for u in reach} & module_pkgs)
    if leaked:
        print(f"\033[31m[FAIL]\033[0m kernel host (app/main.dart) chua package cua MODULE: {', '.join(leaked)}")
        print("       host khong duoc import chung — xem configs/abi/host_packages.yaml")
        sys.exit(1)
    expose_also: set[str] = set()
    if os.path.isfile(EXTRA):
        _, sec_lines = read_yaml(EXTRA)
        expose_also = {l.strip()[1:].strip() for l in sec_lines.get("expose-packages", [])
                       if l.strip().startswith("-")}
    exposed = exposed_packages(tiers, module_pkgs, expose_also)
    anchor = {u for u in reach if u[len("package:"):].split("/")[0] in exposed}
    dropped = {u for u in anchor if not valid_uri(u)}
    anchor -= dropped
    libs = sorted(anchor | set(DART_LIBS))
    print(f"kernel libs (tu main.dart, nhanh VM): {len(reach)}, lo cho module: {len(anchor)} "
          f"({len(exposed)} package host), bo part/khong hop le: {len(dropped)}, tong: {len(libs)}")

    # Giu lai cac entry CAP CLASS/MEMBER da augment tu loi validate truoc do
    # (private member khong sinh duoc tu strings anchor).
    # Entry không sinh tự động được (class private lộ member public) — nằm
    # TRONG REPO (configs/abi/dynamic_interface.extra.yaml), không carry-over từ
    # yaml cũ trong dist/ như trước: interface phải tái lập được từ repo
    # (đóng băng theo host release — docs/dynmod_build_once_plan.md P4).
    extras: dict[str, list[str]] = {}
    if os.path.isfile(EXTRA):
        _, sec_lines = read_yaml(EXTRA)
        for sec, lines in sec_lines.items():
            if sec == "expose-packages":
                continue  # danh sách package, không phải entry interface
            keep = [l for l in lines if l.strip().startswith("-")]
            if keep:
                extras[sec] = keep
    n_extras = sum(len(v) for v in extras.values())
    if n_extras:
        print(f"gop {n_extras} entry tu {os.path.relpath(EXTRA, _ROOT)}")

    header = [
        "# Dynamic interface — sinh TU DONG tu anchor dill (host kernel) + platform dill",
        "# (tools/cmd/dyniface/gen_dynamic_interface.py) + class private trong",
        "# configs/dynamic_interface.extra.yaml. KHONG sua tay file nay.",
        "# Module tu dong dung chung moi thu vien da co trong anchor (dio, json_annotation,",
        "# shared_preferences, flutter, ...) → thieu khai la loi COMPILE-TIME.",
        "# Host doi (main/loading_kit/...) → chay lai generator + augment, build lai host.",
        "# Moi dong library = toan bo public class/member cua thu vien do.",
    ]
    sections_out: dict[str, list[str]] = {}
    for title, note in [
        ("callable", "# Module duoc GOI API public."),
        ("dynamically-callable", "# Module duoc GOI dynamic — sinh theo TUNG CLASS, loai class co noSuchMethod (validator chan)."),
        ("extendable", "# Module duoc ke thai/impl/mixin class public."),
        ("can-be-overridden", "# Module duoc override member public."),
        ("can-be-used-as-type", "# Module duoc dung class public lam kiieu (is/as/type param)."),
    ]:
        if title == "dynamically-callable":
            # Library-level CHỈ cho thư viện lõi (đích dynamic call từ dữ liệu
            # JSON: Map/List/String…). Bản cũ liệt kê TỪNG class bằng regex
            # trên source → bắt nhầm class trong comment → validator crash
            # "Container X not found". Thiếu thêm → validator báo tên selector.
            entries = [f"  - {{library: '{lib}'}}" for lib in DYNAMIC_CALL_LIBS]
            entries += extras.get(title, [])
        else:
            entries = [f"  - {{library: '{lib}'}}" for lib in libs]
            entries += extras.get(title, [])
        sections_out[title] = (note, entries)

    with open(OUT, "w") as f:
        f.write("\n".join(header) + "\n")
        for title, (note, entries) in sections_out.items():
            f.write(f"\n{note}\n{title}:\n")
            f.write("\n".join(entries) + "\n")
    total = sum(len(e) for _, e in sections_out.values())
    print(f"da ghi {OUT} ({total} entry)")


if __name__ == "__main__":
    main()
