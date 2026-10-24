#!/usr/bin/env python3
"""Áp danh tính 1 app (apps/<bundleId>/app.yaml) vào bản build host.

Không sửa vĩnh viễn file trong app/: Android đọc env (build.gradle.kts), iOS
đọc ios/Flutter/AppIdentity.xcconfig (gitignore). Riêng icon phải chép đè vào
res/ + AppIcon.appiconset → luôn backup trước, dynpub khôi phục sau build.

Lệnh (tools/dynpub.sh gọi):
  check <bundle>                       kiểm app.yaml + main_app/ đủ để build
  env <bundle>                         in `export KEY=...` cho bash eval
  ios-check <bundle>                   build iOS: chọn kiểu ký — profile đã cài trên máy
                                       → Manual (trống thì tự tìm, ghi app.yaml); không có
                                       → Automatic (Xcode đã đăng nhập tài khoản của team)
  xcconfig <bundle> <out> [mode]       ghi AppIdentity.xcconfig (mode appstore + Automatic →
                                       archive ký Apple Distribution, không cần device)
  export-plist <bundle> <adhoc|appstore> <out>
  icons-apply <bundle> <backup_dir>    backup icon gốc → sinh icon từ app.yaml
  icons-restore <backup_dir>           chép icon gốc về
"""
import json
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
APPS_DIR = os.environ.get("REGISTRY_APPS_DIR", os.path.join(ROOT, "apps"))
APP = os.path.join(ROOT, "app")
ANDROID_RES = os.path.join(APP, "android", "app", "src", "main", "res")
IOS_ICONSET = os.path.join(APP, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
PROFILE_DIRS = [
    os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
    os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
]
# Trường app.yaml (mục ios:) ↔ loại profile.
PROFILE_KEYS = {"profile": "dev", "adhoc_profile": "adhoc", "appstore_profile": "appstore"}
ANDROID_ICON_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def die(m):
    print(f"LỖI: {m}", file=sys.stderr)
    sys.exit(1)


def parse_yaml(path):
    """YAML tối giản đúng dạng app.yaml (key: value, lồng 1 cấp, comment #)."""
    out, cur = {}, None
    for ln in open(path, encoding="utf-8"):
        raw = re.sub(r"\s+#.*$", "", ln.rstrip("\n"))
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", raw)
        if m:
            k, v = m.group(1), m.group(2).strip()
            if v == "":
                out[k], cur = {}, k
            else:
                out[k], cur = v.strip("'\""), None
            continue
        m = re.match(r"^\s+([A-Za-z_][\w-]*):\s*(.*)$", raw)
        if m and cur is not None:
            out[cur][m.group(1)] = m.group(2).strip().strip("'\"")
    return out


def load(bundle):
    d = os.path.join(APPS_DIR, bundle)
    y = os.path.join(d, "app.yaml")
    if not os.path.isfile(y):
        die(f"thiếu {os.path.relpath(y, ROOT)} — menu [9] → Thêm app để tạo khung")
    cfg = parse_yaml(y)
    if cfg.get("bundle_id") != bundle:
        die(f"{os.path.relpath(y, ROOT)}: bundle_id ({cfg.get('bundle_id')}) ≠ thư mục ({bundle})")
    cfg["_dir"] = d
    return cfg


def expand(p, base):
    if not p:
        return ""
    p = os.path.expanduser(p)
    return p if os.path.isabs(p) else os.path.normpath(os.path.join(base, p))


def cmd_check(bundle):
    cfg = load(bundle)
    d = cfg["_dir"]
    errs = 0
    if not os.path.isfile(os.path.join(d, "main_app", "lib", "main_app_package.dart")):
        print(f"  \033[31m[FAIL]\033[0m thiếu apps/{bundle}/main_app/lib/main_app_package.dart")
        errs += 1
    icon = expand(cfg.get("icon"), d)
    if cfg.get("icon") and not os.path.isfile(icon):
        print(f"  \033[33m[WARN]\033[0m icon {cfg['icon']} chưa có → giữ icon mặc định của app/")
    ks = expand((cfg.get("android") or {}).get("keystore"), d)
    if ks and not os.path.isfile(ks):
        print(f"  \033[31m[FAIL]\033[0m keystore {ks} không tồn tại")
        errs += 1
    print(f"  [i]    {bundle}: tên hiển thị '{cfg.get('display_name', 'App')}'")
    return 1 if errs else 0


def cmd_env(bundle):
    cfg = load(bundle)
    d = cfg["_dir"]
    a = cfg.get("android") or {}
    env = {
        "APP_BUNDLE_ID": bundle,
        "APP_DISPLAY_NAME": cfg.get("display_name") or "App",
        "APP_KEYSTORE": expand(a.get("keystore"), d),
        "APP_KEY_ALIAS": a.get("key_alias", ""),
        "APP_MAIN_APP_SRC": os.path.join(d, "main_app"),
    }
    for k, v in env.items():
        print(f"export {k}={shlex.quote(v)}")
    return 0


def installed_profiles(bundle):
    """Profile đã cài (Xcode / double-click) cấp cho ĐÚNG bundle, còn hạn."""
    now = datetime.now(timezone.utc)
    out, seen = [], set()
    for d in PROFILE_DIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".mobileprovision") or fn in seen:
                continue
            seen.add(fn)
            r = subprocess.run(["security", "cms", "-D", "-i", os.path.join(d, fn)], capture_output=True)
            if r.returncode != 0:
                continue
            try:
                pl = plistlib.loads(r.stdout)
            except Exception:
                continue
            team = (pl.get("TeamIdentifier") or [""])[0]
            ent = pl.get("Entitlements") or {}
            if ent.get("application-identifier") != f"{team}.{bundle}":
                continue
            exp = pl.get("ExpirationDate")
            if exp is None:
                continue
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
            if exp <= now:
                continue
            if ent.get("get-task-allow"):
                kind = "dev"
            elif pl.get("ProvisionedDevices"):
                kind = "adhoc"
            elif pl.get("ProvisionsAllDevices"):
                continue  # enterprise — không dùng
            else:
                kind = "appstore"
            out.append({"name": pl.get("Name", ""), "team": team, "kind": kind, "exp": exp})
    return out


