#!/usr/bin/env python3
# Augment dynamic_interface.yaml tu loi dart2bytecode --validate.
# - "Cannot invoke member 'M' ... list member 'C.M' as callable"
# - "Cannot use class 'C' as a type ... as can-be-used-as-type"
# - "Cannot extend/override ... as extendable / can-be-overridden"
# Library suy ra tu duong dan file loi qua package_config.json.
import json, os, re, sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import repair_containers as rl

yaml_path, log_path, pkg_config = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(log_path, encoding="utf-8", errors="replace").read()
pc = json.load(open(pkg_config))
APP = os.path.dirname(os.path.dirname(os.path.abspath(pkg_config)))
# rootUri trong package_config.json tuong doi voi THU MUC CHUA FILE
# (app/.dart_tool/) — khong phai APP. Join voi APP se lech 1 cap
# (../../../app_package -> Documents/app_package) → lib_of() tra None cho
# moi file ngoai repo → augment khong them duoc entry → loop ping-pong.
_PKG_DIR = os.path.dirname(os.path.abspath(pkg_config))
roots = []
for p in pc["packages"]:
    ru = p["rootUri"].replace("file://", "")
    if not ru.startswith("/"):
        ru = os.path.normpath(os.path.join(_PKG_DIR, ru))
    roots.append((p["name"], ru))
APP = os.path.dirname(os.path.dirname(os.path.abspath(pkg_config)))

def lib_of(path):
    path = path.strip()
    if not path.startswith("/"):
        path = os.path.normpath(os.path.join(APP, path))
    for name, root in sorted(roots, key=lambda x: -len(x[1])):
        if root.endswith("/lib") and path.startswith(root[:-4] + "/"):
            return "package:%s/%s" % (name, path[len(root) - 4 + 1:].lstrip("/"))
        if path.startswith(root + "/"):
            rel = path[len(root) + 1:]
            if rel.startswith("lib/"):
                return "package:%s/%s" % (name, rel[4:])
            if "/lib/" in rel:
                return "package:%s/%s" % (name, rel.split("/lib/", 1)[1])
    return None

err_line = re.compile(r"^(.+?):\d+:\d+: Error: (.*)$", re.M)

def _imports_of(path):
    """package duoc import/export boi FILE LOI — huong dan find_toplevel chon
    dung package khi ten member trung ten o nhieu package (NULL khai bau ca
    package:win32 lan package:posix — chon theo import cua file loi)."""
    p = path.strip()
    if not p.startswith("/"):
        p = os.path.normpath(os.path.join(APP, p))
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            txt = f.read(20000)
    except OSError:
        return []
    out = []
    for m2 in re.finditer(r"(?:import|export)\s+'package:([^/]+)/", txt):
        if m2.group(1) not in out:
            out.append(m2.group(1))
    return out

# Package module BIEN DICH DUOC nhung anchor khong co → force-load that bai
# ('has not been indexed'; win32 la thu vien Windows-only cua cac *_windows
# file ma yaml khong duoc phep chua). Augment phai SKIP entry cho cac package
# nay thay vi resolve them (resolve dung cung vo ich → crash o buoc force-load).
EXCLUDE_TOP = {"path_provider_windows"}
# Export cho repair_containers (find_container/find_toplevel) — khong resolve
# decl trong package bi loai (libs khong duoc host anchor index).
os.environ["DYNIFACE_EXCLUDE_PKGS"] = ",".join(sorted(EXCLUDE_TOP))
# Blacklist lib khong index duoc (fix_disambiguation ghi khi gap crash
# 'has not been indexed') — bo qua khi augment.
_BAD_LIBS = set()
try:
    _BAD_LIBS = {l.strip() for l in open("/tmp/dyniface_bad_libs.txt") if l.strip()}
except OSError:
    pass
# Blacklist (library|container) da lam validator CRASH "Container 'X' not
# found in library 'L'" (fix_disambiguation ghi). Entry do append library cua
# FILE LOI (khong phai library chua container) → them lai = ping-pong vo han
# (fix gỡ mỗi vòng, augment them lại).
_BAD_CONTAINERS = set()
try:
    _BAD_CONTAINERS = {l.strip() for l in
                       open("/tmp/dyniface_bad_containers.txt") if l.strip()}
except OSError:
    pass
SECT = {
    "callable": "callable",
    "can-be-used-as-type": "can-be-used-as-type",
    "extendable": "extendable",
    "can-be-overridden": "can-be-overridden",
}

