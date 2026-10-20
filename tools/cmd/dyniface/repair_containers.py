#!/usr/bin/env python3
# Tim thu vien that su khai bao container (class/mixin/enum) va sua entry yaml:
#  - "Container 'X' not found in library 'L'"  -> entry tro sai lib: tim lai.
#  - augment moi: resolve dung lib truoc khi chen.
# Cache ket qua tim kiem trong /tmp/decl_cache.json de khong grep lai.
import json, os, re, subprocess, sys

CACHE = os.environ.get("DYNIFACE_DECL_CACHE", "/tmp/decl_cache.json")
_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))  # repo root
_WORK = os.environ.get(
    "DYNMOD_WORK",
    os.path.abspath(os.path.join(_ROOT, "..", "dart-sdk-build")))  # relative từ folder project

# Engine DÙNG: DYNMOD_ENGINE_SRC (dyniface.sh export) > ../engine (bản chép gọn) > checkout
_ENG = os.environ.get("DYNMOD_ENGINE_SRC") or next(
    (d for d in (os.path.join(os.path.dirname(_ROOT), "engine"),) if os.path.isdir(os.path.join(d, "out"))),
    _WORK + "/flutter-framework/engine/src")
PKG = os.environ.get(
    "DYNMOD_PKG_CONFIG",
    os.path.join(_ROOT, "app", ".dart_tool", "package_config.json"),
)
_APP = os.environ.get("DYNMOD_APP", os.path.join(_ROOT, "app"))
SDK_LIB = os.environ.get(
    "DYNIFACE_SDK_LIB",
    os.path.join(_ENG, "flutter", "third_party", "dart", "sdk", "lib"),
)

# file patch duoi _internal (vi du date_patch.dart thuoc dart:core)
def _sdk_lib_of(filepath):
    rel = os.path.relpath(filepath, SDK_LIB)
    parts = rel.replace(os.sep, "/").split("/")
    comp = parts[0]
    if comp.startswith("_"):
        stem = os.path.splitext(parts[-1])[0].replace("_patch", "")
        if os.path.isdir(os.path.join(SDK_LIB, stem)):
            return stem
        return "core"  # date_patch.dart... -> dart:core
    return comp

def search_dirs():
    pc = json.load(open(PKG))
    dirs = []
    for p in pc["packages"]:
        root = p["rootUri"].replace("file://", "")
        if not root.startswith("/"):
            root = os.path.normpath(os.path.join(_APP, root))
        lib = os.path.join(root, "lib")
        if os.path.isdir(lib):
            dirs.append((p["name"], root, lib))
    # SDK libs (dart:core, dart:io, ...) — class khai bao trong SDK
    if os.path.isdir(SDK_LIB):
        for lib in sorted(os.listdir(SDK_LIB)):
            d = os.path.join(SDK_LIB, lib)
            if os.path.isdir(d):
                dirs.append(("dart:" + lib, d, d))
    return dirs

_DIRS = None
_cache = {}
if os.path.exists(CACHE):
    _cache = json.load(open(CACHE))

def uri_for(root, filepath):
    if root == SDK_LIB or filepath.startswith(SDK_LIB + os.sep):
        return "dart:" + _sdk_lib_of(filepath)
    name = None
    for n, r, _ in search_dirs():
        if r == root:
            name = n
            break
    rel = os.path.relpath(filepath, root)
    if rel.startswith("lib" + os.sep):
        rel = rel[4:]
    if name == "sky_engine":
        # dart:ui vien dich thanh package:sky_engine/* trong checkout —
        # validator chi nhan dart:ui. NHUNG sky_engine con chua ban copy
        # cua dart:core/io... (lib/core/stopwatch.dart...) — map theo path:
        # lib/ui/... -> dart:ui; lib/<x>/... -> dart:<x>.
        parts = rel.replace(os.sep, "/").split("/")
        if parts and parts[0] == "ui":
            return "dart:ui"
        if parts and parts[0] not in ("src", "_internal", "core_patch"):
            return "dart:" + parts[0]
        # lib/_internal/vm*/lib/<x>_patch.dart → lib goc cua patch
        stem = os.path.splitext(parts[-1])[0].replace("_patch", "")
        sky_map = {
            "stopwatch": "core", "date": "core", "core": "core",
            "hash": "core", "error": "core", "regexp": "core", "uri": "core",
            "list": "core", "map": "core", "string": "core", "integers": "core",
            "file_system": "io", "directory": "io", "file": "io",
            "link": "io", "socket": "io", "process": "io", "eventhandler": "io",
            "platform": "io", "secure_socket": "io", "stdio": "io",
        }
        return "dart:" + sky_map.get(stem, "core")
    return "package:%s/%s" % (name, rel.replace(os.sep, "/"))

