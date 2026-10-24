#!/usr/bin/env python3
"""Release registry — mỗi bản build host 1 ABI, tool tự tính patch cao nhất
mỗi bản build chạy được, sinh manifest tĩnh cho TỪNG env (staging / pre / prod).

Env: mỗi app thuộc đúng 1 env (`configs/apps/<bundle>.json` → "env"); env nào
có rs_domain + server SSH nào khai ở `configs/deploy.json`. Patch được đưa lên
1 hoặc nhiều env ("envs" trong patches/v<N>.json). Mỗi APP 1 manifest riêng
`publish/<env>/manifest/<bundle>.json` (= `<rs_domain>/app/manifest/<bundle>.json`)
chứa mọi bản build store của app đó + patch app đó dùng; bytecode dùng chung ở
`publish/patches/`.

Thiết kế: docs/release_registry_design.md. Dữ liệu (track git):

  registry/abis/<abi_id>.json   provides của 1 ABI (dùng chung giữa các build)
  registry/hosts/<bundle>.json  MỌI bản build của 1 bundle (trỏ abi_id) — máy build
                                ghi + commit, không cần VPN / deploy
  registry/store/<bundle>.json  CHỈ bản build đã xác nhận lên store (menu [6]:
                                submitted / live / removed) — manifest, plan,
                                deploy chỉ dùng file này
  registry/bundles.json         trạng thái bundle (active/retired, app thay thế…)
  registry/patches/v<N>.json    requires + file/hash/size của từng patch
  registry/policy.json          min_allowed_patch, popup, app thay thế chung (replacement_app — chỉ prod)
                                (mặc định chung + "envs": {<env>: ghi đè})
  registry/compat.json          SINH RA: env → abi_id → max_patch + lý do dừng

Mọi lệnh ghi: áp thay đổi trong bộ nhớ → tính lại → validator. Có lỗi →
KHÔNG ghi gì (exit 1). Không lỗi → ghi registry + compat + manifest.

Lệnh (dynpub.sh wizard gọi; gọi tay khi cần):
  list-bundles | list-builds <bundle> | list-patches | list-envs | env-of <bundle> | apps-in-env <env>
  next-version <bundle>                   version kế tiếp (chỉ xem, không giữ chỗ)
  reserve-version <bundle> [--version X]  giữ chỗ version cho lần build host này
                                          (tự tăng, ghi last_version_code vào bundles.json)
  redirect-candidates <platform> --env E [--min-patch N] [--exclude B]
  register-host --bundle B --platform P --version-name X --version-code N --mode M [--unlock-date YYYY-MM-DD]
  register-patch --bytecode F --envs E1,E2 [--min-force-update N]
  patch-envs <N> --add E1,E2 | --remove E | --set E1,E2
  patch-force <N> <M>                     min_force_update của patch vN = M: máy đang chạy
                                          patch < M, khi tải vN sẽ hiện popup restart (0 = tắt)
  store <bundle> <platform> <version_code> built|submitted|live|removed|rejected
                                          (rejected chỉ từ submitted → bỏ khỏi store/, bản trước giữ nguyên)
  bundle-add <bundle> [--env E] | bundle-retire <bundle> | bundle-activate <bundle>
  replacement-app --android B|none --ios B|none
                                          app thay thế CHUNG của env prod (mỗi platform 1 app):
                                          app chết / app bị ép mà không có bản cao hơn → mở app này
  set-env <bundle> <env>                 chuyển app sang env khác (config + manifest)
  set-rs-domain <env> <url> [--ssh-path P]  đổi rs_domain của env → mọi config env đó
  set-api-domain <env> <url>              đổi api_domain của env → mọi config env đó
  sync-configs                            rs_domain mỗi config = rs_domain env của nó
  ios-app-id <bundle> <id>
  force-vc <bundle> <platform> <below_vc|0>
  block-below <N> --env E [--dry-run]
  retract <N>                             (rút khỏi MỌI env)
  plan [--env E] [--bundle B] | regen | validate | check-links
  changed-envs [--clear]                  env có manifest/config đổi mà chưa deploy (deploy xong tự xoá)
  deploy [--env E]… [--bundle B] [--dry-run] [--no-configs] [--key-file F] [--key-pass P]

Env: REGISTRY_DIR, REGISTRY_PUBLISH, REGISTRY_APPS_DIR, REGISTRY_RUNTIME_CFG_DIR,
     REGISTRY_DEPLOY_FILE, REGISTRY_OFFLINE=1 (không gọi iTunes/Play).
"""
import datetime
import gzip
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import deploy_sftp  # noqa: E402  (.env + SFTP; paramiko chỉ nạp khi deploy)

deploy_sftp.load_dotenv()

_HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(_HERE, "..", ".."))
REG = os.environ.get("REGISTRY_DIR", os.path.join(ROOT, "registry"))
# publish/<env>/manifest/<bundle>.json + publish/patches/<file>.bytecode (dùng chung các env).
PUBLISH = os.environ.get("REGISTRY_PUBLISH", os.path.join(ROOT, "publish"))
# Bản sao mọi bytecode đã đăng ký (dist/ gitignore): retract/đổi đích có thể
# cần lại file đã bị dọn khỏi publish/patches → lấy từ đây, không có thì tải từ rs_domain.
ARCHIVE = os.environ.get("REGISTRY_ARCHIVE", os.path.join(ROOT, "dist", "patch_archive"))
APPS_DIR = os.environ.get("REGISTRY_APPS_DIR", os.path.join(ROOT, "apps"))
DEPLOY_FILE = os.environ.get("REGISTRY_DEPLOY_FILE", os.path.join(ROOT, "configs", "deploy.json"))
RUNTIME_CFG_DIR = os.environ.get("REGISTRY_RUNTIME_CFG_DIR", os.path.join(ROOT, "configs", "apps"))
# Repo configs (GitHub Vulcan-dev-25/configs, app đọc config ở đây) clone cạnh
# repo này: deploy CHÉP config app sang ../configs/apps/, user tự commit + push.
CONFIGS_OUT = os.environ.get("REGISTRY_CONFIGS_OUT", os.path.join(os.path.dirname(ROOT), "configs", "apps"))
IFACE = os.environ.get("DYNMOD_IFACE", os.path.join(ROOT, "dist", "dynamic_interface.yaml"))
MODULE_PKG_DIR = os.environ.get("DYNMOD_MODULE_PKG_DIR", os.path.join(os.path.dirname(ROOT), "app_package"))
MODULE_NAME = os.environ.get("DYNPUSH_MODULE_NAME", "app_content")
OFFLINE = os.environ.get("REGISTRY_OFFLINE") == "1"
# Env có manifest/config đổi mà chưa deploy (dynpub.sh hỏi deploy đúng các env này).
CHANGED_FILE = os.environ.get("REGISTRY_CHANGED_FILE", os.path.join(ROOT, "dist", ".dynpub_changed_envs"))

PLATFORMS = ("android", "ios")
STORE_STATES = ("built", "submitted", "live", "removed", "rejected")
# Mode build chạy được module (engine ddm). Build engine stock không đăng ký.
MODULE_MODES = ("ddm", "adhoc", "appstore")

RED, GRN, YEL, DIM, RST = "\033[31m", "\033[32m", "\033[33m", "\033[2m", "\033[0m"


def ok(m): print(f"  {GRN}[PASS]{RST} {m}")
def bad(m): print(f"  {RED}[FAIL]{RST} {m}")
def warn(m): print(f"  {YEL}[WARN]{RST} {m}")
def info(m): print(f"  [i]    {m}")