def set_ios_fields(bundle, values):
    """Ghi giá trị vào mục ios: của app.yaml, giữ comment; chỉ điền trường trống."""
    y = os.path.join(APPS_DIR, bundle, "app.yaml")
    lines = open(y, encoding="utf-8").read().split("\n")
    todo, sec, ios_at = dict(values), None, None
    for n, ln in enumerate(lines):
        m = re.match(r"^([A-Za-z_][\w-]*):", ln)
        if m:
            sec = m.group(1)
            if sec == "ios":
                ios_at = n
            continue
        m = re.match(r"^(\s+)([A-Za-z_][\w-]*):(\s*)(\"\"|''|)(\s*#.*)?$", ln)
        if sec == "ios" and m and m.group(2) in todo:
            v = todo.pop(m.group(2))
            lines[n] = f'{m.group(1)}{m.group(2)}:{m.group(3) or " "}"{v}"{m.group(5) or ""}'
    if todo:
        extra = [f'  {k}: "{v}"' for k, v in todo.items()]
        if ios_at is None:
            while lines and lines[-1] == "":
                lines.pop()
            lines += ["ios:"] + extra + [""]
        else:
            lines[ios_at + 1:ios_at + 1] = extra
    with open(y, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def autofill_ios(bundle, keys):
    """Trường ios.* trống trong [keys] → điền từ profile đã cài, ghi app.yaml.
    Không bao giờ đè giá trị người dùng đã ghi."""
    i = load(bundle).get("ios") or {}
    if all(i.get(k) for k in keys):
        return i
    found = installed_profiles(bundle)
    team = i.get("team_id")
    if team:
        found = [p for p in found if p["team"] == team]
    else:
        teams = sorted({p["team"] for p in found})
        if len(teams) > 1:
            die(f"profile của {bundle} thuộc nhiều team ({', '.join(teams)}) — "
                f"ghi ios.team_id trong apps/{bundle}/app.yaml để chọn")
    fill = {}
    if not team and found:
        fill["team_id"] = found[0]["team"]
    for k in keys:
        if k == "team_id" or i.get(k):
            continue
        cand = [p for p in found if p["kind"] == PROFILE_KEYS[k]]
        if cand:
            fill[k] = max(cand, key=lambda p: p["exp"])["name"]  # hạn xa nhất
    if fill:
        set_ios_fields(bundle, fill)
        for k, v in fill.items():
            print(f"  \033[32m[PASS]\033[0m apps/{bundle}/app.yaml: ios.{k} = {v} (tự tìm từ profile đã cài)", file=sys.stderr)
        i.update(fill)
    return i


def missing_profile_msg(bundle, kind):
    return (f"chưa cài profile {kind} còn hạn cho {bundle} — tạo trên developer.apple.com "
            f"(App ID {bundle}), tải .mobileprovision, double-click để import rồi chạy lại "
            f"(hoặc ghi tay vào apps/{bundle}/app.yaml)")


def xcode_teams():
    """Team của các tài khoản đã đăng nhập Xcode (Settings → Accounts):
    [(team_id, tên, free?)]. Đọc từ defaults com.apple.dt.Xcode."""
    r = subprocess.run(["defaults", "export", "com.apple.dt.Xcode", "-"], capture_output=True)
    if r.returncode != 0:
        return []
    try:
        d = plistlib.loads(r.stdout)
    except Exception:
        return []
    out = {}
    for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
        for teams in (d.get(key) or {}).values():
            for t in teams if isinstance(teams, list) else []:
                tid = t.get("teamID")
                if tid:
                    out[tid] = (tid, t.get("teamName", ""), bool(t.get("isFreeProvisioningTeam")))
    return sorted(out.values())


def distribution_cert_teams():
    """Team id của cert "Apple Distribution: … (TEAMID)" có private key trong keychain."""
    r = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True)
    return sorted(set(re.findall(r'"(?:Apple|iPhone) Distribution: .*\(([A-Z0-9]{10})\)"', r.stdout)))