want = []
for m in err_line.finditer(text):
    path, msg = m.group(1), m.group(2)
    win = text[m.start():m.start() + 400]
    sect = None
    lib0 = lib_of(path)
    pkg0 = lib0.split("/")[0].replace("package:", "") if lib0 else None
    # Error nam TRONG 1 package bi loai (win32_registry/path_provider_windows:
    # module bien dich duoc nhung anchor khong co → force-load se crash 'not
    # indexed', them entry vo ich) → SKIP ngay.
    if pkg0 in EXCLUDE_TOP:
        continue
    mm = re.search(r"list member '([^']+)' as callable", win)
    if mm:
        want.append(("callable", lib_of(path), mm.group(1)))
        continue
    # "Cannot invoke constructor 'C' / 'C.named' ... list constructor ... as
    # callable" — yaml callable can {class, member: ''} (ctor unnamed) hoac
    # {class, member: 'named'}; entry {class} khong chap constructor → loop
    # stall vi augment cu bo qua loi nay.
    mc = re.search(r"list constructor '([^']+)' as callable", win)
    if mc:
        want.append(("callable", lib0, "ctor:" + mc.group(1)))
        continue
    for kind, s in [("can-be-used-as-type", "can-be-used-as-type"),
                    ("extendable", "extendable"),
                    ("can-be-overridden", "can-be-overridden")]:
        mm = re.search(r"list member '([^']+)' as " + kind, win)
        if mm:
            want.append((s, lib_of(path), "m:" + mm.group(1)))
            break
        mm = re.search(r"list class '([^']+)' as " + kind, win)
        if mm:
            res = rl.find_container(mm.group(1))
            want.append((s, res[0] if res else lib_of(path), "cls:" + mm.group(1)))
            break
    mm = re.search(r"Try listing '([^']+)' as 'dynamically-callable'", win)
    if mm:
        sel = mm.group(1)  # 'get:logLevel' hoac 'logLevel'
        bare = sel.split(":", 1)[1] if ":" in sel else sel
        hint = None
        _l0 = lib_of(path)
        if _l0:
            hint = _l0.split("/")[0].replace("package:", "")
        res = rl.find_member(bare, hint)
        if res:
            want.append(("dynamically-callable", res[0], "c:" + res[1] + "." + sel))
        else:
            print("WARN: khong tim thay member cho selector", sel, file=sys.stderr)
        continue

if not want:
    # KHONG UNPREFIX o day nua — fix_disambiguation.py xu ly cung pattern
    # (missclass/UNPREFIX) nhung dung NGHICH voi augment (prefix get:/set:) →
    # 2 script dong thoi chay moi vong = ping-pong vo han. Day NO_ERROR de
    # cmd_loop chay fix_disambiguation truc tiep.
    print("NO_ERROR")
    sys.exit(2)