class RegError(Exception):
    pass


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path, default=None):
    if not os.path.isfile(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    """Ghi atomic (tmp → rename), key sắp xếp ổn định để diff git gọn."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ════════════════════════════════════════════════════════════ Env + config app
def norm_domain(u):
    """Dạng so sánh / tool tự ghép URL: bỏ `/` cuối (tránh `//app/`). Config app
    vẫn ghi NGUYÊN VĂN rs_domain của deploy.json (`rs_domain_raw`)."""
    return (u or "").strip().rstrip("/")


def load_envs():
    """configs/deploy.json → {env: {name, rs_domain, ssh?, upload?}} (giữ thứ tự file)."""
    out = {}
    for t in (read_json(DEPLOY_FILE) or {}).get("targets", []):
        name = t.get("name")
        if not name:
            raise RegError(f"{os.path.relpath(DEPLOY_FILE, ROOT)}: target thiếu name")
        e = dict(t)
        e["rs_domain_raw"] = (t.get("rs_domain") or t.get("url") or "").strip()
        e["rs_domain"] = norm_domain(e["rs_domain_raw"])
        out[name] = e
    return out


def env_names():
    return list(load_envs())


def need_env(env, envs=None):
    envs = envs if envs is not None else load_envs()
    if env not in envs:
        raise RegError(f"env lạ: {env} (có: {', '.join(envs) or '— chưa có configs/deploy.json'})")
    return envs[env]


def app_cfg_path(bundle):
    return os.path.join(RUNTIME_CFG_DIR, f"{bundle}.json")


def read_app_cfg(bundle):
    return read_json(app_cfg_path(bundle), {}) or {}


def app_env(bundle):
    return read_app_cfg(bundle).get("env")


def all_app_cfgs():
    """{bundle: config} của mọi configs/apps/*.json."""
    out = {}
    if os.path.isdir(RUNTIME_CFG_DIR):
        for f in sorted(os.listdir(RUNTIME_CFG_DIR)):
            if f.endswith(".json"):
                out[f[:-5]] = read_json(os.path.join(RUNTIME_CFG_DIR, f)) or {}
    return out


def apps_in_env(env):
    return sorted(b for b, c in all_app_cfgs().items() if c.get("env") == env)


def mark_changed(*envs):
    os.makedirs(os.path.dirname(CHANGED_FILE), exist_ok=True)
    cur = set(read_changed())
    with open(CHANGED_FILE, "w") as f:
        f.write("\n".join(sorted(cur | {e for e in envs if e})) + "\n")


def unmark_changed(*envs):
    left = [e for e in read_changed() if e not in envs]
    if left:
        with open(CHANGED_FILE, "w") as f:
            f.write("\n".join(left) + "\n")
    elif os.path.isfile(CHANGED_FILE):
        os.remove(CHANGED_FILE)


def read_changed():
    if not os.path.isfile(CHANGED_FILE):
        return []
    return [x.strip() for x in open(CHANGED_FILE) if x.strip()]


def patch_in_env(p, env):
    """Patch cũ (trước khi có env) không có "envs" → coi như ở mọi env."""
    envs = p.get("envs")
    return envs is None or env in envs


def parse_env_list(v, envs):
    out = [x.strip() for x in (v or "").split(",") if x.strip()]
    if not out:
        raise RegError("cần ít nhất 1 env")
    for e in out:
        need_env(e, envs)
    return out


# ════════════════════════════════════════════════════════════ ABI: provides / requires
_IFACE_LINE = re.compile(
    r"^\s*-\s*\{library:\s*'([^']+)'(?:,\s*class:\s*'([^']+)')?(?:,\s*member:\s*'([^']+)')?\s*\}\s*$")
_IFACE_SECTION = re.compile(r"^([a-z][a-z-]*):\s*$")


def parse_iface(path):
    """dynamic_interface.yaml → tập entry `section|library[#class[.member]]`."""
    out, section = set(), None
    with open(path, encoding="utf-8") as f:
        for ln in f:
            m = _IFACE_SECTION.match(ln)
            if m:
                section = m.group(1)
                continue
            m = _IFACE_LINE.match(ln)
            if m and section:
                key = f"{section}|{m.group(1)}"
                if m.group(2):
                    key += "#" + m.group(2)
                if m.group(3):
                    key += "." + m.group(3)
                out.add(key)
    return out


def iface_library(entry):
    """`callable|package:dio/dio.dart#Dio` → `package:dio/dio.dart`."""
    lib = entry.split("|", 1)[1]
    return lib.split("#", 1)[0]


def iface_package(entry):
    """Tên package của entry (`dart:*` → `dart`, package:flutter/... → `flutter`)."""
    lib = iface_library(entry)
    if lib.startswith("dart:"):
        return "dart"
    m = re.match(r"package:([A-Za-z0-9_]+)/", lib)
    return m.group(1) if m else lib


def _abi_mod():
    """abi.py (tools/cmd/abicheck) — dùng lại compute_abi/read_lock/abi_packages."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "cmd", "abicheck"))
    sys.dont_write_bytecode = True
    import abi  # noqa: E402
    return abi


def compute_provides():
    """ABI host `app/` HIỆN TẠI (gọi ngay sau khi build host).

    `iface` lấy từ bản ĐẦY ĐỦ `dist/dynamic_interface.yaml` (cùng loại file mà
    patch dùng khi compile) — so cùng loại mới so được tập con. Bản `.host.yaml`
    chỉ bớt entry trỏ library không có trong host, module không dùng được.
    """
    abi = _abi_mod()
    cur = abi.compute_abi(os.path.join(abi.APP, "pubspec.lock"), abi.APP)
    if not os.path.isfile(IFACE):
        raise RegError(f"thiếu {os.path.relpath(IFACE, ROOT)} — host build chưa sinh interface?")
    return {
        "engine_rev": cur["engine_rev"],
        "contract_version": cur["contract_version"],
        "packages": cur["packages"],
        "iface": sorted(parse_iface(IFACE)),
    }


def compute_requires():
    """Patch vừa compile cần gì từ host.

    Bytecode được link với kernel + package của host `app/` lúc compile
    (dart2bytecode --import-dill anchor --packages app/.dart_tool/...), nên
    VERSION lấy theo host compile; TÊN package = package tầng host có trong
    pubspec.lock của app_package (module có dùng). iface chỉ giữ entry thuộc
    dart:*, flutter và các package đó — host compile thêm package module không
    dùng thì host cũ không bị dừng oan.
    """
    abi = _abi_mod()
    host_names, _, _ = abi.abi_packages()
    compile_host = abi.compute_abi(os.path.join(abi.APP, "pubspec.lock"), abi.APP)
    mod_lock_path = os.path.join(MODULE_PKG_DIR, "pubspec.lock")
    if os.path.isfile(mod_lock_path):
        mod_lock = abi.read_lock(mod_lock_path)
        names = set(mod_lock) & set(host_names)
        # Entry module (modules/*.dart) import thẳng package host không khai
        # trong pubspec app_package (vd content_kit — resolve qua package_config
        # của host) → không có trong lock, phải quét import.
        names |= _module_direct_imports(abi) & set(host_names)
        names = sorted(names)
    else:
        warn(f"không thấy {mod_lock_path} — coi như module dùng MỌI package host (chặt)")
        mod_lock, names = {}, sorted(host_names)
    packages = {}
    for n in names:
        v = compile_host["packages"].get(n)
        if v is None:
            e = mod_lock.get(n, {})
            v = e.get("version")
            if v is None:
                continue
        packages[n] = v
    keep = set(packages) | {"dart", "flutter"}
    iface = sorted(e for e in parse_iface(IFACE) if iface_package(e) in keep)
    return {
        "engine_rev": compile_host["engine_rev"],
        "contract_version": compile_host["contract_version"],
        "packages": packages,
        "iface": iface,
    }


def _module_direct_imports(abi):
    """Package host mà code module import TRỰC TIẾP (đi từ entry module)."""
    import importlib
    gdi = importlib.import_module("gen_dynamic_interface")
    entry = os.path.join(MODULE_PKG_DIR, "modules", "home_content.dart")
    if not os.path.isfile(entry):
        warn(f"không thấy {entry} — chưa áp templates/module, bỏ qua quét import trực tiếp")
        return set()
    gdi.MODULE_ENTRY = entry
    _, module, host = abi.abi_packages()
    return gdi.module_direct_packages(host, module)


def abi_id_of(provides):
    canon = json.dumps(provides, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()[:16]


def compatible(provides, requires):
    """→ (bool, [lý do]). Luật §3.3 của doc."""
    reasons = []
    if requires.get("engine_rev") and provides.get("engine_rev") and \
            requires["engine_rev"] != provides["engine_rev"]:
        reasons.append(f"engine: host {provides['engine_rev'][:10]} ≠ patch {requires['engine_rev'][:10]}")
    if requires.get("contract_version") != provides.get("contract_version"):
        reasons.append(f"content_kit contract: host {provides.get('contract_version')} ≠ "
                       f"patch {requires.get('contract_version')}")
    hp = provides.get("packages", {})
    for n, v in sorted(requires.get("packages", {}).items()):
        if n not in hp:
            reasons.append(f"package mới: {n} {v} (host không có)")
        elif hp[n] != v:
            reasons.append(f"{n}: host {hp[n]} ≠ patch {v}")
    missing = sorted(set(requires.get("iface", [])) - set(provides.get("iface", [])))
    if missing:
        ex = ", ".join(iface_library(e) for e in missing[:2])
        reasons.append(f"interface: host thiếu {len(missing)} entry (vd {ex})")
    return (not reasons), reasons


# ════════════════════════════════════════════════════════════ Registry (bộ nhớ)
# Env duy nhất có app thay thế chung (app chết / bị ép mà không có bản cao hơn).
REPLACE_ENV = "prod"

DEFAULT_POLICY = {
    "min_allowed_patch": 0,
    "soft_prompt": True,
    "soft_prompt_interval_hours": 24,
    "ios_lookup_countries": ["us"],
}


class Registry:
    def __init__(self, root=REG):
        self.root = root
        self.abis = {}      # abi_id → {abi_id, first_seen, provides}
        self.hosts = {}     # bundle → {bundle_id, builds:[...]}  mọi bản build
        self.store = {}     # bundle → {bundle_id, builds:[...]}  chỉ bản đã lên store
        self.bundles = {}   # bundle → {status, ios_app_id, force_vc}
        self.patches = {}   # version(int) → {...}
        self.policy = json.loads(json.dumps(DEFAULT_POLICY))
        self.dirty = set()  # đường dẫn tương đối cần ghi
        self.env = None     # bản scoped(): tên env

    # ── load / save ─────────────────────────────────────────────────────────
    @classmethod
    def load(cls, root=REG):
        r = cls(root)
        d = os.path.join(root, "abis")
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json"):
                    a = read_json(os.path.join(d, f))
                    r.abis[a["abi_id"]] = a
        d = os.path.join(root, "hosts")
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json"):
                    h = read_json(os.path.join(d, f))
                    r.hosts[h["bundle_id"]] = h
        d = os.path.join(root, "store")
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".json"):
                    h = read_json(os.path.join(d, f))
                    r.store[h["bundle_id"]] = h
        r._migrate_store_field()
        r.bundles = read_json(os.path.join(root, "bundles.json"), {}) or {}
        d = os.path.join(root, "patches")
        if os.path.isdir(d):
            for f in os.listdir(d):
                if re.match(r"^v\d+\.json$", f):
                    p = read_json(os.path.join(d, f))
                    r.patches[int(p["version"])] = p
        pol = read_json(os.path.join(root, "policy.json"))
        if pol:
            for k, v in pol.items():
                r.policy[k] = v
        else:
            r.dirty.add("policy.json")
        return r

    def _migrate_store_field(self):
        """Bố cục cũ: trạng thái store nằm trong hosts/<b>.json → chuyển bản đã
        rời `built` sang store/<b>.json, bỏ field `store` khỏi hosts."""
        for b, h in self.hosts.items():
            for bd in h.get("builds", []):
                st = bd.pop("store", None)
                if st is None:
                    continue
                self.dirty.add(f"hosts/{b}.json")
                if st != "built" and not self.find_store_build(b, bd["platform"], bd["version_code"]):
                    self._put_store(b, bd, st)

    def save(self):
        for rel in sorted(self.dirty):
            path = os.path.join(self.root, rel)
            if rel == "policy.json":
                write_json(path, self.policy)
            elif rel == "bundles.json":
                write_json(path, self.bundles)
            elif rel.startswith("abis/"):
                write_json(path, self.abis[rel[5:-5]])
            elif rel.startswith("hosts/"):
                write_json(path, self.hosts[rel[6:-5]])
            elif rel.startswith("store/"):
                b = rel[6:-5]
                h = self.store.get(b, {})
                if h.get("builds") or h.get("rejected"):
                    write_json(path, h)
                elif os.path.isfile(path):
                    os.remove(path)
            elif rel.startswith("patches/"):
                write_json(path, self.patches[int(rel[9:-5])])
        self.dirty.clear()

    # ── tiện ích ────────────────────────────────────────────────────────────
    def bundle(self, b):
        if b not in self.bundles:
            raise RegError(f"bundle chưa đăng ký: {b} (menu [9] → Thêm app)")
        return self.bundles[b]

    @staticmethod
    def _iter(src, bundle):
        out = []
        for b, h in sorted(src.items()):
            if bundle and b != bundle:
                continue
            for bd in h.get("builds", []):
                out.append((b, bd))
        return out

    def builds(self, bundle=None):
        """Build ĐÃ LÊN STORE (store/<b>.json): [(bundle, build_dict)] — thứ
        manifest / plan / validator dùng."""
        return self._iter(self.store, bundle)

    def all_builds(self, bundle=None):
        """Mọi bản build (hosts/<b>.json), kể cả chưa lên store."""
        return self._iter(self.hosts, bundle)

    def store_state(self, bundle, platform, vc):
        sb = self.find_store_build(bundle, platform, vc)
        if sb:
            return sb["store"]
        rj = self._find({bundle: {"builds": self.store.get(bundle, {}).get("rejected", [])}}, bundle, platform, vc)
        return "rejected" if rj else "built"

    @staticmethod
    def _find(src, bundle, platform, vc):
        for bd in src.get(bundle, {}).get("builds", []):
            if bd["platform"] == platform and int(bd["version_code"]) == int(vc):
                return bd
        return None

    def find_build(self, bundle, platform, vc):
        return self._find(self.hosts, bundle, platform, vc)

    def find_store_build(self, bundle, platform, vc):
        return self._find(self.store, bundle, platform, vc)

    def live_versions(self):
        return sorted(v for v, p in self.patches.items() if not p.get("retracted"))

    def latest(self):
        lv = self.live_versions()
        return lv[-1] if lv else 0

    # ── mutation ────────────────────────────────────────────────────────────
    def add_bundle(self, b):
        if not re.match(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$", b):
            raise RegError(f"bundle id không hợp lệ: {b}")
        if b in self.bundles:
            return False
        self.bundles[b] = {"status": "active", "ios_app_id": None,
                           "force_vc": {}}
        self.dirty.add("bundles.json")
        return True

    def add_abi(self, provides):
        aid = abi_id_of(provides)
        if aid not in self.abis:
            self.abis[aid] = {"abi_id": aid, "first_seen": now_iso(), "provides": provides}
            self.dirty.add(f"abis/{aid}.json")
        return aid

    def add_build(self, bundle, platform, version_name, version_code, mode, abi_id, git_rev=None, unlock_date=None):
        self.bundle(bundle)
        if platform not in PLATFORMS:
            raise RegError(f"platform lạ: {platform}")
        h = self.hosts.setdefault(bundle, {"bundle_id": bundle, "builds": []})
        bd = self.find_build(bundle, platform, version_code)
        if bd and bd["abi_id"] != abi_id:
            raise RegError(
                f"{bundle}/{platform}/{version_code} đã đăng ký với ABI {bd['abi_id']} — build lại ra ABI "
                f"{abi_id} khác → tăng version_code (máy đã cài bản cũ sẽ tra nhầm dòng)")
        new = bd is None
        if bd:
            bd.update({"built_at": now_iso(), "git_rev": git_rev, "version_name": version_name, "mode": mode})
        else:
            bd = {
                "platform": platform, "version_code": int(version_code), "version_name": version_name,
                "abi_id": abi_id, "mode": mode, "built_at": now_iso(), "git_rev": git_rev,
            }
            h["builds"].append(bd)
            h["builds"].sort(key=lambda x: (x["platform"], x["version_code"]))
        # ngày unlock đã ghi vào loading_kit (BootConfig.appReleaseDate) lúc build
        if unlock_date:
            bd["unlock_date"] = unlock_date
        self.dirty.add(f"hosts/{bundle}.json")
        return new

    def _put_store(self, bundle, bd, state):
        """Ghi 1 dòng vào store/<b>.json: `builds` (submitted / live / removed —
        vào manifest) hoặc `rejected` (chỉ ghi nhận, KHÔNG vào manifest)."""
        h = self.store.setdefault(bundle, {"bundle_id": bundle, "builds": []})
        same = lambda x: x["platform"] == bd["platform"] and x["version_code"] == bd["version_code"]  # noqa: E731
        h["builds"] = [x for x in h["builds"] if not same(x)]
        rejected = [x for x in h.get("rejected", []) if not same(x)]
        if state == "rejected":
            rejected.append({"platform": bd["platform"], "version_code": bd["version_code"],
                             "version_name": bd.get("version_name"), "rejected_at": now_iso()})
            rejected.sort(key=lambda x: (x["platform"], x["version_code"]))
        elif state != "built":
            h["builds"].append(dict(bd, store=state, store_at=now_iso()))
            h["builds"].sort(key=lambda x: (x["platform"], x["version_code"]))
        if rejected:
            h["rejected"] = rejected
        else:
            h.pop("rejected", None)
        self.dirty.add(f"store/{bundle}.json")

    def set_store(self, bundle, platform, vc, state):
        """submitted / live / removed → ghi (cập nhật) dòng trong store/<b>.json;
        rejected (chỉ từ submitted) / built → bỏ khỏi `builds` (không còn trong
        manifest; bản trước của app giữ nguyên)."""
        if state not in STORE_STATES:
            raise RegError(f"trạng thái store lạ: {state}")
        bd = self.find_build(bundle, platform, vc)
        if not bd:
            raise RegError(f"không có build {bundle}/{platform}/{vc} trong registry")
        cur = self.store_state(bundle, platform, vc)
        if state == "rejected" and cur != "submitted":
            raise RegError(f"{bundle}/{platform}/{vc} đang {cur} — chỉ bản submitted mới chuyển sang rejected")
        if state != cur:
            self._put_store(bundle, bd, state)

    def add_patch(self, file, hash_, size, requires, min_force_update=0, envs=()):
        # Trùng = cùng nội dung VÀ cùng requires. Bytecode có thể y hệt dù host
        # đổi version package (module chỉ tham chiếu theo tên) → requires khác thì
        # ra version mới, nếu không ABI host mới không có patch nào khớp.
        for v, p in self.patches.items():
            if p["hash"].lower() == hash_.lower() and p.get("requires") == requires:
                self.set_patch_envs(v, sorted(set(p.get("envs") or []) | set(envs)))
                return v, False
        v = (max(self.patches) if self.patches else 0) + 1
        self.patches[v] = {
            "version": v, "file": file, "hash": hash_.lower(), "size": int(size),
            "min_force_update": int(min_force_update), "published_at": now_iso(),
            "retracted": False, "requires": requires, "envs": sorted(set(envs)),
        }
        self.dirty.add(f"patches/v{v}.json")
        return v, True

    def set_patch_envs(self, v, envs):
        if v not in self.patches:
            raise RegError(f"không có patch v{v}")
        self.patches[v]["envs"] = sorted(set(envs))
        self.dirty.add(f"patches/v{v}.json")

    def set_min_force_update(self, v, m):
        if v not in self.patches:
            raise RegError(f"không có patch v{v}")
        if not 0 <= m <= v:
            raise RegError(f"min_force_update phải trong 0..{v} (máy đang chạy patch < M mới bị ép, M > v{v} vô nghĩa)")
        self.patches[v]["min_force_update"] = m
        self.dirty.add(f"patches/v{v}.json")

    def retract(self, v):
        if v not in self.patches:
            raise RegError(f"không có patch v{v}")
        self.patches[v]["retracted"] = True
        self.dirty.add(f"patches/v{v}.json")

    def set_policy(self, env=None, **kw):
        """env=None → mặc định chung; env → chỉ ghi đè cho env đó."""
        if env:
            self.policy.setdefault("envs", {}).setdefault(env, {}).update(kw)
        else:
            self.policy.update(kw)
        self.dirty.add("policy.json")

    def policy_for(self, env):
        pol = {k: v for k, v in self.policy.items() if k != "envs"}
        pol.update((self.policy.get("envs") or {}).get(env) or {})
        return pol

    def scoped(self, env, members=None):
        """Bản nhìn của 1 env: chỉ app thuộc env + patch đưa lên env + policy env.
        Dùng chung abis / dict bundle / dirty với bản gốc → set_bundle (vd tra
        được ios_app_id) vẫn được ghi."""
        if members is None:
            members = set(apps_in_env(env))
        s = Registry(self.root)
        s.env = env
        s.abis = self.abis
        s.bundles = {b: v for b, v in self.bundles.items() if b in members}
        s.hosts = {b: h for b, h in self.hosts.items() if b in members}
        s.store = {b: h for b, h in self.store.items() if b in members}
        s.patches = {v: p for v, p in self.patches.items() if patch_in_env(p, env)}
        s.policy = self.policy_for(env)
        s.dirty = self.dirty
        return s

    def set_bundle(self, b, **kw):
        self.bundle(b).update(kw)
        self.dirty.add("bundles.json")


# ════════════════════════════════════════════════════════════ Store links
def _http_get(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "dynpub-registry/1"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def lookup_ios_app_id(bundle, countries):
    """iTunes lookup theo bundle id → trackId (None nếu không ra / offline)."""
    if OFFLINE:
        return None
    for cc in countries or ["us"]:
        try:
            _, body = _http_get(f"https://itunes.apple.com/lookup?bundleId={bundle}&country={cc}")
            res = json.loads(body.decode("utf-8")).get("results") or []
            if res and res[0].get("trackId"):
                return int(res[0]["trackId"])
        except Exception:
            continue
    return None


class Links:
    """Sinh link store của 1 bundle. iOS cần Apple ID số: khai tay
    (`ios_app_id`) hoặc tra iTunes 1 lần rồi ghi lại vào bundles.json."""

    def __init__(self, reg):
        self.reg = reg
        self._tried = set()

    def store_url(self, bundle, platform):
        if platform == "android":
            return f"market://details?id={bundle}"
        b = self.reg.bundles.get(bundle) or {}
        app_id = b.get("ios_app_id")
        if not app_id and bundle not in self._tried and bundle in self.reg.bundles:
            self._tried.add(bundle)
            app_id = lookup_ios_app_id(bundle, self.reg.policy.get("ios_lookup_countries"))
            if app_id:
                self.reg.set_bundle(bundle, ios_app_id=app_id)
        return f"https://apps.apple.com/app/id{app_id}" if app_id else None


# ════════════════════════════════════════════════════════════ Tính toán
def compute_compat(reg):
    """abi_id → {max_patch, first_break}."""
    lv = reg.live_versions()
    out = {}
    for aid, a in sorted(reg.abis.items()):
        prov = a["provides"]
        results = {}
        for v in lv:
            good, reasons = compatible(prov, reg.patches[v]["requires"])
            results[v] = (good, reasons)
        good_vs = [v for v in lv if results[v][0]]
        mx = good_vs[-1] if good_vs else 0
        brk = next(({"patch": v, "reason": "; ".join(results[v][1])}
                    for v in lv if v > mx and not results[v][0]), None)
        out[aid] = {"max_patch": mx, "first_break": brk}
    return out


def remind_patch(reg, ev, bundle, platform, vc):
    """Bản build chưa có patch hợp (ABI mới sau [11], hoặc patch mới nhất của
    env không hợp) → nhắc ra patch mới + deploy, kẻo máy cài không nhận gì."""
    env = app_env(bundle)
    if env not in ev.envs:
        return
    bd = reg.find_build(bundle, platform, vc)
    if bd is None:
        return
    c = ev[env].compat.get(bd["abi_id"])
    if not c:
        return
    who = f"{bundle}/{platform}/{vc}"
    if not c["max_patch"]:
        warn(f"[{env}] {who}: CHƯA có patch nào chạy được trên bản build này"
             + (f" (v{c['first_break']['patch']}: {c['first_break']['reason']})" if c["first_break"] else ""))
    elif c["first_break"]:
        warn(f"[{env}] {who}: chỉ chạy tới v{c['max_patch']} — v{c['first_break']['patch']} không hợp "
             f"({c['first_break']['reason']})")
    else:
        return
    warn(f"→ nhớ RA PATCH MỚI cho host này: bash tools/dynpub.sh → [1] (env {env}) → deploy env {env}")


def store_build(reg, bundle, platform):
    """Build `live` có version_code lớn nhất của bundle + platform (None nếu không có)."""
    lives = [bd for b, bd in reg.builds(bundle) if bd["platform"] == platform and bd["store"] == "live"]
    return max(lives, key=lambda x: x["version_code"]) if lives else None


def compute_actions(reg, compat, links):
    """→ ({(bundle, platform, vc): row}, errors, warnings). row: target, action,
    url, why (lý do force/soft), via ('own'|'redirect'|None)."""
    latest = reg.latest()
    pol = reg.policy
    min_allowed = int(pol.get("min_allowed_patch") or 0)
    rows, errors, warnings = {}, [], []

    def target_of(bd):
        return compat.get(bd["abi_id"], {}).get("max_patch", 0)

    def forced_by_vc(b, bd):
        fv = (reg.bundles.get(b, {}).get("force_vc") or {}).get(bd["platform"]) or {}
        below = int(fv.get("below") or 0)
        return below if below and bd["version_code"] < below else 0

    def is_forced(b, bd):
        return target_of(bd) < min_allowed or bool(forced_by_vc(b, bd))

    def replacement(platform):
        """App thay thế CHUNG (chỉ env prod — policy.envs.prod.replacement_app)."""
        return (pol.get("replacement_app") or {}).get(platform)

    def check_redirect(dest, platform, label, as_error):
        """App thay thế phải active, có build live trên platform, build đó không bị force."""
        sink = errors if as_error else warnings
        if dest not in reg.bundles:
            sink.append(f"{label}: app thay thế {dest} chưa đăng ký hoặc không cùng env {reg.env or ''}")
            return False
        if reg.bundles[dest].get("status") != "active":
            sink.append(f"{label}: app thay thế {dest} không còn active")
            return False
        sb = store_build(reg, dest, platform)
        if not sb:
            sink.append(f"{label}: app thay thế {dest} không có build {platform} live trên store")
            return False
        if is_forced(dest, sb):
            sink.append(f"{label}: build live của app thay thế {dest} ({platform} vc{sb['version_code']}) "
                        f"cũng bị force → user bị đẩy sang rồi lại bị force tiếp")
            return False
        return True

    checked = {}
    for b, bd in reg.builds():
        p, vc = bd["platform"], bd["version_code"]
        key = (b, p, vc)
        target = target_of(bd)
        bun = reg.bundles.get(b, {})
        sb = store_build(reg, b, p)
        store_max = target_of(sb) if sb else 0
        row = {"target": target, "action": "none", "url": None, "why": None, "via": None,
               "store": bd["store"], "abi_id": bd["abi_id"]}
        vc_below = forced_by_vc(b, bd)
        if target < min_allowed or vc_below:
            row["action"] = "force"
            if vc_below:
                row["why"] = f"version_code {vc} < {vc_below} (force-vc)"
                own_ok = bool(sb) and sb["version_code"] >= vc_below
            else:
                row["why"] = f"chỉ chạy tới v{target} < min_allowed v{min_allowed}"
                own_ok = bool(sb) and store_max >= min_allowed
            # App còn sống + store có bản cao hơn đạt ngưỡng → update chính nó;
            # không thì sang app thay thế chung (prod).
            if own_ok and bun.get("status") != "retired":
                row["url"] = links.store_url(b, p)
                row["via"] = "own"
            else:
                dest = replacement(p)
                if not dest or dest == b:
                    errors.append(
                        f"{b}/{p}/{vc}: bị force nhưng "
                        + ("app đã chết" if bun.get("status") == "retired" else "store của app chưa có bản cao hơn đạt ngưỡng")
                        + (f" và app thay thế chung {p} chính là app này (menu [8] → App thay thế chung)" if dest == b
                           else " và chưa có app thay thế chung (menu [8] → App thay thế chung)" if reg.env == REPLACE_ENV
                           else f" — env {reg.env} không có app thay thế chung (chỉ {REPLACE_ENV})")
                        + " → user kẹt")
                else:
                    ck = (dest, p, "force")
                    if ck not in checked:
                        checked[ck] = check_redirect(dest, p, f"force {p} → {dest}", True)
                    row["url"] = links.store_url(dest, p)
                    row["via"] = "redirect"
            if row["via"] and not row["url"]:
                errors.append(
                    f"{b}/{p}/{vc}: bị force nhưng không sinh được link (iOS thiếu ios_app_id?)")
        elif target < latest and pol.get("soft_prompt", True):
            if bun.get("status") == "retired":
                # App chết: store của nó không dùng được → mời sang app thay thế chung.
                dest = replacement(p)
                if dest and dest != b:
                    ck = (dest, p, "soft")
                    if ck not in checked:
                        checked[ck] = check_redirect(dest, p, f"soft {b} → {dest}", False)
                    if checked[ck]:
                        row.update(action="soft", url=links.store_url(dest, p), via="redirect",
                                   why=f"chạy tới v{target}, app đã chết → mời sang {dest}")
            elif store_max > target:
                row.update(action="soft", url=links.store_url(b, p), via="own",
                           why=f"chạy tới v{target}, store đã có bản chạy tới v{store_max}")
            if row["action"] == "soft" and not row["url"]:
                warnings.append(f"{b}/{p}/{vc}: SOFT nhưng không sinh được link → không mời")
                row.update(action="none", via=None)
        rows[key] = row

    if min_allowed and min_allowed > latest:
        errors.append(f"min_allowed_patch v{min_allowed} lớn hơn patch mới nhất v{latest} → MỌI máy bị force")
    for p in PLATFORMS:
        dead = sorted({b for b, bd in reg.builds() if bd["platform"] == p
                       and reg.bundles.get(b, {}).get("status") == "retired"})
        if dead and not replacement(p):
            warnings.append(f"app đã chết {', '.join(dead)}: chưa có app thay thế chung {p}"
                            + (" (menu [8] → App thay thế chung)" if reg.env == REPLACE_ENV
                               else f" — env {reg.env} không có app thay thế (chỉ {REPLACE_ENV}) → user không được mời"))
    if latest and compat and not any(c["max_patch"] == latest for c in compat.values()):
        warnings.append(f"patch mới nhất v{latest} chưa bản build nào chạy được (cần build host mới?)")
    return rows, errors, warnings


def build_manifest(reg, rows):
    pol = reg.policy
    hosts, used = {}, set()
    for (b, p, vc), row in sorted(rows.items()):
        e = {"patch": row["target"]}
        if row["action"] != "none" and row["url"]:
            e["action"] = row["action"]
            e["url"] = row["url"]
        hosts.setdefault(b, {}).setdefault(p, {})[str(vc)] = e
        if row["target"]:
            used.add(row["target"])
    patches = {}
    for v in sorted(used):
        p = reg.patches[v]
        patches[str(v)] = {"file": p["file"], "hash": p["hash"], "size": p["size"],
                           "min_force_update": p.get("min_force_update", 0)}
        if p.get("gz_size"):
            # Host mới tải bản nén (giải nén rồi verify `hash` của bytecode);
            # host cũ không biết 2 field này → vẫn tải `file` như trước.
            patches[str(v)].update(gz_file=gz_name(p["file"]), gz_size=p["gz_size"])
    return {
        "schema": 1,
        "generated_at": now_iso(),
        "latest": reg.latest(),
        "min_allowed_patch": int(pol.get("min_allowed_patch") or 0),
        "soft_prompt_interval_hours": int(pol.get("soft_prompt_interval_hours") or 24),
        "patches": patches,
        "hosts": hosts,
    }


def patches_dir():
    return os.path.join(PUBLISH, "patches")


def manifest_dir(env):
    return os.path.join(PUBLISH, env, "manifest")


def manifest_path(env, bundle):
    return os.path.join(manifest_dir(env), f"{bundle}.json")


def local_manifests(env):
    """{bundle: đường dẫn} của manifest đã sinh cho env."""
    d = manifest_dir(env)
    if not os.path.isdir(d):
        return {}
    return {f[:-5]: os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".json")}


def split_manifest(combined, bundles):
    """Manifest gộp của 1 env → {bundle: manifest riêng của app}. Cùng schema
    (app tra `hosts[bundle][platform][vc]`), chỉ còn dòng của app đó + patch
    app đó dùng. App chưa có bản build nào vẫn có file (hosts rỗng → fail-open)."""
    out = {}
    for b in sorted(bundles):
        h = combined["hosts"].get(b, {})
        used = {str(e["patch"]) for p in h.values() for e in p.values() if e.get("patch")}
        m = {k: v for k, v in combined.items() if k not in ("hosts", "patches")}
        m["bundle"] = b
        m["hosts"] = {b: h}
        m["patches"] = {v: p for v, p in combined["patches"].items() if v in used}
        out[b] = m
    return out


def ensure_patch_file(p):
    """Đưa bytecode của patch về publish/patches nếu thiếu: lấy từ ARCHIVE, không
    có thì tải từ rs_domain các env — luôn kiểm hash. → True nếu có file đúng."""
    path = os.path.join(patches_dir(), p["file"])
    if os.path.isfile(path):
        return sha256_file(path) == p["hash"]
    os.makedirs(patches_dir(), exist_ok=True)
    arch = os.path.join(ARCHIVE, p["file"])
    if os.path.isfile(arch) and sha256_file(arch) == p["hash"]:
        shutil.copyfile(arch, path)
        info(f"{p['file']}: lấy lại từ {os.path.relpath(ARCHIVE, ROOT)}")
        return True
    if OFFLINE:
        return False
    for t in load_envs().values():
        if not t["rs_domain"]:
            continue
        url = f"{t['rs_domain']}/app/{p['file']}"
        try:
            _, body = _http_get(url, timeout=60)
        except Exception:
            continue
        if hashlib.sha256(body).hexdigest() == p["hash"]:
            with open(path, "wb") as f:
                f.write(body)
            archive_patch_file(path)
            info(f"{p['file']}: tải lại từ {url}")
            return True
    return False


def gz_name(file):
    return file + ".gz"


def ensure_gz(p):
    """Sinh publish/patches/<file>.gz từ bytecode thô (mtime=0 → cùng input
    ra cùng byte). Không lưu ARCHIVE — luôn sinh lại được. → size bản nén,
    None nếu không có bytecode thô đúng hash."""
    gz = os.path.join(patches_dir(), gz_name(p["file"]))
    if os.path.isfile(gz):
        return os.path.getsize(gz)
    if not ensure_patch_file(p):
        return None
    with open(os.path.join(patches_dir(), p["file"]), "rb") as f:
        data = gzip.compress(f.read(), compresslevel=9, mtime=0)
    with open(gz + ".tmp", "wb") as f:
        f.write(data)
    os.replace(gz + ".tmp", gz)
    return len(data)


def backfill_gz(reg):
    """Patch chưa có bản nén (đăng ký trước khi có gz) → sinh .gz + ghi gz_size."""
    for v, p in sorted(reg.patches.items()):
        if p.get("gz_size") or p.get("retracted"):
            continue
        n = ensure_gz(p)
        if n:
            p["gz_size"] = n
            reg.dirty.add(f"patches/v{v}.json")
            info(f"v{v}: thêm bản nén {gz_name(p['file'])} ({p['size'] / 1e6:.1f}MB → {n / 1e6:.1f}MB)")


def archive_patch_file(path):
    os.makedirs(ARCHIVE, exist_ok=True)
    dst = os.path.join(ARCHIVE, os.path.basename(path))
    if not os.path.isfile(dst):
        shutil.copyfile(path, dst)


def check_patch_files(manifest, errors):
    for v, p in sorted(manifest["patches"].items(), key=lambda x: int(x[0])):
        path = os.path.join(patches_dir(), p["file"])
        if not ensure_patch_file(p):
            if os.path.isfile(path):
                errors.append(f"v{v}: {p['file']} lệch hash so với registry")
            else:
                errors.append(f"v{v}: thiếu {p['file']} (không có trong publish/patches, "
                              f"{os.path.relpath(ARCHIVE, ROOT)}, lẫn rs_domain) → máy tải 404")
        elif p.get("gz_file") and not ensure_gz(p):
            errors.append(f"v{v}: không sinh được {p['gz_file']}")


class Result:
    """manifest = bản gộp cả env (tính toán / kiểm file / in), manifests =
    {bundle: manifest riêng} — thứ được ghi + deploy."""

    def __init__(self, compat, rows, manifest, errors, warnings, env=None, latest=0, manifests=None):
        self.compat, self.rows, self.manifest = compat, rows, manifest
        self.errors, self.warnings = errors, warnings
        self.env, self.latest = env, latest
        self.manifests = manifests or {}


class Evaluation:
    """Kết quả mọi env: ev[env] → Result; errors/warnings gộp (tiền tố [env])."""

    def __init__(self, envs, warnings, errors=None):
        self.envs = envs
        self.errors = list(errors or []) + [f"[{e}] {x}" for e, r in envs.items() for x in r.errors]
        self.warnings = list(warnings) + [f"[{e}] {x}" for e, r in envs.items() for x in r.warnings]

    def __getitem__(self, env):
        return self.envs[env]


def evaluate_env(reg, env, check_files=True, members=None):
    sc = reg.scoped(env, members)
    compat = compute_compat(sc)
    rows, errors, warnings = compute_actions(sc, compat, Links(sc))
    manifest = build_manifest(sc, rows)
    if check_files:
        check_patch_files(manifest, errors)
    return Result(compat, rows, manifest, errors, warnings, env, sc.latest(),
                  split_manifest(manifest, sc.bundles))


def evaluate(reg, check_files=True, only=None):
    envs = load_envs()
    cfgs = all_app_cfgs()
    warnings, errors = [], []
    if not envs:
        warnings.append(f"chưa có {os.path.relpath(DEPLOY_FILE, ROOT)} — chưa có env nào, không sinh manifest")
    for b in sorted(reg.bundles):
        e = (cfgs.get(b) or {}).get("env")
        if not e:
            warnings.append(f"{b}: chưa gán env (configs/apps/{b}.json \"env\") → không nằm trong manifest nào")
        elif e not in envs:
            errors.append(f"{b}: env {e} không có trong {os.path.relpath(DEPLOY_FILE, ROOT)}")
    for b, c in cfgs.items():
        e = c.get("env")
        if e in envs and norm_domain(c.get("rs_domain")) != envs[e]["rs_domain"]:
            warnings.append(f"configs/apps/{b}.json: rs_domain {c.get('rs_domain') or '-'} ≠ rs_domain env {e} "
                            f"({envs[e]['rs_domain']}) → chạy: reg sync-configs")
    for b, c in cfgs.items():
        if c.get("env") in envs and not (c.get("api_domain") or "").strip():
            warnings.append(f"configs/apps/{b}.json: api_domain trống — deploy KHÔNG chép giá trị rỗng sang ../configs; "
                            f"điền tay hoặc đặt api_domain mặc định của env {c['env']} rồi `reg sync-configs`")
    for v, p in sorted(reg.patches.items()):
        for e in p.get("envs") or []:
            if e not in envs:
                warnings.append(f"v{v}: env {e} không còn trong deploy.json")
    res = {}
    for e in envs:
        if only and e not in only:
            continue
        members = {b for b, c in cfgs.items() if c.get("env") == e}
        res[e] = evaluate_env(reg, e, check_files, members)
    return Evaluation(res, warnings, errors)


def report_issues(res):
    for w in res.warnings:
        warn(w)
    for e in res.errors:
        bad(e)


def _same_manifest(a, b):
    strip = lambda m: {k: v for k, v in (m or {}).items() if k != "generated_at"}  # noqa: E731
    return a is not None and strip(a) == strip(b)


def commit(reg, ev):
    """Ghi registry + compat + manifest mọi env khi không có lỗi. Lỗi → RegError,
    không ghi. Manifest env nào đổi nội dung → ghi + đánh dấu env đó cần deploy."""
    report_issues(ev)
    if ev.errors:
        raise RegError(f"{len(ev.errors)} lỗi — KHÔNG ghi gì (sửa rồi chạy lại)")
    reg.save()
    write_compat(reg, ev)
    changed = []
    for e, r in ev.envs.items():
        wrote = []
        for b, m in r.manifests.items():
            path = manifest_path(e, b)
            if _same_manifest(read_json(path), m):
                continue
            write_json(path, m)
            n = sum(len(x) for x in m["hosts"][b].values())
            wrote.append(f"{b} ({n} bản build, latest v{m['latest']})")
        for b, path in local_manifests(e).items():
            if b not in r.manifests:  # app đã chuyển env / bỏ khỏi registry
                os.remove(path)
                wrote.append(f"bỏ {b}")
        legacy = os.path.join(PUBLISH, e, "manifest.json")
        if os.path.isfile(legacy):  # bố cục cũ: 1 manifest gộp cả env
            os.remove(legacy)
            wrote.append("bỏ manifest.json gộp cũ")
        if wrote:
            changed.append(e)
            ok(f"[{e}] {os.path.relpath(manifest_dir(e), ROOT)}/: {'; '.join(wrote)}")
    prune_publish(ev)
    if changed:
        mark_changed(*changed)
    else:
        ok("đã ghi registry (manifest các env không đổi)")
    return changed


def write_compat(reg, ev):
    write_json(os.path.join(reg.root, "compat.json"), {
        e: {"latest": r.latest, "abis": r.compat} for e, r in ev.envs.items()})


def prune_publish(ev):
    """publish/patches/ chỉ giữ bytecode manifest các env đang trỏ tới (file cũ
    vẫn nằm trên rs_domain — deploy không xoá gì trên server). Dọn bố cục cũ
    publish/app/ (trước khi có env)."""
    keep = {f for r in ev.envs.values() for p in r.manifest["patches"].values()
            for f in (p["file"], p.get("gz_file")) if f}
    d = patches_dir()
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith((".bytecode", ".bytecode.gz")) and f not in keep:
                os.remove(os.path.join(d, f))
    legacy = os.path.join(PUBLISH, "app")
    if os.path.isdir(legacy) and ev.envs:
        shutil.rmtree(legacy)
        info("đã bỏ bố cục cũ publish/app/ (giờ là publish/<env>/ + publish/patches/)")


# ════════════════════════════════════════════════════════════ In bảng
def print_plan(reg, res, bundle=None):
    print()
    if reg.env:
        t = load_envs().get(reg.env) or {}
        print(f"══ env {reg.env}  →  {t.get('rs_domain') or '(chưa có rs_domain)'}/app/manifest/<bundle>.json")
    ra = reg.policy.get("replacement_app") or {}
    print(f"latest = v{reg.latest()}   min_allowed_patch = v{reg.policy.get('min_allowed_patch') or 0}"
          + (f"   app thay thế chung = android:{ra.get('android') or '-'} ios:{ra.get('ios') or '-'}"
             if reg.env == REPLACE_ENV else ""))
    rows = [(k, r) for k, r in sorted(res.rows.items()) if not bundle or k[0] == bundle]
    if not rows:
        info("chưa có bản build nào lên store (registry/store/) — menu [6] để xác nhận")
        return
    w = max(len(f"{b}/{p}/{vc}") for (b, p, vc), _ in rows)
    print(f"  {'host'.ljust(w)}  {'store':9} {'patch':>5}  {'action':6}  mở / lý do")
    for (b, p, vc), r in rows:
        tag = {"force": RED + "force " + RST, "soft": YEL + "soft  " + RST}.get(r["action"], "none  ")
        brk = res.compat.get(r["abi_id"], {}).get("first_break")
        detail = r["url"] or ""
        if r["why"]:
            detail = f"{detail}  {DIM}({r['why']}){RST}"
        if brk:
            detail += f"  {DIM}dừng vì v{brk['patch']}: {brk['reason']}{RST}"
        print(f"  {f'{b}/{p}/{vc}'.ljust(w)}  {r['store']:9} {('v' + str(r['target'])) if r['target'] else '-':>5}  "
              f"{tag}  {detail}")


def print_patch_report(reg, res, v):
    print()
    print(f"== compat v{v}{' [' + reg.env + ']' if reg.env else ''} ==")
    req = reg.patches[v]["requires"]
    for aid, a in sorted(reg.abis.items()):
        good, reasons = compatible(a["provides"], req)
        users = [f"{b}/{bd['platform']}/{bd['version_code']}"
                 + ("" if reg.find_store_build(b, bd["platform"], bd["version_code"]) else " (chưa lên store)")
                 for b, bd in reg.all_builds() if bd["abi_id"] == aid]
        if not users:
            continue
        mark = GRN + "✓" + RST if good else RED + "✗" + RST
        print(f"  {mark} abi {aid}  max v{res.compat[aid]['max_patch']}  ← {', '.join(users)}")
        if not good:
            print(f"      {DIM}{'; '.join(reasons)}{RST}")


# ════════════════════════════════════════════════════════════ Deploy / check-links
def deploy(envs=None, bundle=None, dry_run=False, key_file=None, key_pass=None, copy_cfg=True):
    """Deploy từng env (mặc định: mọi env; --bundle B → env của B, chỉ config của B).

    Mỗi env, theo thứ tự: bytecode → manifest lên server (<ssh.path>/app/…),
    đọc lại hash qua SFTP, RỒI MỚI chép config app (không lên server) sang
    ../configs/apps/ (user tự commit + push lên GitHub — app đọc config ở đó →
    đổi rs_domain / đổi env thì máy chỉ chuyển khi domain mới đã đủ file)."""
    all_envs = load_envs()
    if not all_envs:
        raise RegError(
            f"chưa cấu hình {os.path.relpath(DEPLOY_FILE, ROOT)} — tạo theo mẫu (tools/README.md). Ví dụ:\n"
            '  {"targets": [{"name": "prod", "rs_domain": "https://rs.example.site",\n'
            '                "ssh": {"host": "1.2.3.4", "port": 22, "user": "deploy", "path": "/var/www/rs"}}]}\n'
            "  File lên <ssh.path>/app/<file>; key SSH đặt trong .env (cp .env.example .env).")
    if bundle:
        e = app_env(bundle)
        if not e:
            raise RegError(f"{bundle} chưa gán env — menu [9] → Đổi env của app")
        envs = [e]
    for e in envs or []:
        need_env(e, all_envs)
    failed, pushed, done = 0, [], []
    for e in envs or list(all_envs):
        t = all_envs[e]
        mans = local_manifests(e)
        if bundle:
            if bundle not in mans:
                raise RegError(f"chưa có manifest của {bundle} ({os.path.relpath(manifest_path(e, bundle), ROOT)}) "
                               f"— app chưa đăng ký registry? chạy `reg regen`")
            mans = {bundle: mans[bundle]}
        if not mans:
            info(f"[{e}] chưa có app nào trong registry — không có manifest để deploy")
            done.append(e)
            continue
        files = sorted({f for path in mans.values() for p in read_json(path)["patches"].values()
                        for f in (p["file"], p.get("gz_file")) if f})
        for f in files:
            if not os.path.isfile(os.path.join(patches_dir(), f)):
                raise RegError(f"[{e}] thiếu {f} trong publish/patches (chạy `reg validate`)")
        cfgs = [bundle] if bundle else apps_in_env(e)
        for b in cfgs:
            c = read_app_cfg(b)
            if norm_domain(c.get("rs_domain")) != t["rs_domain"]:
                raise RegError(f"configs/apps/{b}.json: rs_domain {c.get('rs_domain') or '-'} ≠ env {e} "
                               f"({t['rs_domain']}) — chạy `reg sync-configs` trước")
        print(f"== deploy [{e}] → {t['rs_domain']}/app/{' [dry-run]' if dry_run else ''} ==")
        info(f"manifest: {', '.join(mans)} · patch: {', '.join(files) or '-'}")
        before = failed
        if t.get("ssh"):
            failed += _deploy_sftp(t, files, mans, dry_run, key_file, key_pass)
        elif t.get("upload"):
            failed += _deploy_cmd(t, files, mans, dry_run)
        else:
            raise RegError(f"target {e}: cần `ssh` (hoặc `upload`)")
        # KHÔNG tải lại qua rs_domain để kiểm (prod không vào được qua VPN) —
        # đã kiểm hash qua SFTP ngay trên server.
        if not dry_run and failed == before and not bundle:
            done.append(e)
        pushed += cfgs
    if failed:
        raise RegError(f"{failed} env chưa deploy xong — KHÔNG chép config sang ../configs (sửa rồi deploy lại)")
    if copy_cfg and pushed:
        copy_configs(pushed, dry_run)
    unmark_changed(*done)


def _deploy_sftp(t, files, mans, dry_run, key_file, key_pass):
    try:
        with deploy_sftp.SftpTarget(t, key_file, key_pass, dry_run) as s:
            info(f"thư mục server: {s.dir}")
            for f in files:
                path = os.path.join(patches_dir(), f)
                if s.size(f) == os.path.getsize(path):
                    info(f"{f}: server đã có — bỏ qua")
                    continue
                s.put(path, f)
            for b, path in mans.items():
                s.put(path, f"manifest/{b}.json")
            if dry_run:
                return 0
            wrong = [b for b, path in mans.items() if s.sha256(f"manifest/{b}.json") != sha256_file(path)]
            if wrong:
                bad(f"manifest trên server (đọc qua SFTP) KHÁC bản local: {', '.join(wrong)}")
                return 1
            ok(f"{len(mans)} manifest trên server khớp bản local (SFTP)")
            return 0
    except deploy_sftp.DeployError as e:
        raise RegError(str(e))
    except (IOError, OSError) as e:
        raise RegError(f"SFTP lỗi ({t.get('name')}): {e}")


def _deploy_cmd(t, files, mans, dry_run):
    """Cách cũ: lệnh shell `upload` cho từng file (không upload config)."""
    if dry_run:
        info("dry-run: target dùng lệnh upload — bỏ qua")
        return 0
    base = t["rs_domain"]
    for f in files:
        path = os.path.join(patches_dir(), f)
        if _remote_size(f"{base}/app/{f}") == os.path.getsize(path):
            info(f"{f}: server đã có — bỏ qua")
            continue
        _upload(t["upload"], path, f)
    for b, path in mans.items():
        _upload(t["upload"], path, f"manifest/{b}.json")
    return 0


def copy_configs(bundles, dry_run=False):
    """Chép configs/apps/<b>.json → ../configs/apps/<b>.json. Chỉ đè key tool
    quản lý, GIỮ key chỉ có bên kia (vd force_update), không ghi giá trị rỗng.
    KHÔNG commit / push — user tự làm trong repo configs."""
    root = os.path.dirname(CONFIGS_OUT)
    if not os.path.isdir(root):
        raise RegError(f"không thấy {root} — clone repo Vulcan-dev-25/configs về đó")
    print(f"== config → {CONFIGS_OUT} ==")
    changed = []
    for b in sorted(set(bundles)):
        dst = os.path.join(CONFIGS_OUT, f"{b}.json")
        cur = read_json(dst, {}) or {}
        merged = dict(cur)
        # Không bao giờ ghi đè bằng giá trị rỗng (config local chưa điền ≠ muốn xoá).
        merged.update({k: v for k, v in read_app_cfg(b).items() if v not in ("", None)})
        if merged == cur:
            continue
        diff = {k: v for k, v in merged.items() if cur.get(k) != v}
        info(f"apps/{b}.json: {json.dumps(diff, ensure_ascii=False)}" + (" [dry-run]" if dry_run else ""))
        changed.append(b)
        if not dry_run:
            os.makedirs(CONFIGS_OUT, exist_ok=True)
            with open(dst, "w", encoding="utf-8") as f:
                json.dump(merged, f, indent=2, ensure_ascii=False)
                f.write("\n")
    if not changed:
        ok("config bên ../configs đã khớp — không đổi gì")
    elif not dry_run:
        ok(f"đã chép {len(changed)} config sang {CONFIGS_OUT}")
        warn(f"NHỚ commit + push repo configs: cd {root} && git add apps && git commit && git push "
             f"— app chỉ đọc config mới sau khi lên GitHub")


def _remote_size(url):
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "dynpub-registry/1"})
        with urllib.request.urlopen(req, timeout=8) as r:
            n = r.headers.get("Content-Length")
            return int(n) if n else None
    except Exception:
        return None


def _upload(template, path, name):
    cmd = template.replace("{file}", shlex.quote(path)).replace("{name}", shlex.quote(name))
    print(f"  $ {cmd}")
    if subprocess.run(cmd, shell=True).returncode != 0:
        raise RegError(f"upload {name} thất bại")


def check_links(reg):
    """Link store của build live + app thay thế còn sống không (cron hằng ngày)."""
    if OFFLINE:
        raise RegError("REGISTRY_OFFLINE=1 — check-links cần mạng")
    targets = set()
    for res in evaluate(reg, check_files=False).envs.values():
        for (b, p, _), r in res.rows.items():
            if r["url"]:
                dest = b if r["via"] == "own" else None
                targets.add((r["url"], p, dest))
    links = Links(reg)
    ra = reg.policy_for(REPLACE_ENV).get("replacement_app") or {}
    for b in reg.bundles:
        for p in PLATFORMS:
            if store_build(reg, b, p) or ra.get(p) == b:
                url = links.store_url(b, p)
                if url:
                    targets.add((url, p, b))
                else:
                    warn(f"{b}/{p}: chưa có link store"
                         + (" (iOS chưa có Apple ID — menu [9] → Khai Apple ID)" if p == "ios" else "")
                         + " → không kiểm được, popup cập nhật / chuyển app sẽ không mở được")
    dead = 0
    if not targets:
        warn("không có link nào để kiểm (chưa app nào có bản live kèm link store)")
        return 0
    for url, p, b in sorted(targets):
        alive = _link_alive(url, p)
        if alive is None:
            warn(f"{url}  không kiểm được (mạng / store trả mã lạ) — thử lại sau")
        elif alive:
            ok(f"{url}  sống")
        else:
            bad(f"{url}  KHÔNG mở được (app bị gỡ?)")
            dead += 1
    if dead:
        raise RegError(f"{dead} link chết — sửa trước khi user bấm vào (menu [6]/[9]/[8])")
    return len(targets)


def _link_alive(url, platform):
    if url.startswith("market://details?id="):
        bid = url.split("id=", 1)[1]
        try:
            status, _ = _http_get(f"https://play.google.com/store/apps/details?id={bid}&hl=en")
            return status == 200
        except urllib.error.HTTPError as e:
            return False if e.code == 404 else None
        except Exception:
            return None
    m = re.search(r"/id(\d+)", url)
    if m:
        try:
            _, body = _http_get(f"https://itunes.apple.com/lookup?id={m.group(1)}")
            return bool(json.loads(body.decode()).get("resultCount"))
        except Exception:
            return None
    return None


# ════════════════════════════════════════════════════════════ CLI
def _opt(args, name, default=None):
    if name in args:
        i = args.index(name)
        if i + 1 >= len(args):
            raise RegError(f"{name} cần giá trị")
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default


def _flag(args, name):
    if name in args:
        args.remove(name)
        return True
    return False


def _none(v):
    return None if v in (None, "", "none", "-") else v


def git_rev():
    try:
        return subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return None


def gen_texts():
    """Sinh text host token-hoá cho MỌI configs/apps/*.json (tools/cmd/gentexts.py).

    Idempotent — chạy sau khi tạo/đổi config app để file mới có khối `texts`."""
    script = os.path.join(ROOT, "tools", "cmd", "gentexts.py")
    r = subprocess.run([sys.executable, script], cwd=ROOT)
    if r.returncode != 0:
        warn("gentexts.py lỗi — chạy tay: python3 tools/cmd/gentexts.py")


# Trường DANH TÍNH/KÝ riêng từng app — copy folder app khác sang KHÔNG được
# dùng chung (trùng team/profile/keystore → ký nhầm app). [9] xoá trắng.
_APP_YAML_RESET_FIELDS = (
    "keystore", "key_alias",
    "team_id", "profile", "adhoc_profile", "appstore_profile", "export_options",
)
_RESET_RE = re.compile(
    r"^(?P<ind>\s*)(?P<key>" + "|".join(_APP_YAML_RESET_FIELDS) +
    r")(?P<col>:\s*)(?P<val>[^#\n]*?)(?P<sp>\s*)(?P<cmt>#.*)?$")


def fix_app_yaml_bundle_id(bundle):
    """apps/<bundle>/ đã có sẵn (vd copy từ app khác):
    - sửa dòng `bundle_id:` cho khớp tên thư mục nếu đang sai (idt check vốn
      die khi lệch);
    - XOÁ TRẮNG các trường ký/danh tính ([_APP_YAML_RESET_FIELDS]) để không
      trùng app gốc (ký nhầm).
    Giữ nguyên phần còn lại — display_name / icon là của người dùng."""
    y = os.path.join(APPS_DIR, bundle, "app.yaml")
    if not os.path.isfile(y):
        warn(f"apps/{bundle}/ có sẵn nhưng thiếu app.yaml — "
             f"xoá folder rồi chạy lại [9] để lấy khung, hoặc tạo app.yaml tay")
        return
    lines = open(y, encoding="utf-8").read().splitlines(keepends=True)
    changed_from = None
    cleared = []
    for i, ln in enumerate(lines):
        if changed_from is None and ln.startswith("bundle_id:"):
            cur = ln.split(":", 1)[1].strip().strip("'\"")
            if cur != bundle:
                changed_from = cur or "(trống)"
                lines[i] = f"bundle_id: {bundle}\n"
            else:
                changed_from = False  # có dòng, đúng rồi
            continue
        m = _RESET_RE.match(ln)
        if m and m.group("val").strip().strip("'\""):
            cleared.append(m.group("key"))
            nl = "\n" if ln.endswith("\n") else ""
            cmt = m.group("cmt")
            tail = (m.group("sp") + cmt) if cmt else ""
            lines[i] = f'{m.group("ind")}{m.group("key")}{m.group("col")}""{tail}{nl}'
    if changed_from is None:
        lines.insert(0, f"bundle_id: {bundle}\n")
        changed_from = "(thiếu)"
    if changed_from or cleared:
        with open(y, "w", encoding="utf-8") as f:
            f.writelines(lines)
    if changed_from:
        ok(f"apps/{bundle}/app.yaml: bundle_id {changed_from} → {bundle}")
    if cleared:
        ok(f"apps/{bundle}/app.yaml: xoá trắng {', '.join(cleared)} (tránh trùng app gốc)")


def scaffold_app(bundle):
    """apps/<bundle>/: app.yaml + main_app/ (chép từ apps/_reference/main_app)."""
    d = os.path.join(APPS_DIR, bundle)
    if os.path.isdir(d):
        return False
    os.makedirs(os.path.join(d, "assets"), exist_ok=True)
    src = os.path.join(APPS_DIR, "_reference", "main_app")
    if not os.path.isdir(src):
        src = os.path.join(ROOT, "apps", "_reference", "main_app")
    if os.path.isdir(src):
        shutil.copytree(src, os.path.join(d, "main_app"),
                        ignore=shutil.ignore_patterns("build", ".dart_tool", "*.iml", "pubspec.lock",
                                                      "android", "ios", "macos"))
    with open(os.path.join(d, "app.yaml"), "w", encoding="utf-8") as f:
        f.write(APP_YAML_TEMPLATE.format(bundle=bundle))
    return True


APP_YAML_TEMPLATE = """\
# Thông tin build của app — dynpub.sh đọc khi build host cho bundle này.
# KHÔNG commit file ký/mật khẩu: chỉ ghi đường dẫn (ngoài repo).
bundle_id: {bundle}
display_name: App
# Icon vuông PNG >= 1024x1024 (tương đối thư mục này). Bỏ trống = giữ icon mặc định của app/.
icon: assets/icon.png
android:
  keystore: ""          # vd ~/keys/app.jks — trống = ký debug
  key_alias: ""
  # mật khẩu: env APP_KEYSTORE_PASSWORD / APP_KEY_PASSWORD, thiếu thì dynpub hỏi
ios:
  # Trống → dynpub tự tìm profile đã cài (double-click .mobileprovision) khớp
  # bundle id này rồi ghi vào đây. Ghi tay để chọn team / profile khác.
  # Profile không có trên máy đang build → ký Automatic (Xcode đã đăng nhập
  # tài khoản của team, tự tạo/tải profile).
  team_id: ""           # BẮT BUỘC khi build iOS — team Apple của bundle id này
  profile: ""           # profile DEVELOPMENT dùng lúc archive (ký Manual)
  adhoc_profile: ""     # profile Ad Hoc dùng lúc export (mode adhoc)
  appstore_profile: ""  # profile App Store dùng lúc export (mode appstore)
  export_options: ""    # tuỳ chọn: plist có sẵn cho adhoc (thay cho tự sinh)
"""


def github_cfg(bundle):
    """Config app đang nằm trong ../configs/apps (repo GitHub configs), {} nếu chưa có."""
    return read_json(os.path.join(CONFIGS_OUT, f"{bundle}.json"), {}) or {}


def default_api_domain(bundle, env, envs):
    """api_domain khi config local trống: bản trong ../configs (app đã chạy) → mặc
    định của env (`api_domain` của target trong deploy.json) → ""."""
    return (github_cfg(bundle).get("api_domain") or "").strip() or \
        ((envs.get(env) or {}).get("api_domain") or "").strip()


def next_version_code(reg, bundle):
    """max(version_code đã đăng ký, last_version_code đã giữ chỗ) + 1."""
    vcs = [bd["version_code"] for _, bd in reg.builds(bundle)]
    vcs.append(int((reg.bundles.get(bundle) or {}).get("last_version_code") or 0))
    return max(vcs) + 1


def _bundle_cfg_set(bundle, env, envs):
    """Gán env cho app: ghi "env" + rs_domain của env vào configs/apps/<b>.json;
    api_domain trống thì điền mặc định (default_api_domain)."""
    t = need_env(env, envs)
    c = read_app_cfg(bundle)
    if not (c.get("api_domain") or "").strip():
        c["api_domain"] = default_api_domain(bundle, env, envs)
    c["env"] = env
    c["rs_domain"] = t["rs_domain_raw"]
    write_json(app_cfg_path(bundle), c)


def _write_deploy_cfg(cfg):
    with open(DEPLOY_FILE + ".tmp", "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(DEPLOY_FILE + ".tmp", DEPLOY_FILE)


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, a = argv[0], list(argv[1:])
    reg = Registry.load()

    if cmd == "list-bundles":
        cfgs = all_app_cfgs()
        for b, v in sorted(reg.bundles.items()):
            print(f"{b}\t{v.get('status', 'active')}\t{(cfgs.get(b) or {}).get('env') or '-'}")
        return 0
    if cmd == "list-envs":
        cfgs = all_app_cfgs()
        for e, t in load_envs().items():
            n = sum(1 for c in cfgs.values() if c.get("env") == e)
            print(f"{e}\t{t['rs_domain'] or '-'}\t{n}\t{(t.get('ssh') or {}).get('path') or '-'}")
        return 0
    if cmd == "apps-in-env":
        print("\n".join(apps_in_env(a[0])))
        return 0
    if cmd == "env-of":
        print(app_env(a[0]) or "")
        return 0
    if cmd == "changed-envs":
        out = read_changed()
        if out:
            print("\n".join(out))
        if _flag(a, "--clear"):
            unmark_changed(*out)
        return 0
    if cmd == "list-builds":
        for b, bd in reg.all_builds(a[0] if a else None):
            print(f"{b}\t{bd['platform']}\t{bd['version_code']}\t{bd.get('version_name', '')}\t"
                  f"{reg.store_state(b, bd['platform'], bd['version_code'])}\t{bd['abi_id']}")
        return 0
    if cmd == "list-patches":
        for v in sorted(reg.patches):
            p = reg.patches[v]
            envs = ",".join(p["envs"]) if p.get("envs") is not None else "*"
            print(f"{v}\t{'retracted' if p.get('retracted') else 'active'}\t{p.get('published_at', '')}\t{envs or '-'}"
                  f"\t{p.get('min_force_update', 0)}")
        return 0
    if cmd == "next-version":
        n = next_version_code(reg, a[0])
        print(f"1.0.{n}+{n}")
        return 0
    if cmd == "reserve-version":
        # Mỗi lần build host (kể cả debug / không lên store / build lỗi) lấy 1
        # số mới → không bao giờ 2 bản build khác nhau trùng version_code.
        b, given = a[0], _opt(a, "--version")
        if given:
            m = re.match(r"^\d+(\.\d+)*\+(\d+)$", given.strip())
            if not m:
                raise RegError(f"version lạ: {given} (dạng 1.0.5+5)")
            vc, ver = int(m.group(2)), given.strip()
            if vc < next_version_code(reg, b):
                warn(f"{b}: version_code {vc} đã dùng (kế tiếp là {next_version_code(reg, b)})")
        else:
            vc = next_version_code(reg, b)
            ver = f"1.0.{vc}+{vc}"
        last = int(reg.bundle(b).get("last_version_code") or 0)
        if vc > last:
            reg.set_bundle(b, last_version_code=vc)
            reg.save()
        print(ver)
        return 0
    if cmd == "redirect-candidates":
        platform = a[0]
        excl = _opt(a, "--exclude")
        env = _opt(a, "--env") or (app_env(excl) if excl else None)
        if not env:
            raise RegError("redirect-candidates cần --env")
        sc = reg.scoped(env)
        mp = _opt(a, "--min-patch")
        if mp is not None:  # đánh giá theo ngưỡng SẮP đặt (chưa ghi)
            reg.set_policy(env=env, min_allowed_patch=int(mp))
            reg.dirty.discard("policy.json")
        res = evaluate_env(reg, env, check_files=False)
        for b, bun in sorted(sc.bundles.items()):
            if b == excl or bun.get("status") != "active":
                continue
            sb = store_build(sc, b, platform)
            if not sb:
                continue
            r = res.rows[(b, platform, sb["version_code"])]
            if r["action"] == "force":
                continue
            print(f"{b}\tlive vc{sb['version_code']}, chạy tới v{r['target']}")
        return 0
    if cmd == "plan":
        bundle = _opt(a, "--bundle")
        only = [_opt(a, "--env") or (app_env(bundle) if bundle else None)]
        ev = evaluate(reg, check_files=False, only=[x for x in only if x] or None)
        for e, res in ev.envs.items():
            print_plan(reg.scoped(e), res, bundle)
        print()
        report_issues(ev)
        return 1 if ev.errors else 0
    if cmd == "validate":
        ev = evaluate(reg)
        report_issues(ev)
        if not ev.errors:
            ok("registry hợp lệ")
        return 1 if ev.errors else 0
    if cmd == "regen":
        backfill_gz(reg)
        commit(reg, evaluate(reg))
        return 0
    if cmd == "deploy":
        envs = []
        while "--env" in a or "--target" in a:
            envs.append(_opt(a, "--env") if "--env" in a else _opt(a, "--target"))
        deploy(envs=envs or None, bundle=_opt(a, "--bundle"), dry_run=_flag(a, "--dry-run"),
               key_file=_opt(a, "--key-file"), key_pass=_opt(a, "--key-pass"),
               copy_cfg=not (_flag(a, "--no-configs") or _flag(a, "--no-github")))
        return 0
    if cmd == "check-links":
        n = check_links(reg)
        if n:
            ok(f"{n} link đã kiểm — không link nào chết")
        return 0

    # ── lệnh ghi ────────────────────────────────────────────────────────────
    envs = load_envs()
    if cmd == "bundle-add":
        b = a[0]
        env = _opt(a, "--env")
        if reg.add_bundle(b):
            ok(f"đã thêm app {b}")
        else:
            info(f"{b} đã có")
        if scaffold_app(b):
            ok(f"đã tạo apps/{b}/ (app.yaml + main_app/) — sửa display_name, icon, ký app trước khi build")
        else:
            # Folder có sẵn (copy từ app khác / tạo tay) → sửa bundle_id lệch.
            fix_app_yaml_bundle_id(b)
        if env:
            _bundle_cfg_set(b, env, envs)
            ok(f"{b}: env {env} (rs_domain {envs[env]['rs_domain_raw']})")
        elif not os.path.isfile(app_cfg_path(b)):
            write_json(app_cfg_path(b), {"api_domain": "", "rs_domain": ""})
            warn(f"đã tạo {os.path.relpath(app_cfg_path(b), ROOT)} chưa có env — reg set-env {b} <env>")
        # Khối `texts` token-hoá cho app mới (token theo bundleId).
        gen_texts()
        api = read_app_cfg(b).get("api_domain")
        if api:
            info(f"{b}: api_domain {api}")
        else:
            warn(f"{b}: api_domain trống — điền trong {os.path.relpath(app_cfg_path(b), ROOT)} hoặc đặt "
                 f"`api_domain` mặc định cho env trong configs/deploy.json rồi chạy `reg sync-configs`")
        mark_changed(env)
    elif cmd == "set-env":
        b, env = a[0], a[1]
        reg.bundle(b)
        old = app_env(b)
        _bundle_cfg_set(b, env, envs)
        ok(f"{b}: env {old or '-'} → {env} (rs_domain {envs[env]['rs_domain_raw']})")
        if not old:
            gen_texts()  # config mới tạo chưa có khối `texts`
        mark_changed(env, old if old in envs else None)
    elif cmd == "set-rs-domain":
        env, url = a[0], a[1].strip()
        path = _opt(a, "--ssh-path")
        need_env(env, envs)
        if not re.match(r"^https?://[^/\s]+", url):
            raise RegError(f"rs_domain không hợp lệ: {url}")
        cfg = read_json(DEPLOY_FILE)
        for t in cfg["targets"]:
            if t.get("name") == env:
                info(f"[{env}] rs_domain {t.get('rs_domain') or t.get('url')} → {url}")
                t["rs_domain"] = url
                t.pop("url", None)
                if path:
                    info(f"[{env}] ssh.path {t.get('ssh', {}).get('path')} → {path}")
                    t.setdefault("ssh", {})["path"] = path
        _write_deploy_cfg(cfg)
        envs = load_envs()
        for b in apps_in_env(env):
            _bundle_cfg_set(b, env, envs)
            ok(f"configs/apps/{b}.json: rs_domain → {url}")
        mark_changed(env)
        warn(f"deploy env {env} để đẩy manifest + bytecode lên domain mới TRƯỚC; deploy xong mới commit config mới "
             f"trong ../configs lên GitHub")
    elif cmd == "set-api-domain":
        env, url = a[0], a[1].strip()
        need_env(env, envs)
        if not re.match(r"^https?://[^/\\s]+", url):
            raise RegError(f"api_domain không hợp lệ: {url}")
        cfg = read_json(DEPLOY_FILE)
        for t in cfg["targets"]:
            if t.get("name") == env:
                info(f"[{env}] api_domain {t.get('api_domain') or '-'} → {url}")
                t["api_domain"] = url
        _write_deploy_cfg(cfg)
        envs = load_envs()
        for b in apps_in_env(env):
            c = read_app_cfg(b)
            c["api_domain"] = url
            write_json(app_cfg_path(b), c)
            ok(f"configs/apps/{b}.json: api_domain → {url}")
        mark_changed(env)
        warn(f"api_domain env {env} → {url} (ghi configs/deploy.json + configs/apps/<app>.json của env này; "
             f"bạn commit + push configs sau để app nhận config mới)")
    elif cmd == "sync-configs":
        for b, c in all_app_cfgs().items():
            e = c.get("env")
            if e not in envs:
                continue
            fix_rs = (c.get("rs_domain") or "").strip() != envs[e]["rs_domain_raw"]
            fix_api = not (c.get("api_domain") or "").strip() and default_api_domain(b, e, envs)
            if fix_rs or fix_api:
                _bundle_cfg_set(b, e, envs)
                n = read_app_cfg(b)
                ok(f"configs/apps/{b}.json: rs_domain {n['rs_domain']} · api_domain {n['api_domain'] or '-'}")
                mark_changed(e)
    elif cmd == "bundle-retire":
        reg.set_bundle(a[0], status="retired")
        reg.bundle(a[0]).pop("redirect_bundle", None)
    elif cmd == "replacement-app":
        if REPLACE_ENV not in envs:
            raise RegError(f"chưa có env {REPLACE_ENV} trong {os.path.relpath(DEPLOY_FILE, ROOT)}")
        sc = reg.scoped(REPLACE_ENV)
        ra = dict((reg.policy.get("envs") or {}).get(REPLACE_ENV, {}).get("replacement_app") or {})
        for p in PLATFORMS:
            v = _opt(a, f"--{p}")
            if v is None:
                continue
            dest = _none(v)
            if dest:
                if dest not in sc.bundles:
                    raise RegError(f"{dest} không thuộc env {REPLACE_ENV} — app thay thế chung phải là app prod")
                if sc.bundles[dest].get("status") != "active":
                    raise RegError(f"{dest} đã đánh dấu chết — không làm app thay thế được")
                if not store_build(sc, dest, p):
                    raise RegError(f"{dest} chưa có bản {p} live trên store")
            ra[p] = dest
            info(f"app thay thế chung {p}: {dest or '(bỏ trống)'}")
        reg.set_policy(env=REPLACE_ENV, replacement_app=ra)
    elif cmd == "bundle-activate":
        reg.set_bundle(a[0], status="active")
    elif cmd == "ios-app-id":
        reg.set_bundle(a[0], ios_app_id=int(a[1]))
    elif cmd == "force-vc":
        b, p, below = a[0], a[1], int(a[2])
        fv = dict(reg.bundle(b).get("force_vc") or {})
        if below > 0:
            fv[p] = {"below": below}
        else:
            fv.pop(p, None)
        reg.set_bundle(b, force_vc=fv)
    elif cmd == "store":
        reg.set_store(a[0], a[1], int(a[2]), a[3])
        ev = evaluate(reg)
        if a[3] in ("submitted", "live"):
            remind_patch(reg, ev, a[0], a[1], int(a[2]))
        commit(reg, ev)
        return 0
    elif cmd == "retract":
        reg.retract(int(a[0]))
    elif cmd == "patch-force":
        v, m = int(a[0]), int(a[1])
        reg.set_min_force_update(v, m)
        info(f"v{v}: min_force_update = {m}" + (f" — máy đang chạy patch < {m} sẽ được nhắc khởi động lại" if m else " (tắt ép restart)"))
    elif cmd == "patch-envs":
        v = int(a[0])
        if v not in reg.patches:
            raise RegError(f"không có patch v{v}")
        cur = set(reg.patches[v].get("envs") or [])
        add, rm, st = _opt(a, "--add"), _opt(a, "--remove"), _opt(a, "--set")
        if st:
            new = set(parse_env_list(st, envs))
        else:
            new = (cur | set(parse_env_list(add, envs) if add else [])) - \
                set(parse_env_list(rm, envs) if rm else [])
        reg.set_patch_envs(v, new)
        info(f"v{v}: env {','.join(sorted(cur)) or '-'} → {','.join(sorted(new)) or '-'}")
        ev = evaluate(reg)
        for e in sorted(new - cur):
            print_patch_report(reg.scoped(e), ev[e], v)
        commit(reg, ev)
        return 0
    elif cmd == "block-below":
        n = int(a[0])
        env = _opt(a, "--env")
        need_env(env, envs)
        dry = _flag(a, "--dry-run")
        reg.set_policy(env=env, min_allowed_patch=n)
        (reg.policy.get("envs") or {}).get(env, {}).pop("force_redirect", None)
        reg.policy.pop("force_redirect", None)
        ev = evaluate(reg)
        print_plan(reg.scoped(env), ev[env])
        print()
        if dry:
            report_issues(ev)
            return 1 if ev.errors else 0
        commit(reg, ev)
        return 0
    elif cmd == "register-host":
        b = _opt(a, "--bundle")
        p = _opt(a, "--platform")
        name = _opt(a, "--version-name")
        vc = int(_opt(a, "--version-code"))
        mode = _opt(a, "--mode")
        if mode not in MODULE_MODES:
            info(f"mode {mode} dùng engine stock — không đăng ký registry")
            return 0
        reg.add_bundle(b)
        aid = reg.add_abi(compute_provides())
        new = reg.add_build(b, p, name, vc, mode, aid, git_rev(), _opt(a, "--unlock-date", None))
        info(f"{b}/{p}/{vc}: ABI {aid} ({'mới' if f'abis/{aid}.json' in reg.dirty else 'đã có'}), "
             f"{'thêm' if new else 'cập nhật'} build")
        # Chỉ GHI NHẬN bản build (hosts/ + abis/ + compat.json): chưa lên store
        # → không có trong manifest, không cần deploy (máy build không có VPN).
        # Không chặn vì lỗi validator của phần đã lên store — sửa ở máy deploy.
        ev = evaluate(reg, check_files=False)
        env = app_env(b)
        if env in ev.envs:
            c = ev[env].compat[aid]
            info(f"[{env}] bản build này chạy được tới: {'v' + str(c['max_patch']) if c['max_patch'] else 'chưa có patch nào'}"
                 + (f" — dừng vì v{c['first_break']['patch']}: {c['first_break']['reason']}" if c["first_break"] else ""))
            remind_patch(reg, ev, b, p, vc)
        reg.save()
        write_compat(reg, ev)
        ok(f"đã ghi registry/hosts/{b}.json — chưa vào manifest; lên store rồi thì menu [6] (máy có VPN) → deploy")
        return 0
    elif cmd == "register-patch":
        src = _opt(a, "--bytecode")
        mfu = int(_opt(a, "--min-force-update", "0"))
        penvs = parse_env_list(_opt(a, "--envs"), envs)
        if not src or not os.path.isfile(src):
            raise RegError(f"không thấy bytecode: {src}")
        h = sha256_file(src)
        name = f"{MODULE_NAME}_{h[:8]}.bytecode"
        os.makedirs(patches_dir(), exist_ok=True)
        dst = os.path.join(patches_dir(), name)
        if os.path.abspath(src) != os.path.abspath(dst):
            shutil.copyfile(src, dst)
        archive_patch_file(dst)
        v, new = reg.add_patch(name, h, os.path.getsize(dst), compute_requires(), mfu, penvs)
        backfill_gz(reg)
        info(f"patch v{v} {'MỚI' if new else '(nội dung y hệt bản đã có — giữ version)'}: {name} "
             f"→ env {','.join(reg.patches[v]['envs'])}")
        ev = evaluate(reg)
        for e in penvs:
            print_patch_report(reg.scoped(e), ev[e], v)
        commit(reg, ev)
        return 0
    else:
        raise RegError(f"lệnh lạ: {cmd} (xem --help)")

    commit(reg, evaluate(reg))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RegError as e:
        bad(str(e))
        sys.exit(1)