def sign_plan(bundle, export_mode=None):
    """Kiểu ký cho lần build này. Profile ghi trong app.yaml chỉ dùng được khi
    CÓ THẬT trên máy (app.yaml được commit — máy khác có thể không có file):
      archive: profile Development cài trên máy → Manual, không → Automatic
      export : profile Ad Hoc / App Store cài trên máy → manual, không → automatic
    Automatic = Xcode tự tạo/tải profile bằng tài khoản đã đăng nhập (flutter
    build ipa truyền sẵn -allowProvisioningUpdates). → dict."""
    keys = ["team_id", "profile"] + ([f"{export_mode}_profile"] if export_mode else [])
    i = autofill_ios(bundle, keys)
    team = i.get("team_id")
    have = {}
    for p in installed_profiles(bundle):
        if not team or p["team"] == team:
            have.setdefault(p["kind"], set()).add(p["name"])

    def pick(key):
        name = i.get(key)
        if name and name in have.get(PROFILE_KEYS[key], ()):
            return name
        if name:
            print(f"  [i]    apps/{bundle}/app.yaml: ios.{key} = {name} không có trên máy này → ký Automatic",
                  file=sys.stderr)
        return None

    plan = {"team": team, "profile": pick("profile"), "export_profile": None, "teams": []}
    if export_mode:
        plan["export_profile"] = pick(f"{export_mode}_profile")
    auto = not plan["profile"] or (export_mode and not plan["export_profile"])
    if auto:
        teams = xcode_teams()
        plan["teams"] = teams
        if not team:
            # Ưu tiên team trả phí của tài khoản Xcode; chưa đăng nhập → team của cert Distribution.
            paid = [t for t in teams if not t[2]] or teams
            cand = [t[0] for t in paid] if paid else distribution_cert_teams()
            if len(cand) == 1:
                team = plan["team"] = cand[0]
                set_ios_fields(bundle, {"team_id": team})
                print(f"  \033[32m[PASS]\033[0m apps/{bundle}/app.yaml: ios.team_id = {team} (tài khoản Xcode / cert trên máy)",
                      file=sys.stderr)
    plan["archive_style"] = "Manual" if plan["profile"] else "Automatic"
    plan["export_style"] = "manual" if plan["export_profile"] else "automatic"
    return plan


