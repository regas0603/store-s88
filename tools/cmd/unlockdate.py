#!/usr/bin/env python3
"""Ngày unlock của host (BootConfig.appReleaseDate trong loading_kit).

Trước ngày này, máy chưa có cờ boot → chạy demo (không gọi check boot).
dynpub.sh hỏi ngày này mỗi lần build host rồi ghi vào code + commit.

  unlockdate.py show            # in ngày đang ghi trong code (YYYY-MM-DD)
  unlockdate.py set <ngày>      # parse + ghi vào code, in ngày đã ghi (YYYY-MM-DD)
  unlockdate.py parse <ngày>    # chỉ parse, in YYYY-MM-DD

<ngày> nhận:
  2026-10-20   20/10/2026   20-10-2026   20/10 (năm nay)
  +3 / -1 / 0  (số ngày so với hôm nay; 0 = hôm nay)
Lỗi → exit 2, thông báo ra stderr.
"""
import datetime
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DART = os.path.join(ROOT, "loading_kit", "loading_kit", "lib", "flow", "boot_config.dart")
REL = os.path.relpath(DART, ROOT)
LINE_RE = re.compile(
    r"(static final DateTime appReleaseDate = DateTime\()\s*(\d{4})\s*,\s*(\d{1,2})\s*,\s*(\d{1,2})\s*(\);)")


def die(msg):
    print(f"LỖI: {msg}", file=sys.stderr)
    sys.exit(2)


def parse(text, today=None):
    today = today or datetime.date.today()
    s = text.strip()
    if re.fullmatch(r"[+-]?\d{1,4}", s) and (s[0] in "+-" or s == "0"):
        return today + datetime.timedelta(days=int(s))
    try:
        m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", s)
        if m:
            return datetime.date(int(m[1]), int(m[2]), int(m[3]))
        m = re.fullmatch(r"(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{4}))?", s)
        if m:
            return datetime.date(int(m[3] or today.year), int(m[2]), int(m[1]))
    except ValueError as e:
        die(f"ngày không hợp lệ '{s}': {e}")
    die(f"không hiểu ngày '{s}' — dùng 2026-10-20, 20/10/2026, 20/10, +3, -1 hoặc 0")


THU = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật"]


def describe(d, today=None):
    n = (d - (today or datetime.date.today())).days
    rel = "hôm nay" if n == 0 else f"{n} ngày nữa" if n > 0 else f"{-n} ngày trước — máy mở ngay"
    return f"{d.isoformat()} ({THU[d.weekday()]}, {rel})"


def read_src():
    with open(DART, encoding="utf-8") as f:
        src = f.read()
    if len(LINE_RE.findall(src)) != 1:
        die(f"không tìm thấy đúng 1 dòng `appReleaseDate = DateTime(y, m, d);` trong {REL}")
    return src


def show():
    m = LINE_RE.search(read_src())
    return datetime.date(int(m[2]), int(m[3]), int(m[4]))


def write(d):
    src = read_src()
    new = LINE_RE.sub(lambda m: f"{m[1]}{d.year}, {d.month}, {d.day}{m[5]}", src)
    if new != src:
        with open(DART, "w", encoding="utf-8") as f:
            f.write(new)


def main(argv):
    if len(argv) < 1 or argv[0] not in ("show", "set", "parse") or (argv[0] != "show" and len(argv) != 2):
        print(__doc__, file=sys.stderr)
        return 2
    if argv[0] == "show":
        print(show().isoformat())
        return 0
    d = parse(argv[1])
    if argv[0] == "set":
        write(d)
    print(f"  → unlock {describe(d)}", file=sys.stderr)
    print(d.isoformat())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
