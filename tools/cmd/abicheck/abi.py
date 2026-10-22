#!/usr/bin/env python3
"""ABI host ↔ module: kiểm nhiều app (mỗi app 1 main_app) dùng CHUNG 1 bytecode.

Module (../app_package) chạy trên host chỉ khi host giống "ABI đóng băng":
  - cùng engine (revision checkout flutter),
  - cùng dist/dynamic_interface.yaml,
  - cùng version mọi package host module có thể chạm (sdk/t0/t1 của
    configs/abi/host_packages.yaml, trừ package vỏ host như main_app_package),
  - package path (content_kit…) cùng NỘI DUNG lib/.
Không có gì chặn lúc chạy (P5) — lệch = crash khi nạp → kiểm trước bằng tool này.

Lệnh:
  snapshot              chụp ABI host hiện tại → configs/abi/module_abi.json
  host                  so host hiện tại (app/) với ABI đóng băng
  main-app <dir>        giả lập host dùng main_app ở <dir> (resolve trong thư
                        mục tạm, KHÔNG đụng app/) → so ABI + quét import
  app-package [dir] [--accept]
                        kiểm pubspec app_package + packages/*: ràng buộc
                        version phải được bản host đóng băng thoả; báo ràng
                        buộc đổi so với lần chấp nhận trước
                        (configs/abi/app_package_deps.json). --accept = ghi mốc mới.
Exit 0 = OK, 1 = có lỗi, 2 = (app-package) chỉ ràng buộc đổi so với mốc, chưa nhận.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(_HERE, "..", "dyniface"))
import classify_packages as cp  # noqa: E402

ROOT = cp._ROOT
APP = cp.APP
ABI_FILE = os.environ.get("DYNMOD_ABI", os.path.join(ROOT, "configs", "abi", "module_abi.json"))
DEPS_FILE = os.environ.get("DYNMOD_APP_PACKAGE_DEPS", os.path.join(ROOT, "configs", "abi", "app_package_deps.json"))
IFACE = os.environ.get("DYNMOD_IFACE", os.path.join(ROOT, "dist", "dynamic_interface.yaml"))
WORK = os.environ.get("DYNMOD_WORK", os.path.join(os.path.dirname(ROOT), "dart-sdk-build"))
# Flutter DÙNG: ../engine/flutter-framework (gom 1 chỗ), chưa có thì checkout build.
_FF_HOME = os.path.join(os.path.dirname(ROOT), "engine", "flutter-framework")
FF = os.environ.get("DYNMOD_FF") or (
    _FF_HOME if os.access(os.path.join(_FF_HOME, "bin", "flutter"), os.X_OK)
    else os.path.join(WORK, "flutter-framework"))
MODULE_PKG_DIR = os.environ.get("DYNMOD_MODULE_PKG_DIR", os.path.join(os.path.dirname(ROOT), "app_package"))

# Vỏ host: module không bao giờ chạm → đổi thoải mái giữa các app.
HOST_SHELL = {"main_app_package", "loading_kit", "dyn_loader", "dynamic_modules", "app"}
# Thuộc engine (đã có engine_rev).
ENGINE_PKGS = {"flutter", "sky_engine"}

RED, GRN, YEL, RST = "\033[31m", "\033[32m", "\033[33m", "\033[0m"
CYN, BLD, DIM = "\033[36m", "\033[1m", "\033[2m"


def ok(m): print(f"  {GRN}[PASS]{RST} {m}")
def bad(m): print(f"  {RED}[FAIL]{RST} {m}")
def warn(m): print(f"  {YEL}[WARN]{RST} {m}")
def info(m): print(f"  [i]    {m}")


# ---------------------------------------------------------------- dữ liệu
def read_lock(path):
    """{name: {version, source, path?}} từ pubspec.lock."""
    out, cur, in_desc = {}, None, False
    for ln in open(path, encoding="utf-8"):
        m = re.match(r"^  ([A-Za-z0-9_]+):\s*$", ln)
        if m:
            cur = m.group(1)
            out[cur] = {}
            continue
        if not cur:
            continue
        m = re.match(r'^    (version|source): "?([^"\n]+)"?', ln)
        if m:
            out[cur][m.group(1)] = m.group(2).strip()
        m = re.match(r'^      path: "?([^"\n]+)"?', ln)
        if m:
            out[cur]["path"] = m.group(1).strip()
    return out


def dir_hash(d):
    """sha256 nội dung lib/**/*.dart + pubspec.yaml (thứ tự ổn định)."""
    h = hashlib.sha256()
    files = []
    lib = os.path.join(d, "lib")
    for dp, _, fs in os.walk(lib):
        files += [os.path.join(dp, f) for f in fs if f.endswith(".dart")]
    pub = os.path.join(d, "pubspec.yaml")
    if os.path.isfile(pub):
        files.append(pub)
    for f in sorted(files):
        h.update(os.path.relpath(f, d).encode())
        h.update(open(f, "rb").read())
    return h.hexdigest()[:16]


def abi_packages():
    tiers = cp.parse_manifest(cp.MANIFEST)
    host = {n for t in ("sdk", "t0_required", "t1_frozen_pure_dart") for n in tiers.get(t, [])}
    module = set(tiers.get("module_internal", [])) | set(tiers.get("module_allowed", []))
    return sorted(host - HOST_SHELL - ENGINE_PKGS), module, host


def engine_rev():
    try:
        return subprocess.run(["git", "-C", FF, "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except Exception:
        return None


def contract_version():
    p = os.path.join(ROOT, "loading_kit", "content_kit", "lib", "content_kit.dart")
    m = re.search(r"kContentContractVersion\s*=\s*(\d+)", open(p).read()) if os.path.isfile(p) else None
    return int(m.group(1)) if m else None


def compute_abi(lock_path, lock_base_dir):
    names, _, _ = abi_packages()
    lock = read_lock(lock_path)
    pkgs = {}
    for n in names:
        e = lock.get(n)
        if not e:
            continue  # package chỉ có code native (vd *_darwin) không có trong lock thì bỏ
        if e.get("source") == "path" and e.get("path"):
            d = e["path"] if os.path.isabs(e["path"]) else os.path.normpath(os.path.join(lock_base_dir, e["path"]))
            pkgs[n] = "path:" + dir_hash(d)
        else:
            pkgs[n] = e.get("version", "?")
    return {
        "engine_rev": engine_rev(),
        "iface_sha256": hashlib.sha256(open(IFACE, "rb").read()).hexdigest() if os.path.isfile(IFACE) else None,
        "contract_version": contract_version(),
        "packages": pkgs,
    }


def diff_abi(base, cur, label, soft=False):
    """In khác biệt; trả số lỗi. soft=True: lệch version chỉ in WARN (vàng) —
    release registry cho phép mỗi bản build 1 ABI riêng."""
    errs = 0
    bad_ = warn if soft else bad
    if base.get("engine_rev") and cur.get("engine_rev") and base["engine_rev"] != cur["engine_rev"]:
        bad_(f"engine khác: đóng băng {base['engine_rev'][:10]} ≠ {label} {cur['engine_rev'][:10]}")
        errs += 1
    if base.get("contract_version") != cur.get("contract_version"):
        bad_(f"content_kit contract khác: {base.get('contract_version')} ≠ {cur.get('contract_version')}")
        errs += 1
    bp, cp_ = base.get("packages", {}), cur.get("packages", {})
    for n in sorted(set(bp) | set(cp_)):
        a, b = bp.get(n), cp_.get(n)
        if a == b:
            continue
        if a is None:
            warn(f"{n}: MỚI ở {label} ({b}) — chưa có trong ABI đóng băng (ổn nếu module không dùng)")
        elif b is None:
            bad_(f"{n}: có trong ABI ({a}) nhưng {label} KHÔNG còn")
            errs += 1
        else:
            bad_(f"{n}: đóng băng {a} → {label} {b}")
            errs += 1
    if not errs:
        ok(f"{len(cp_)} package host khớp ABI đóng băng (engine, contract v{cur.get('contract_version')})")
    return errs


def load_abi():
    if not os.path.isfile(ABI_FILE):
        bad(f"chưa có {os.path.relpath(ABI_FILE, ROOT)} — chạy: bash tools/cmd/abicheck.sh snapshot")
        sys.exit(1)
    return json.load(open(ABI_FILE))


# ---------------------------------------------------------------- snapshot / host
def cmd_snapshot():
    abi = compute_abi(os.path.join(APP, "pubspec.lock"), APP)
    if not abi["iface_sha256"]:
        warn("chưa có dist/dynamic_interface.yaml — ABI không kèm hash iface (chạy dyniface.sh bootstrap trước)")
    with open(ABI_FILE, "w", encoding="utf-8") as f:
        json.dump(abi, f, indent=2, sort_keys=True)
        f.write("\n")
    ok(f"đã chụp ABI → {os.path.relpath(ABI_FILE, ROOT)} ({len(abi['packages'])} package, "
       f"engine {str(abi['engine_rev'])[:10]}, iface {str(abi['iface_sha256'])[:12]})")
    return 0


def cmd_host():
    print("== ABI host hiện tại (app/) vs đóng băng ==")
    base = load_abi()
    cur = compute_abi(os.path.join(APP, "pubspec.lock"), APP)
    errs = diff_abi(base, cur, "host")
    if base.get("iface_sha256") and cur.get("iface_sha256"):
        if base["iface_sha256"] != cur["iface_sha256"]:
            bad(f"dynamic_interface.yaml khác: {base['iface_sha256'][:12]} ≠ {cur['iface_sha256'][:12]}")
            errs += 1
        else:
            ok(f"dynamic_interface.yaml khớp ({cur['iface_sha256'][:12]})")
    return 1 if errs else 0


# ---------------------------------------------------------------- main-app
DIRECTIVE = re.compile(r"^\s*(?:import|export)\s+([^;]*);", re.M | re.S)


def scan_imports(lib_dir):
    out = set()
    for dp, _, fs in os.walk(lib_dir):
        for f in fs:
            if f.endswith(".dart"):
                src = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
                for m in DIRECTIVE.finditer(src):
                    out.update(re.findall(r"package:([A-Za-z0-9_]+)/", m.group(1)))
    return out


def absolutize_pubspec(text, base):
    """Đổi mọi `path: <tương đối>` thành tuyệt đối (so với base)."""
    def fix(m):
        p = m.group(2).strip().strip("'\"")
        if not os.path.isabs(p):
            p = os.path.normpath(os.path.join(base, p))
        return f"{m.group(1)}{p}"
    return re.sub(r"^(\s+path:\s*)(\S.*)$", fix, text, flags=re.M)


def main_app_closure(proj):
    """Tập package main_app_package kéo vào (kể cả bắc cầu), theo package_config + pubspec."""
    cp.PKG_CONFIG = os.path.join(proj, ".dart_tool", "package_config.json")
    pkgs = cp.load_packages()
    seen, todo = set(), ["main_app_package"]
    while todo:
        n = todo.pop()
        if n not in seen and n in pkgs:
            seen.add(n)
            todo += cp.pubspec_deps(cp.read_pubspec(pkgs[n]))
    return seen - {"main_app_package"}


def cmd_main_app(src):
    src = os.path.abspath(src)
    # apps/<bundleId>/main_app → in bundle id ở đầu cho dễ nhìn.
    parent = os.path.basename(os.path.dirname(src)) if os.path.basename(src) == "main_app" else src
    print(f"{BLD}== {CYN}{parent}{RST}{BLD} — main_app dùng chung bytecode được không? =={RST}")
    print(f"   {DIM}{src}{RST}")
    pub = os.path.join(src, "pubspec.yaml")
    if not os.path.isfile(pub):
        bad(f"không thấy {pub}")
        return 1
    errs = 0
    name = re.search(r"^name:\s*(\S+)", open(pub).read(), re.M)
    if not name or name.group(1) != "main_app_package":
        bad(f"pubspec name phải là main_app_package (đang {name.group(1) if name else '?'})")
        errs += 1

    # 1. import của main_app không được kéo package MODULE vào host.
    _, module, host = abi_packages()
    imports = scan_imports(os.path.join(src, "lib")) - {"main_app_package"}
    leak = sorted(imports & module)
    if leak:
        bad(f"main_app import package của MODULE: {', '.join(leak)} → host chứa bản riêng → "
            f"module nạp lỗi 'already loaded'")
        errs += 1
    new = sorted(imports - host - module - {"flutter"})
    for n in new:
        warn(f"main_app import package mới (ngoài manifest): {n} — vào host; ổn nếu module không dùng")
    if not leak:
        ok(f"main_app import {len(imports)} package, không chạm package module")

    # 2. Resolve host với main_app này trong thư mục tạm (giữ pubspec.lock host).
    base = load_abi()
    tmp = tempfile.mkdtemp(prefix="abicheck_")
    try:
        text = open(os.path.join(APP, "pubspec.yaml"), encoding="utf-8").read()
        text = re.sub(r"(  main_app_package:\s*\n\s+path:\s*)\S+", lambda m: m.group(1) + src, text)
        text = absolutize_pubspec(text, APP)
        open(os.path.join(tmp, "pubspec.yaml"), "w").write(text)
        shutil.copy(os.path.join(APP, "pubspec.lock"), os.path.join(tmp, "pubspec.lock"))
        flutter = os.path.join(FF, "bin", "flutter")
        if not os.access(flutter, os.X_OK):
            # KHÔNG lùi về flutter trong PATH (CLAUDE.md §1): khác version → kết quả
            # resolve sai, so ABI vô nghĩa.
            bad(f"không thấy {flutter} — chạy: bash tools/setup.sh")
            return 1
        r = subprocess.run([flutter, "pub", "get", "--directory", tmp], capture_output=True, text=True)
        if r.returncode != 0:
            bad("pub get với main_app này THẤT BẠI (xung đột version với host):")
            print("\n".join("         " + l for l in (r.stdout + r.stderr).strip().splitlines()[-12:]))
            return 1
        # Dep bắc cầu cũng vào host: package mới có thể kéo theo package của MODULE.
        # Lock host có thể chứa sẵn package module (mode module-only) → tính closure
        # của riêng main_app_package từ pubspec từng package.
        trans = sorted((main_app_closure(tmp) & module) - set(leak))
        if trans:
            bad(f"main_app kéo bắc cầu package của MODULE: {', '.join(trans)} → host chứa bản riêng → "
                f"module nạp lỗi 'already loaded'")
            errs += 1
        cur = compute_abi(os.path.join(tmp, "pubspec.lock"), tmp)
        cur["iface_sha256"] = base.get("iface_sha256")  # iface không phụ thuộc main_app (main_app không lộ)
        soft = os.environ.get("ABICHECK_ALLOW_ABI_DIFF") == "1"
        d = diff_abi(base, cur, "host+main_app", soft=soft)
        if d and soft:
            # Release registry: mỗi bản build 1 ABI riêng — lệch host tham chiếu
            # là bình thường, tool tự tính bản build này chạy được tới patch nào.
            warn(f"{d} khác biệt version package host so với ABI tham chiếu → app này có ABI riêng "
                 f"(registry tự tính patch chạy được)")
        else:
            errs += d
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    print(f"{BLD}== {CYN}{parent}{RST}{BLD}: {GRN + 'OK — dùng chung bytecode được' if not errs else RED + f'{errs} lỗi — KHÔNG dùng chung được'}{RST}{BLD} =={RST}")
    return 1 if errs else 0


# ---------------------------------------------------------------- app-package
def pubspec_constraints(path):
    """{dep: constraint} trong `dependencies:` (bỏ sdk/path/git)."""
    out, inside, cur, block = {}, False, None, {}
    lines = open(path, encoding="utf-8").read().splitlines()

    def flush():
        if cur is None:
            return
        if "path" in block or "sdk" in block or "git" in block:
            return
        if "version" in block:
            out[cur] = block["version"]
        elif "value" in block:
            out[cur] = block["value"]

    for ln in lines:
        raw = ln.split("#")[0].rstrip()
        if not raw.strip():
            continue
        if re.match(r"^\S", raw):
            flush()
            cur, block = None, {}
            inside = raw.strip() == "dependencies:"
            continue
        if not inside:
            continue
        m = re.match(r"^  ([A-Za-z0-9_]+):\s*(.*)$", raw)
        if m:
            flush()
            cur, block = m.group(1), {}
            v = m.group(2).strip().strip("'\"")
            if v:
                block["value"] = v
            continue
        m = re.match(r"^\s{4,}(version|path|sdk|git|hosted):\s*(.*)$", raw)
        if m and cur:
            block[m.group(1)] = m.group(2).strip().strip("'\"")
    flush()
    return out


def parse_ver(v):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$", v.strip())
    if not m:
        return None
    pre = m.group(4)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), 0 if pre else 1, pre or "")


def satisfies(version, constraint):
    """Hỗ trợ: any, ^x.y.z, x.y.z, >=a <b, >a, <=a… (ghép bằng dấu cách)."""
    v = parse_ver(version)
    c = constraint.strip()
    if v is None or c in ("", "any"):
        return True
    if c.startswith("^"):
        lo = parse_ver(c[1:])
        if lo is None:
            return True
        if lo[0] > 0:
            hi = (lo[0] + 1, 0, 0, 0, "")
        elif lo[1] > 0:
            hi = (0, lo[1] + 1, 0, 0, "")
        else:
            hi = (0, 0, lo[2] + 1, 0, "")
        return lo <= v < hi
    conds = re.findall(r"(>=|<=|>|<)?\s*(\d+\.\d+\.\d+[0-9A-Za-z.+-]*)", c)
    if not conds:
        return True
    for op, s in conds:
        w = parse_ver(s)
        if w is None:
            continue
        if (op == ">=" and not v >= w) or (op == "<=" and not v <= w) or \
           (op == ">" and not v > w) or (op == "<" and not v < w) or (op == "" and v != w):
            return False
    return True


def exposed_in_iface():
    """Package host đang LỘ cho module (mức library, section callable của iface)."""
    if not os.path.isfile(IFACE):
        return None
    y = open(IFACE, encoding="utf-8").read()
    sec = y.split("\ncallable:", 1)[-1].split("\ndynamically-callable:", 1)[0]
    return set(re.findall(r"library: 'package:([A-Za-z0-9_]+)/", sec))


def check_exposed(pkg_dir):
    """Module import TRỰC TIẾP package host chưa lộ → compile fail → phải build
    lại host (thêm vào expose-packages của configs/abi/dynamic_interface.extra.yaml).
    Báo sớm, không cần chờ dart2bytecode."""
    exposed = exposed_in_iface()
    if exposed is None:
        warn("chưa có dist/dynamic_interface.yaml — bỏ qua kiểm package host đã lộ")
        return 0
    import importlib
    gdi = importlib.import_module("gen_dynamic_interface")
    gdi.MODULE_ENTRY = os.path.join(pkg_dir, "modules", "home_content.dart")
    if not os.path.isfile(gdi.MODULE_ENTRY):
        warn("chưa áp templates/module (modules/home_content.dart) — bỏ qua kiểm package host đã lộ")
        return 0
    _, module, host = abi_packages()
    direct = gdi.module_direct_packages(host, module) - ENGINE_PKGS
    missing = sorted(direct - exposed)
    if missing:
        for n in missing:
            bad(f"module import package host '{n}' nhưng host CHƯA lộ → compile sẽ lỗi; "
                f"cần thêm vào expose-packages (configs/abi/dynamic_interface.extra.yaml) + BUILD LẠI HOST")
        return len(missing)
    ok(f"module import {len(direct)} package host — đều đã lộ (không cần build lại host)")
    return 0


def cmd_app_package(pkg_dir, accept):
    pkg_dir = os.path.abspath(pkg_dir)
    print(f"== app_package {pkg_dir} — có đòi version khác host đóng băng không? ==")
    base = load_abi()
    frozen = base.get("packages", {})
    files = [os.path.join(pkg_dir, "pubspec.yaml")]
    pk = os.path.join(pkg_dir, "packages")
    if os.path.isdir(pk):
        files += sorted(os.path.join(pk, d, "pubspec.yaml") for d in os.listdir(pk)
                        if os.path.isfile(os.path.join(pk, d, "pubspec.yaml")))
    current, errs, drift = {}, 0, False
    for f in files:
        rel = os.path.relpath(f, pkg_dir)
        cons = pubspec_constraints(f)
        current[rel] = cons
        for dep, c in sorted(cons.items()):
            ver = frozen.get(dep)
            if ver is None or ver.startswith("path:"):
                continue  # không phải package host (module tự mang) / package path
            if not satisfies(ver, c):
                bad(f"{rel}: {dep} {c} — host đóng băng {ver} KHÔNG thoả → "
                    f"pub get host sẽ nâng/vỡ, bytecode lệch host đã phát hành")
                errs += 1
    if not errs:
        ok(f"{sum(len(v) for v in current.values())} ràng buộc trong {len(files)} pubspec đều thoả version host đóng băng")
    errs += check_exposed(pkg_dir)

    # Đổi so với lần chấp nhận trước (AI tự nâng version…).
    if os.path.isfile(DEPS_FILE) and not accept:
        old = json.load(open(DEPS_FILE))
        changes = []
        for rel in sorted(set(old) | set(current)):
            a, b = old.get(rel, {}), current.get(rel, {})
            for dep in sorted(set(a) | set(b)):
                if a.get(dep) != b.get(dep):
                    tag = "host" if dep in frozen else "module"
                    changes.append(f"{rel}: {dep} {a.get(dep, '(chưa có)')} → {b.get(dep, '(bỏ)')}  [{tag}]")
        if changes:
            # FAIL (exit 2, khác vi phạm ABI = exit 1): đổi ràng buộc package host
            # chưa được nhận = có thể đổi ABI host → phải duyệt qua dynpub [11].
            drift = True
            bad(f"{len(changes)} ràng buộc version ĐỔI so với mốc đã chấp nhận "
                 f"({os.path.relpath(DEPS_FILE, ROOT)}):")
            for c in changes:
                print("         " + c)
            print("         → xem lại; đúng ý thì: bash tools/dynpub.sh → [11] (nhận đổi package host)")
        else:
            ok("ràng buộc version không đổi so với mốc đã chấp nhận")
    if accept or not os.path.isfile(DEPS_FILE):
        if errs:
            bad("còn ràng buộc vi phạm ABI — KHÔNG ghi mốc")
        else:
            with open(DEPS_FILE, "w", encoding="utf-8") as f:
                json.dump(current, f, indent=2, sort_keys=True)
                f.write("\n")
            ok(f"đã ghi mốc ràng buộc → {os.path.relpath(DEPS_FILE, ROOT)}")
    return 1 if errs else (2 if drift else 0)


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = a[0], a[1:]
    if cmd == "snapshot":
        return cmd_snapshot()
    if cmd == "host":
        return cmd_host()
    if cmd == "main-app":
        return cmd_main_app(rest[0] if rest else os.path.join(ROOT, "apps", "_reference", "main_app"))
    if cmd == "app-package":
        accept = "--accept" in rest
        dirs = [x for x in rest if x != "--accept"]
        return cmd_app_package(dirs[0] if dirs else MODULE_PKG_DIR, accept)
    print(f"lệnh lạ: {cmd}\n{__doc__}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