def cmd_ios_check(bundle):
    """Build iOS cần team của đúng bundle (không có team mặc định); có profile
    trên máy → Manual, không → Automatic (cần Xcode đăng nhập tài khoản team)."""
    plan = sign_plan(bundle)
    if not plan["team"]:
        die(f"apps/{bundle}/app.yaml: thiếu ios.team_id và không đoán được — ghi team Apple của bundle này, "
            f"hoặc " + missing_profile_msg(bundle, "Development"))
    if plan["archive_style"] == "Manual":
        print(f"  [i]    {bundle}: ký Manual — team {plan['team']}, profile {plan['profile']}")
        return 0
    if not any(t[0] == plan["team"] for t in plan["teams"]):
        die(f"{bundle}: không có profile Development trên máy VÀ Xcode chưa đăng nhập tài khoản thuộc team "
            f"{plan['team']} → không ký được. Một trong hai:\n"
            f"  • Xcode → Settings → Accounts → thêm Apple ID của team (tool sẽ ký Automatic)\n"
            f"  • {missing_profile_msg(bundle, 'Development')}")
    print(f"  [i]    {bundle}: ký Automatic — team {plan['team']} (Xcode tự tạo/tải profile; tài khoản cần quyền "
          f"Admin / App Manager, bản ad-hoc cần máy test đã đăng ký trong team)")
    return 0


def cmd_xcconfig(bundle, out, mode=None):
    cfg = load(bundle)
    plan = sign_plan(bundle) if cfg.get("ios") is not None else {"team": None, "profile": None,
                                                                 "archive_style": "Automatic"}
    lines = [
        "// SINH RA bởi tools/dynpub.sh từ apps/%s/app.yaml — KHÔNG sửa, KHÔNG commit." % bundle,
        f"APP_BUNDLE_ID = {bundle}",
        f"APP_DISPLAY_NAME = {cfg.get('display_name') or 'App'}",
        f"APP_SIGN_STYLE = {plan['archive_style']}",
    ]
    # Automatic + identity Development cần profile Development → Apple bắt team có
    # ít nhất 1 device đăng ký. Bản App Store archive thẳng bằng Apple Distribution:
    # Xcode tạo profile App Store, không cần device.
    if mode == "appstore" and plan["archive_style"] == "Automatic":
        lines.append("APP_SIGN_IDENTITY = Apple Distribution")
    if plan["team"]:
        lines.append(f"APP_TEAM_ID = {plan['team']}")
    # Automatic: PROVISIONING_PROFILE_SPECIFIER phải rỗng (Xcode báo xung đột nếu có).
    lines.append(f"APP_PROFILE = {plan['profile'] or ''}")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


def cmd_export_plist(bundle, mode, out):
    """ExportOptions cho `flutter build ipa`: dùng file app.yaml chỉ định, không
    thì sinh theo sign_plan — profile export có trên máy → manual, không →
    automatic (Xcode tự lo profile bằng tài khoản đã đăng nhập)."""
    cfg = load(bundle)
    i = cfg.get("ios") or {}
    given = expand(i.get(f"export_options_{mode}") or (i.get("export_options") if mode == "adhoc" else ""),
                   cfg["_dir"])
    if given:
        if not os.path.isfile(given):
            die(f"export options {given} không tồn tại")
        shutil.copyfile(given, out)
        return 0
    plan = sign_plan(bundle, mode)
    if not plan["team"]:
        die(f"apps/{bundle}/app.yaml: thiếu ios.team_id để export {mode}")
    plist = {
        "method": "ad-hoc" if mode == "adhoc" else "app-store",
        "teamID": plan["team"],
        "uploadSymbols": True,
        "compileBitcode": False,
    }
    if plan["export_style"] == "manual":
        plist.update(signingStyle="manual", signingCertificate="Apple Distribution",
                     provisioningProfiles={bundle: plan["export_profile"]})
        print(f"  [i]    export {mode}: manual — profile {plan['export_profile']}", file=sys.stderr)
    else:
        if not any(t[0] == plan["team"] for t in plan["teams"]):
            die(f"{bundle}: không có profile {'Ad Hoc' if mode == 'adhoc' else 'App Store'} trên máy VÀ Xcode chưa "
                f"đăng nhập tài khoản team {plan['team']} → không export được. "
                + missing_profile_msg(bundle, "Ad Hoc" if mode == "adhoc" else "App Store"))
        plist["signingStyle"] = "automatic"
        print(f"  [i]    export {mode}: automatic — team {plan['team']} (Xcode tự tạo/tải profile)", file=sys.stderr)
    with open(out, "wb") as f:
        plistlib.dump(plist, f)
    return 0


