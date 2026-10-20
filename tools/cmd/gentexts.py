#!/usr/bin/env python3
"""Sinh text host từ nguồn CHUNG `configs/texts.json`:

  1. `loading_kit/loading_kit/lib/core/text_keys.dart` — hằng index (TK.*),
     code tra text bằng SỐ, binary không còn tên key.
  2. Khối `texts` TOKEN-HOÁ trong mọi `configs/apps/<bundleId>.json`:
     token = fnv1a64("<bundleId>:<index>")[:12] → mỗi app một token khác,
     nên dump JSON của app không lộ tên key; app tự tính lại token lúc chạy
     (cùng thuật toán trong remote_texts.dart).

Chạy: python3 tools/cmd/gentexts.py   (thêm --check để chỉ kiểm, không ghi)

THỨ TỰ key trong `configs/texts.json` = index: chỉ THÊM ở cuối.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "configs", "texts.json")
TK_DART = os.path.join(
    ROOT, "loading_kit", "loading_kit", "lib", "core", "text_keys.dart")
APPS_GLOB = os.path.join(ROOT, "configs", "apps", "*.json")

TOKEN_LEN = 12  # 48-bit hex, đủ tránh đụng cho vài chục key.


def fnv1a_token(bundle_id, index):
    """FNV-1a 64-bit của "<bundleId>:<index>" → 12 hex đầu.

    PHẢI khớp _token() trong remote_texts.dart. Đổi ở đây là đổi cả bên kia."""
    h = 0xCBF29CE484222325
    for b in f"{bundle_id}:{index}".encode("utf-8"):
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"[:TOKEN_LEN]


def camel(snake):
    head, *tail = snake.split("_")
    return head + "".join(w[:1].upper() + w[1:] for w in tail)


def load_keys():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    keys = data.get("keys")
    if not isinstance(keys, dict) or not keys:
        sys.exit(f"[gentexts] {SRC}: thiếu object `keys` không rỗng")
    names = list(keys.keys())
    dups = {c for c in map(camel, names) if list(map(camel, names)).count(c) > 1}
    if dups:
        sys.exit(f"[gentexts] key camelCase trùng nhau: {dups}")
    return keys, names


def render_tk(names):
    lines = [
        "// GENERATED bởi tools/cmd/gentexts.py từ configs/texts.json — ĐỪNG SỬA TAY.",
        "//",
        "// Index của từng text host. remote_texts.dart tra text bằng các hằng này",
        "// (SỐ, không chuỗi) → binary không chứa tên key. Thêm key = thêm vào",
        "// configs/texts.json (ở CUỐI) rồi chạy lại script.",
        "abstract final class TK {",
        "  TK._();",
        "",
    ]
    for i, name in enumerate(names):
        lines.append(f"  static const int {camel(name)} = {i};")
    lines.append("")
    lines.append(f"  /// Tổng số text key.")
    lines.append(f"  static const int count = {len(names)};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def tokens_for(bundle_id, keys):
    out = {}
    for i, (name, value) in enumerate(keys.items()):
        tok = fnv1a_token(bundle_id, i)
        if tok in out:
            sys.exit(f"[gentexts] ĐỤNG token ở {bundle_id} index {i} ({name}) "
                     f"— tăng TOKEN_LEN")
        out[tok] = value
    return out


def main():
    check = "--check" in sys.argv[1:]
    keys, names = load_keys()

    tk = render_tk(names)
    changed = []
    if not os.path.exists(TK_DART) or open(TK_DART, encoding="utf-8").read() != tk:
        changed.append(os.path.relpath(TK_DART, ROOT))
        if not check:
            os.makedirs(os.path.dirname(TK_DART), exist_ok=True)
            with open(TK_DART, "w", encoding="utf-8") as f:
                f.write(tk)

    for path in sorted(glob.glob(APPS_GLOB)):
        bundle_id = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
        new_texts = tokens_for(bundle_id, keys)
        if cfg.get("texts") == new_texts:
            continue
        changed.append(os.path.relpath(path, ROOT))
        if not check:
            cfg["texts"] = new_texts
            with open(path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, sort_keys=True, ensure_ascii=False)
                f.write("\n")

    if check:
        if changed:
            print("[gentexts] CẦN sinh lại:\n  " + "\n  ".join(changed))
            sys.exit(1)
        print("[gentexts] OK — text đã khớp nguồn")
    else:
        print(f"[gentexts] {len(names)} key → {TOKEN_LEN}-hex token/app")
        print("[gentexts] cập nhật:\n  " + "\n  ".join(changed) if changed
              else "[gentexts] không đổi gì")


if __name__ == "__main__":
    main()
