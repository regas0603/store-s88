#!/usr/bin/env python3
"""Trạng thái CỤC BỘ (không commit) có khớp repo không — để mọi máy chạy check
như nhau sau `git pull`.

Hai thứ sinh ra ở từng máy, git ignore, dễ cũ sau khi máy khác đổi ABI host:
  - app/.dart_tool/package_config.json  (pub get)          → lệnh `pkgconfig`
  - dist/dynamic_interface.yaml         (dyniface bootstrap) → lệnh `iface`

  localstate.py pkgconfig     exit 1 nếu package_config lệch app/pubspec.lock
  localstate.py iface         exit 1 nếu iface chưa sinh từ đầu vào hiện tại
  localstate.py iface-write   ghi dấu đầu vào (dyniface.sh bootstrap gọi khi xong)

tools/check.sh bước 0 dùng 2 lệnh đầu để tự pub get / bootstrap lại.
"""
import hashlib
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "tools", "cmd", "abicheck"))
from abi import read_lock  # noqa: E402

APP = os.environ.get("DYNMOD_APP", os.path.join(ROOT, "app"))
LOCK = os.path.join(APP, "pubspec.lock")
PKG_CONFIG = os.path.join(APP, ".dart_tool", "package_config.json")
IFACE = os.environ.get("DYNMOD_IFACE", os.path.join(ROOT, "dist", "dynamic_interface.yaml"))
STAMP = IFACE + ".inputs"
MODULE_PKG = os.path.abspath(os.path.join(ROOT, "..", "app_package"))
SKIP_DIRS = {".dart_tool", "build", ".git", "__pycache__", "android", "ios", "macos",
             "linux", "windows", "web", ".idea"}
RED, GRN, YEL, RST = "\033[31m", "\033[32m", "\033[33m", "\033[0m"


def pkgconfig():
    if not os.path.isfile(PKG_CONFIG):
        print(f"  {YEL}[STALE]{RST} chưa có {os.path.relpath(PKG_CONFIG, ROOT)} (chưa pub get)")
        return 1
    lock = read_lock(LOCK)
    pc = {p["name"]: p["rootUri"] for p in json.load(open(PKG_CONFIG))["packages"]}
    app_name = next((ln.split(":", 1)[1].strip() for ln in open(os.path.join(APP, "pubspec.yaml"))
                     if ln.startswith("name:")), None)
    bad = []
    for n, info in sorted(lock.items()):
        if n not in pc:
            bad.append(f"{n} {info.get('version')}: có trong lock, thiếu trong package_config")
        elif info.get("source") == "hosted" and \
                os.path.basename(pc[n].rstrip("/")) != f"{n}-{info.get('version')}":
            bad.append(f"{n}: lock {info.get('version')}, package_config {os.path.basename(pc[n])}")
    bad += [f"{n}: có trong package_config, không còn trong lock"
            for n in sorted(set(pc) - set(lock) - {app_name})]
    if bad:
        print(f"  {YEL}[STALE]{RST} package_config lệch app/pubspec.lock ({len(bad)} package):")
        for b in bad[:10]:
            print(f"         {b}")
        if len(bad) > 10:
            print(f"         … và {len(bad) - 10} package nữa")
        return 1
    print(f"  {GRN}[PASS]{RST} package_config khớp app/pubspec.lock ({len(lock)} package)")
    return 0


def _files():
    """Mọi đầu vào của dyniface bootstrap (anchor + gen_dynamic_interface)."""
    yield LOCK
    yield PKG_CONFIG
    yield os.path.join(ROOT, "configs", "flutter.json")
    yield os.path.join(ROOT, "tools", "cmd", "dyniface.sh")
    for d, exts in ((os.path.join(ROOT, "configs", "abi"), (".yaml", ".json")),
                    (os.path.join(ROOT, "tools", "cmd", "dyniface"), (".py", ".json")),
                    (os.path.join(APP, "lib"), (".dart",)),
                    (os.path.join(ROOT, "templates", "module"), None),
                    (MODULE_PKG, (".dart", "pubspec.yaml"))):
        for root, dirs, files in os.walk(d):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
            for f in sorted(files):
                if exts is None or f.endswith(exts):
                    yield os.path.join(root, f)


def inputs_hash():
    h = hashlib.sha256()
    for p in _files():
        if os.path.isfile(p):
            h.update(os.path.relpath(p, os.path.dirname(ROOT)).encode() + b"\0")
            with open(p, "rb") as f:
                h.update(hashlib.sha256(f.read()).digest())
    return h.hexdigest()


def iface():
    rel = os.path.relpath(IFACE, ROOT)
    if not os.path.isfile(IFACE):
        print(f"  {YEL}[STALE]{RST} chưa có {rel}")
        return 1
    old = open(STAMP).read().strip() if os.path.isfile(STAMP) else ""
    if old != inputs_hash():
        why = "đầu vào đã đổi (lock / configs/abi / app / app_package / tool)" if old \
            else "chưa có dấu đầu vào (sinh bởi tool cũ hoặc tay)"
        print(f"  {YEL}[STALE]{RST} {rel}: {why}")
        return 1
    print(f"  {GRN}[PASS]{RST} {rel} sinh từ đầu vào hiện tại")
    return 0


def iface_write():
    with open(STAMP, "w") as f:
        f.write(inputs_hash() + "\n")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    fn = {"pkgconfig": pkgconfig, "iface": iface, "iface-write": iface_write}.get(cmd)
    if not fn:
        print(__doc__)
        sys.exit(2)
    sys.exit(fn())