yaml = open(yaml_path, encoding="utf-8").read()
added = 0
seen = set()
for sect, lib, ident in want:
    if not lib:
        print("WARN: khong suy ra library cho", ident, file=sys.stderr)
        continue
    if lib in _BAD_LIBS:
        print("WARN: bo qua entry cho library khong index:", lib, ident, file=sys.stderr)
        continue
    key = (sect, lib, ident)
    if key in seen:
        continue
    seen.add(key)
    if ident.startswith("m:"):  # member 'C.M' cho section member-level
        cls, mem = ident[2:].rsplit(".", 1)
        # resolve container VOI class that su khai bao (dart:core/dart:io/
        # SDK hoac pub khac) — lib cua file loi chi la HINT, de tranh entry
        # tro sai lib (vi du Stopwatch khai bao o dart:core nhung loi o clock).
        # Fallback: container khong tim thay KHI KE MEMBER (part file khac) →
        # lay theo container thoi; cuoi cung moi dung lib cua file loi.
        res = rl.find_container(cls, mem) or rl.find_container(cls)
        mlib = res[0] if res else lib
        entry = "  - {library: '%s', class: '%s', member: '%s'}" % (mlib, cls, mem)
    elif ident.startswith("ctor:"):  # constructor 'C' / 'C.named'
        # Constructor khong phai member co ten trong source (unnamed = '') →
        # resolve boi CONTAINER thoi; entry {class} (khong member) khong
        # chap constructor (testcase yaml: {class: 'C4', member: ''}).
        nm = ident[5:]
        cls, _, cmem = nm.partition(".")
        res = rl.find_container(cls)
        mlib = res[0] if res else lib
        entry = "  - {library: '%s', class: '%s', member: '%s'}" % (mlib, cls, cmem)
    elif ident.startswith("c:"):  # dynamically-callable class member
        cls, sel = ident[2:].split(".", 1)
        # Bo tien to get:/set: — field chi can ten tran; getter/setter-only
        # validator se bao 'Did you mean get:X' va fix_disambiguation tien to.
        bare_sel = sel.split(":", 1)[1] if ":" in sel else sel
        entry = "  - {library: '%s', class: '%s', member: '%s'}" % (lib, cls, bare_sel)
    elif "." in ident:  # member 'C.M'
        cls, mem = ident.rsplit(".", 1)
        res = rl.find_container(cls, mem) or rl.find_container(cls)
        mlib = res[0] if res else lib
        entry = "  - {library: '%s', class: '%s', member: '%s'}" % (mlib, cls, mem)
    elif ident.startswith("cls:"):  # 'list class X as <kind>' → entry class
        res = rl.find_container(ident[4:])
        mlib = res[0] if res else lib
        entry = "  - {library: '%s', class: '%s'}" % (mlib, ident[4:])
    elif ":" in ident:
        cls, mem = ident.split(":", 1)
        res = rl.find_container(cls, mem) or rl.find_container(cls)
        mlib = res[0] if res else lib
        entry = "  - {library: '%s', class: '%s', member: '%s'}" % (mlib, cls, mem)
    else:
        # Top-level member (ham/getter/hang cua thu vien) — KHONG phai class.
        # find_member() chi nhin class member → dung find_toplevel().
        # Entry {class: X} hoac member: SAI library lam validator CRASH cung
        # (getClass/getMember throw) → bo qua neu khong resolve duoc, dong
        # thoi SKIP ca package bi loai khoi interface (force-load se that bai).
        if lib and lib.split("/")[0].replace("package:", "") in EXCLUDE_TOP:
            print("WARN: bo qua entry cho package bi loai:", ident, file=sys.stderr)
            continue
        hint = lib.split("/")[0].replace("package:", "") if lib else None
        # prefer_pkgs = package import boi FILE LOI — chong chon sai package
        # cung ten member (NULL: win32 vs posix).
        lib2 = rl.find_toplevel(ident, hint, prefer_pkgs=_imports_of(path))
        if not lib2:
            print("WARN: khong resolve duoc top-level member", ident, file=sys.stderr)
            continue
        if lib2 and lib2.split("/")[0].replace("package:", "") in EXCLUDE_TOP:
            print("WARN: bo qua entry cho package bi loai:", ident, file=sys.stderr)
            continue
        entry = "  - {library: '%s', member: '%s'}" % (lib2, ident)
    # blacklist (library|container) da CRASH validator "Container 'X' not
    # found" — append library cua FILE LOI la SAI; khong them lai (nguon goc
    # ping-pong: fix gỡ mỗi vòng → augment them lại).
    _mb = re.search(r"library: '([^']+)', class: '([^']+)'", entry)
    if _mb and (_mb.group(1) + "|" + _mb.group(2)) in _BAD_CONTAINERS:
        print("WARN: bo qua entry blacklist (container khong co trong anchor):",
              entry, file=sys.stderr)
        continue
    # library PHU thuoc (da resolve duoc nhung khong co trong anchor) cung
    # phai bo qua — khong thi crash 'has not been indexed' → fix gỡ → them lai.
    _ml = re.search(r"library: '([^']+)'", entry)
    if _ml and _ml.group(1) in _BAD_LIBS:
        print("WARN: bo qua entry cho library khong index:", entry, file=sys.stderr)
        continue
    if entry in yaml or ("library: '%s'" % lib) in yaml and entry.replace("member: '", "member: 'get:") in yaml:
        continue
    # chong churn: entry da co dang get:/set: (fix_iface2 da tien to) thi bo qua
    if "member: 'get:" in entry or "member: 'set:" in entry:
        alt = re.sub(r"member: '(get:|set:)", "member: '", entry)
        if alt in yaml:
            continue
    # chen vao cuoi section
    m = re.search(r"(" + sect + r":\n)(.*?)(\n[A-Za-z-]+:|\Z)", yaml, re.S)
    if not m:
        print("WARN: khong thay section", sect, file=sys.stderr)
        continue
    body = m.group(2).rstrip("\n")
    new_body = body + "\n" + entry
    yaml = yaml[:m.start(2)] + new_body + yaml[m.start(3):] if m.group(3) else yaml[:m.start(2)] + new_body
    added += 1

if added:
    open(yaml_path, "w", encoding="utf-8").write(yaml)
    print("AUGMENTED %d" % added)
    sys.exit(0)

# Khong UNPREFIX o day — fix_disambiguation xu ly (xem ghi chu o nhánh `if not want`).
print("NO_CHANGE")
sys.exit(3)
