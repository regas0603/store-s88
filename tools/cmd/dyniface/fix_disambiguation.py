#!/usr/bin/env python3
# Sua dist/dynamic_interface.yaml dua tren log anchor:
#  1) member disambiguation: "A member with disambiguated name 'N' was not
#     found in class 'C' in library 'L'" -> tien to 'get:'/'set:' theo goi y.
#  2) container: "Container 'X' not found in library 'L'" -> xoa class/phan tu.
import re, sys

yaml_path, log_path = sys.argv[1], sys.argv[2]
text = open(log_path, encoding="utf-8", errors="replace").read()

pat = re.compile(
    r"A member with disambiguated name '(?P<name>[^']+)' was not found "
    r"(?:in class '(?P<cls>[^']+)' )?in (?:top-level of )?library '(?P<lib>[^']+)'")
sug = re.compile(r"Did you mean '([^']+)' or '([^']+)'")
cont_pat = re.compile(r"Container '([^']+)' not found in library '([^']+)'")
# Library khong duoc host anchor index (posix/path_provider_windows/...) —
# them entry vao yml la CRASH 'has not been indexed'. Gỡ entry + ghi blacklist
# de augment bo qua lan sau (blacklist persist qua cac vong loop).
idx_pat = re.compile(r"The library '([^']+)' has not been indexed")
BAD_LIBS_FILE = "/tmp/dyniface_bad_libs.txt"
# (library|container) da CRASH validator — augment bo qua khi them lai.
BAD_CONTAINERS_FILE = "/tmp/dyniface_bad_containers.txt"
# Nguoc lai cua UNPREFIX ben augment: entry {library, class, member: 'get/set:N'}
# ma validator bao member 'N' KHONG TON TAI trong class/lib do → go bo DONG de
# validator tu tim lai dung cho (khong prefix mu, khong ping-pong).
missclass_pat = re.compile(
    r"name '(?:get:|set:)(?P<mem>[^']+)' was not found in class '(?P<cls>[^']+)' "
    r"in library '(?P<lib>[^']+)'")

errors = []
for m in pat.finditer(text):
    seg = text[m.start():m.start() + 400]
    s = sug.search(seg)
    errors.append((m.group("name"), m.group("cls"), m.group("lib"), s))
cont_errors = [(m.group(1), m.group(2)) for m in cont_pat.finditer(text)]
missclass_errors = [(m.group("mem"), m.group("cls"), m.group("lib"))
                    for m in missclass_pat.finditer(text)]
idx_errors = list(dict.fromkeys(idx_pat.findall(text)))

if not errors and not cont_errors and not missclass_errors and not idx_errors:
    print("NO_ERROR")
    sys.exit(2)

yaml = open(yaml_path, encoding="utf-8").read()
changed = 0

# 0b) Crash "Container 'X' not found in library 'L'" = cap (L, X) khong ton tai
# trong anchor → ghi blacklist NGAY (khong can doi gỡ dong). augment doc file
# nay bo qua entry — chong ping-pong "fix gỡ mỗi vòng → augment thêm lại"
# (nguyen nhan loop 40 vong khong hoi tu).
if cont_errors:
    try:
        have = {l.strip() for l in open(BAD_CONTAINERS_FILE) if l.strip()}
    except OSError:
        have = set()
    with open(BAD_CONTAINERS_FILE, "a") as fh:
        for cname, lib in cont_errors:
            pair = "%s|%s" % (lib, cname)
            if pair not in have:
                fh.write(pair + "\n")
                have.add(pair)

# 0) Library khong index — goc ca dong chua library do + ghi blacklist.
for lib in idx_errors:
    lines = yaml.splitlines(keepends=True)
    kept = [ln for ln in lines if ("library: '%s'" % lib) not in ln]
    n = len(lines) - len(kept)
    if n:
        yaml = "".join(kept)
        changed += n
    with open(BAD_LIBS_FILE, "a") as fh:
        fh.write(lib + "\n")

