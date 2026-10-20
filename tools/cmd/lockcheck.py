#!/usr/bin/env python3
"""Chặn pubspec.lock của host trôi version (CLAUDE.md §1).

Lock tham chiếu = app/pubspec.lock đã commit (resolve với main_app tham chiếu
apps/_reference). main_app của từng app được THÊM package mới (vd flame), nhưng
package đã có trong lock tham chiếu KHÔNG được đổi version — đổi = Flutter khác
version / pub upgrade lỡ tay → ABI host lệch ngoài ý muốn.

  lockcheck.py                      so app/pubspec.lock với bản ở HEAD
  lockcheck.py <ref.lock> <cur.lock>

Chỉ package tầng HOST (configs/abi/host_packages.yaml: sdk / t0 / t1) hoặc chưa
phân tầng mới bị chặn — chúng là ABI host. Package tầng module (module_internal /
module_allowed, vd game_api_client) compile thẳng vào bytecode, không nằm trong
host → đổi version chỉ báo [i], không chặn.

Exit 0 = OK, 1 = package host đổi version, 2 = chưa có lock tham chiếu trong git.
"""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "tools", "cmd", "abicheck"))
from abi import abi_packages, read_lock  # noqa: E402

RED, GRN, YEL, RST = "\033[31m", "\033[32m", "\033[33m", "\033[0m"


def main(a):
    if len(a) == 2:
        ref_path, cur_path = a
        ref_text = open(ref_path, encoding="utf-8").read()
    else:
        cur_path = os.path.join(ROOT, "app", "pubspec.lock")
        r = subprocess.run(["git", "-C", ROOT, "show", "HEAD:app/pubspec.lock"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  {YEL}[WARN]{RST} app/pubspec.lock chưa commit — chưa có lock tham chiếu để so")
            return 2
        ref_text = r.stdout
    tmp = os.path.join(os.path.dirname(cur_path), ".pubspec.lock.ref")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(ref_text)
    try:
        ref, cur = read_lock(tmp), read_lock(cur_path)
    finally:
        os.remove(tmp)
    diff = [(n, ref[n].get("version"), cur[n].get("version")) for n in sorted(ref)
            if n in cur and ref[n].get("version") != cur[n].get("version")]
    _, module, _ = abi_packages()
    changed = [d for d in diff if d[0] not in module]
    for n, a_, b_ in diff:
        if n in module:
            print(f"  [i]    {n}: {a_} → {b_} (tầng module — vào bytecode, không phải ABI host)")
    added = sorted(set(cur) - set(ref))
    if changed:
        for n, a_, b_ in changed:
            print(f"  {RED}[FAIL]{RST} {n}: lock tham chiếu {a_} → hiện tại {b_}")
        print(f"  {RED}[FAIL]{RST} pubspec.lock trôi version — chạy nhầm Flutter (không phải "
              f"../engine/flutter-framework) hoặc pub upgrade lỡ tay. Khôi phục: "
              f"git checkout -- app/pubspec.lock && bash tools/cmd/dynmod.sh pubget")
        return 1
    extra = f" (+{len(added)} package mới của main_app: {', '.join(added[:5])}{'…' if len(added) > 5 else ''})" if added else ""
    print(f"  {GRN}[PASS]{RST} pubspec.lock không đổi version package nào so với lock tham chiếu{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