def _sips(src, size, dst):
    r = subprocess.run(["sips", "-s", "format", "png", "-z", str(size), str(size), src, "--out", dst],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die(f"sips lỗi ({dst}): {r.stderr.strip()}")


def cmd_icons_apply(bundle, backup):
    cfg = load(bundle)
    src = expand(cfg.get("icon"), cfg["_dir"])
    if not cfg.get("icon") or not os.path.isfile(src):
        print("  [i]    app.yaml không có icon hợp lệ → giữ icon mặc định")
        return 0
    if os.path.exists(backup):
        shutil.rmtree(backup)
    os.makedirs(backup)
    # Backup TRƯỚC khi ghi đè — dynpub khôi phục sau build (kể cả build lỗi).
    for dens in ANDROID_ICON_SIZES:
        d = os.path.join(ANDROID_RES, f"mipmap-{dens}")
        if os.path.isdir(d):
            shutil.copytree(d, os.path.join(backup, "android", f"mipmap-{dens}"))
    shutil.copytree(IOS_ICONSET, os.path.join(backup, "ios", "AppIcon.appiconset"))
    with open(os.path.join(backup, "MANIFEST.json"), "w") as f:
        json.dump({"bundle": bundle}, f)
    for dens, size in ANDROID_ICON_SIZES.items():
        d = os.path.join(ANDROID_RES, f"mipmap-{dens}")
        os.makedirs(d, exist_ok=True)
        _sips(src, size, os.path.join(d, "ic_launcher.png"))
    contents = json.load(open(os.path.join(IOS_ICONSET, "Contents.json")))
    for img in contents.get("images", []):
        fn = img.get("filename")
        if not fn:
            continue
        pt = float(img["size"].split("x")[0])
        scale = int(img.get("scale", "1x").rstrip("x"))
        _sips(src, int(round(pt * scale)), os.path.join(IOS_ICONSET, fn))
    print(f"  \033[32m[PASS]\033[0m đã áp icon {os.path.relpath(src, ROOT)} (Android mipmap + iOS AppIcon)")
    return 0


def cmd_icons_restore(backup):
    if not os.path.isdir(backup):
        return 0
    for dens in ANDROID_ICON_SIZES:
        b = os.path.join(backup, "android", f"mipmap-{dens}")
        if os.path.isdir(b):
            d = os.path.join(ANDROID_RES, f"mipmap-{dens}")
            shutil.rmtree(d, ignore_errors=True)
            shutil.copytree(b, d)
    b = os.path.join(backup, "ios", "AppIcon.appiconset")
    if os.path.isdir(b):
        shutil.rmtree(IOS_ICONSET, ignore_errors=True)
        shutil.copytree(b, IOS_ICONSET)
    shutil.rmtree(backup, ignore_errors=True)
    print("  [i]    đã khôi phục icon mặc định của app/")
    return 0


def main(a):
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = a[0]
    if cmd == "check":
        return cmd_check(a[1])
    if cmd == "env":
        return cmd_env(a[1])
    if cmd == "ios-check":
        return cmd_ios_check(a[1])
    if cmd == "xcconfig":
        return cmd_xcconfig(a[1], a[2], a[3] if len(a) > 3 else None)
    if cmd == "export-plist":
        return cmd_export_plist(a[1], a[2], a[3])
    if cmd == "icons-apply":
        return cmd_icons_apply(a[1], a[2])
    if cmd == "icons-restore":
        return cmd_icons_restore(a[1])
    die(f"lệnh lạ: {cmd}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