def find_container(name, member=None):
    """Tra ve (lib_uri, filepath) khai bao class/mixin/enum/extension name,
    hoac None."""
    # key v2: mau mo rong sang `extension`/`extension type` (win32 SetStringArray,
    # Utf16Conversion...) — key cu tra null nen khong duoc dung lai.
    key = "c2:" + name + ":" + (member or "")
    if key in _cache:
        v = _cache[key]
        return (v[0], v[1]) if v else None
    global _DIRS
    if _DIRS is None:
        _DIRS = search_dirs()
    # extension la CONTAINER hop le trong LibraryIndex (containers[extension.name])
    # nhung cu ga augment bo qua → entry gan SAI library (file loi) → validator
    # CRASH "Container 'X' not found" → fix gỡ → augment them lai (ping-pong).
    decl = r"\b(class|mixin|enum|extension\s+type|extension)\s+" + re.escape(name) + r"\b"
    pat = re.compile(decl)
    # member can nam trong file khai bao class (chong nham class trung ten
    # o package khac — vi du FileSystemEntity cua package:file vs dart:io).
    mem_pat = re.compile(r"(?<![.\w])" + re.escape(member or "") + r"\b\s*[;({=]") if member else None
    # Bo qua package bi loai — khong thi find_container tra ve uri package
    # khong index duoc → yaml crash 'has not been indexed'.
    _excl_c = {x for x in os.environ.get("DYNIFACE_EXCLUDE_PKGS", "").split(",") if x}
    for _cn, root, lib in _DIRS:
        if _cn in _excl_c:
            continue
        try:
            out = subprocess.run(
                ["grep", "-rlE", "--include=*.dart", decl, lib],
                capture_output=True, text=True, timeout=120)
        except Exception:
            continue
        for f in out.stdout.splitlines():
            try:
                # doc TOAN BO file — structs.g.dart (win32) 257KB, SYSTEMTIME o
                # doan sau 200KB bi bo qua → find_container None → entry SAI
                # (dung hint cua file loi) → fix gỡ → augment them lai (ping-pong).
                txt = open(f, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            if pat.search(txt) and (mem_pat is None or mem_pat.search(txt)):
                uri = uri_for(root, f)
                _cache[key] = [uri, f]
                _save()
                return (uri, f)
    _cache[key] = None
    _save()
    return None

def _save():
    json.dump(_cache, open(CACHE, "w"))

def find_member(mem, hint_pkg=None):
    """Tim file khai bao member (field/getter/method) 'mem' (khong tien to).
    hint_pkg = package uu tien truoc (package cua file loi).
    Tra ve (lib_uri, class_name) gan nhat, hoac None."""
    # key v2: bo sung khai bao extension trong scan container gan nhat.
    key = "m2:" + mem + ":" + (hint_pkg or "")
    if key in _cache:
        v = _cache[key]
        return (v[0], v[1]) if v else None
    global _DIRS
    if _DIRS is None:
        _DIRS = search_dirs()
    dirs = _DIRS
    if hint_pkg:
        dirs = ([d for d in _DIRS if d[0] == hint_pkg] +
                [d for d in _DIRS if d[0] != hint_pkg])
    needle = re.escape(mem)
    # container gan nhat: class/mixin/enum/extension type/extension
    decl_re = re.compile(
        r"\b(?:(?:abstract|base|final|sealed|interface)\s+)*"
        r"(?:(?:mixin|enum)\s+)?class\s+([A-Za-z_][\w<>?]*)"
        r"|\b(?:mixin|enum)\s+([A-Za-z_][\w<>?]*)"
        r"|\b(?:extension\s+type|extension)\s+([A-Za-z_][\w]*)")
    for _, root, lib in dirs:
        try:
            out = subprocess.run(
                ["grep", "-rlE", "--include=*.dart",
                 r"\b(get\s+)?" + needle + r"\s*[;({=]",
                 lib],
                capture_output=True, text=True, timeout=120)
        except Exception:
            continue
        for f in out.stdout.splitlines():
            try:
                txt = open(f, encoding="utf-8", errors="replace").read(400000)
            except Exception:
                continue
            for m in re.finditer(r"(?<![.\w])" + needle + r"\b\s*[;({=]", txt):
                # bo qua truy cap member (a.logLevel) — chi nhan KHAI BAO
                # Dong chua phep gan '=' (khong phai '=>') la lenh/local var,
                # khong phai khai bao field → bo qua (chong sai class).
                ls = txt.rfind("\n", 0, m.start()) + 1
                le = txt.find("\n", m.end())
                line = txt[ls:le if le != -1 else len(txt)]
                if "=" in line and "=>" not in line:
                    continue
                # tim container gan nhat phia truoc
                head = txt[: m.start()]
                cm = None
                for cm in decl_re.finditer(head):
                    pass
                if cm:
                    cname = cm.group(1) or cm.group(2) or cm.group(3)
                    uri = uri_for(root, f)
                    _cache[key] = [uri, cname]
                    _save()
                    return (uri, cname)
    _cache[key] = None
    _save()
    return None

def find_toplevel(mem, hint_pkg=None, prefer_pkgs=None):
    """Tim thu vien khai bao MOT MEMBER TOP-LEVEL (ham/getter/hang) — vd
    win32 `void GetSystemInfo(...)`. find_member() khong dung duoc vi no tra
    ve class bao quanh (top-level khong co). Tra ve uri library hoac None.
    Khai bao top-level = dong bat dau o cot 0 (class member luon thut le).
    prefer_pkgs = package duoc import boi FILE LOI (uu tien sau hint_pkg):
    NULL duoc khai bo ca o package:win32 va package:posix — chon theo import
    cua file loi de khong tra ve sai package."""
    key = "top2:%s:%s:%s" % (hint_pkg or "", ",".join(prefer_pkgs or []), mem)
    if key in _cache:
        return _cache[key]
    global _DIRS
    if _DIRS is None:
        _DIRS = search_dirs()
    dirs = _DIRS
    ordered, seen = [], set()
    for pk in ([hint_pkg] if hint_pkg else []) + list(prefer_pkgs or []):
        for d in dirs:
            if d[0] == pk and d[0] not in seen:
                ordered.append(d)
                seen.add(d[0])
    ordered += [d for d in dirs if d[0] not in seen]
    dirs = ordered
    needle = re.escape(mem)
    decl = re.compile(r"^[A-Za-z_][\w<>?,\s.]*\b" + needle + r"\b\s*[;({=]", re.M)
    # Bo qua package bi loai (libs khong duoc host anchor index → entry cho
    # chung khong bao gio hop le — tim thay cung khong dung duoc).
    _excl_t = {x for x in os.environ.get("DYNIFACE_EXCLUDE_PKGS", "").split(",") if x}
    for _tn, root, lib in dirs:
        if _tn in _excl_t:
            continue
        try:
            out = subprocess.run(
                ["grep", "-rlE", "--include=*.dart",
                 r"^[A-Za-z_][^=;]*\b" + needle + r"\b\s*[;({=]", lib],
                capture_output=True, text=True, timeout=120)
        except Exception:
            continue
        for f in out.stdout.splitlines():
            try:
                txt = open(f, encoding="utf-8", errors="replace").read(400000)
            except Exception:
                continue
            if decl.search(txt):
                uri = uri_for(root, f)
                _cache[key] = uri
                _save()
                return uri
    _cache[key] = None
    _save()
    return None


def repair(yaml_path, log_path):
    text = open(log_path, encoding="utf-8", errors="replace").read()
    pat = re.compile(r"Container '([^']+)' not found in library '([^']+)'")
    errs = [(m.group(1), m.group(2)) for m in pat.finditer(text)]
    if not errs:
        print("NO_ERROR")
        return 2
    good = {}
    for cname, _ in errs:
        res = find_container(cname)
        if res:
            good[cname] = res[0]
        else:
            print("WARN: khong tim thay khai bao", cname, file=sys.stderr)
    if not good:
        print("NO_CHANGE")
        return 3
    lines = open(yaml_path, encoding="utf-8").read().splitlines(keepends=True)
    out = []
    changed = 0
    seen_fixed = set()
    for ln in lines:
        mcls = re.search(r"\{library: '([^']+)', class: '([^']+)'", ln)
        if mcls and mcls.group(2) in good:
            cname = mcls.group(2)
            gl = good[cname]
            if mcls.group(1) != gl:
                if cname in seen_fixed:
                    changed += 1
                    continue  # entry trung sau khi sua -> bo
                seen_fixed.add(cname)
                ln = ln.replace(
                    "{library: '" + mcls.group(1) + "', class: '" + cname + "'",
                    "{library: '" + gl + "', class: '" + cname + "'", 1)
                changed += 1
        out.append(ln)
    if changed:
        open(yaml_path, "w", encoding="utf-8").write("".join(out))
        print("REPAIRED %d" % changed)
        return 0
    print("NO_CHANGE")
    return 3

if __name__ == "__main__":
    sys.exit(repair(sys.argv[1], sys.argv[2]))