# 1) member disambiguation uu tien
for name, cls, lib, s in errors:
    if s:
        newname = s.group(1)  # 'get:N' hoac 'set:N'
    else:
        # Khong co goi y (danh sach member bi cat) → entry gan SAI class/lib:
        # go bo de lỗi gốc (dynamic call) nổ lại và augment tìm đúng chỗ.
        # (Prefix mù 'get:' dễ gây ping-pong với UNPREFIX của augment.)
        line_rm = re.compile(
            r"^  - \{library: '" + re.escape(lib) + r"', class: '" + re.escape(cls or name) +
            r"', member: '" + re.escape(name) + r"'\}\n", re.M)
        new_yaml, n = line_rm.subn("", yaml, count=1)
        if n:
            changed += 1
            yaml = new_yaml
        continue
    if cls:
        line_re = re.compile(
            r"(\{library: '" + re.escape(lib) + r"', class: '" + re.escape(cls) +
            r"', member: ')" + re.escape(name) + r"(')")
    else:
        line_re = re.compile(
            r"(\{library: '" + re.escape(lib) + r"', member: ')" + re.escape(name) + r"(')")
    if s:
        # Field FFI/external co DANH SACH ca getter VA setter (vi du
        # OSVERSIONINFOEX.dwOSVersionInfoSize, Iterable.iterator) — entry plain
        # khong ton tai → crash parse; prefix 1 ben mat ben kia (invoke setter
        # loi tro lai) → thay 1 dong bang CA HAI get:X va set:X (khong ping-pong).
        g1, g2 = s.group(1), s.group(2)
        both = [x for x in (g1, g2) if x.startswith(("get:", "set:"))]
        if len(both) == 2:
            lines = yaml.splitlines(keepends=True)
            out = []
            done = False
            for ln in lines:
                if (not done
                        and ("member: '%s'" % name) in ln
                        and ("library: '%s'" % lib) in ln
                        and (cls is None or ("class: '%s'" % cls) in ln)
                        and ln.lstrip().startswith("- ")):
                    out.append(ln.replace("member: '%s'" % name, "member: '%s'" % g1))
                    out.append(ln.replace("member: '%s'" % name, "member: '%s'" % g2))
                    done = True
                else:
                    out.append(ln)
            if done:
                yaml = "".join(out)
                changed += 1
                continue
    new_yaml, n = line_re.subn(lambda m: m.group(1) + newname + m.group(2), yaml, count=1)
    if n and new_yaml != yaml:
        changed += 1
        yaml = new_yaml

# 2) container khong ton tai (chi khi khong sua duoc member nao)
# 2b) entry {library, class, member: 'get/set:N'} ma validator bao member 'N'
# khong ton tai trong class do.
# Hanh vi dung theo dynamic_interface.md: field plain chi list N tran;
# getter-only moi can get:N (validator bao disambiguated); setter-only set:N.
# Vay 'not found N' voi entry get:N → bo TIEN TO (get:N → N), giong UNPREFIX
# ben augment. FIXED 2 truoc day dung (xoa dong) la SAI — no pha hong entry
# field that (vd collection _DelegatingIterableBase.isEmpty) → Container-CRASH.
if changed == 0:
    for mem, cls, lib in missclass_errors:
        line_un = re.compile(
            r"(\{library: '" + re.escape(lib) + r"', class: '" + re.escape(cls) +
            r"', member: ')(?:get:|set:)" + re.escape(mem) + r"('\})")
        new_yaml, n = line_un.subn(lambda m: m.group(1) + mem + m.group(2), yaml, count=1)
        if n and new_yaml != yaml:
            changed += 1
            yaml = new_yaml
if changed == 0:
    for cname, lib in cont_errors:
        lines = yaml.splitlines(keepends=True)
        out = []
        for ln in lines:
            if ("library: '" + lib + "'") not in ln:
                out.append(ln)
                continue
            m_single = re.search(r"class: '([^']+)'", ln)
            if m_single and m_single.group(1) == cname:
                changed += 1
                continue  # bo ca dong
            m_list = re.search(r"class: \[([^\]]*)\]", ln)
            if m_list:
                parts = [x.strip().strip("'\"") for x in m_list.group(1).split(",")]
                if cname in parts:
                    changed += 1
                    parts.remove(cname)
                    if parts:
                        out.append(ln.replace(
                            "class: [" + m_list.group(1) + "]",
                            "class: [" + ", ".join("'" + p + "'" for p in parts) + "]"))
                    continue  # het item -> bo dong
            out.append(ln)
        yaml = "".join(out)

if changed:
    open(yaml_path, "w", encoding="utf-8").write(yaml)
    print("FIXED %d" % changed)
else:
    print("NO_CHANGE")
    sys.exit(3)
