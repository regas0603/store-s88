#!/usr/bin/env python3
"""Test registry theo kịch bản trong docs/release_registry_design.md §1:
host1..7 build lại được, hostA kẹt; v8 đổi lottie; v14 cấm v7.

Chạy: python3 tools/registry/test_registry.py
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
os.environ["REGISTRY_OFFLINE"] = "1"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import registry as R  # noqa: E402

ENGINE = "4cf24164269a5ebf0c16a028a00727d0e77bbb05"
IFACE_BASE = ["callable|dart:core", "callable|package:dio/dio.dart", "callable|package:lottie/lottie.dart",
              "callable|package:flutter/material.dart", "extendable|package:dio/src/options.dart#_RequestConfig"]


def provides(lottie="3.6.1", extra_pkgs=None, iface=None):
    pk = {"dio": "5.11.1", "lottie": lottie, "content_kit": "path:aaaa"}
    pk.update(extra_pkgs or {})
    return {"engine_rev": ENGINE, "contract_version": 2, "packages": pk,
            "iface": sorted(iface or IFACE_BASE)}


def requires(lottie="3.6.1", extra_pkgs=None, iface=None):
    pk = {"dio": "5.11.1", "lottie": lottie, "content_kit": "path:aaaa"}
    pk.update(extra_pkgs or {})
    return {"engine_rev": ENGINE, "contract_version": 2, "packages": pk,
            "iface": sorted(iface or IFACE_BASE)}


ENVS = {"staging": "https://stg.example.com", "pre": "https://rs.example.com/pre",
        "prod": "https://rs.example.com"}


def setup_env_files(tmp):
    """deploy.json 3 env + thư mục config/archive/changed trong tmp → set vào R."""
    R.PUBLISH = os.path.join(tmp, "publish")
    R.RUNTIME_CFG_DIR = os.path.join(tmp, "configs", "apps")
    R.DEPLOY_FILE = os.path.join(tmp, "configs", "deploy.json")
    R.ARCHIVE = os.path.join(tmp, "archive")
    R.CHANGED_FILE = os.path.join(tmp, "changed")
    os.makedirs(R.RUNTIME_CFG_DIR)
    os.makedirs(os.path.join(R.PUBLISH, "patches"))
    with open(R.DEPLOY_FILE, "w") as f:
        json.dump({"targets": [{"name": e, "rs_domain": u + "/", "api_domain": f"https://api-{e}.example.com/?c=",
                                "ssh": {"host": "h", "user": "u", "path": f"/srv/{e}"}}
                               for e, u in ENVS.items()]}, f)
    R.CONFIGS_OUT = os.path.join(tmp, "configs_repo", "apps")


class Base(unittest.TestCase):
    ENV = "prod"

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="reg_test_")
        setup_env_files(self.tmp)
        self.pub = os.path.join(R.PUBLISH, "patches")
        self.reg = R.Registry.load(os.path.join(self.tmp, "registry"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def ev(self, env=None):
        return R.evaluate(self.reg)[env or self.ENV]

    def patch(self, req, tag, envs=None):
        data = f"bytecode-{tag}".encode()
        h = hashlib.sha256(data).hexdigest()
        name = f"app_content_{h[:8]}.bytecode"
        with open(os.path.join(self.pub, name), "wb") as f:
            f.write(data)
        v, _ = self.reg.add_patch(name, h, len(data), req, envs=envs or [self.ENV])
        return v

    def build(self, bundle, platform, vc, prov, store="live", env=None):
        if not os.path.isfile(R.app_cfg_path(bundle)) or env:
            R._bundle_cfg_set(bundle, env or self.ENV, R.load_envs())
        self.reg.add_bundle(bundle)
        aid = self.reg.add_abi(prov)
        self.reg.add_build(bundle, platform, f"1.0.{vc}", vc, "ddm", aid)
        self.reg.set_store(bundle, platform, vc, store)
        return aid

    def row(self, res, bundle, platform, vc):
        return res.rows[(bundle, platform, vc)]


class CompatTest(Base):
    def test_unused_package_does_not_block(self):
        prov = provides(extra_pkgs={"rive": "0.13.0"})
        ok, _ = R.compatible(prov, requires())
        self.assertTrue(ok)

    def test_version_change_blocks(self):
        ok, reasons = R.compatible(provides(), requires(lottie="3.7.0"))
        self.assertFalse(ok)
        self.assertIn("lottie: host 3.6.1 ≠ patch 3.7.0", reasons)

    def test_new_package_blocks(self):
        ok, reasons = R.compatible(provides(), requires(extra_pkgs={"rive": "0.13.0"}))
        self.assertFalse(ok)
        self.assertTrue(any("package mới: rive" in r for r in reasons))

    def test_iface_subset(self):
        ok, _ = R.compatible(provides(iface=IFACE_BASE + ["callable|package:dio/extra.dart"]), requires())
        self.assertTrue(ok)
        ok, reasons = R.compatible(provides(), requires(iface=IFACE_BASE + ["callable|package:dio/extra.dart"]))
        self.assertFalse(ok)
        self.assertTrue(any("interface" in r for r in reasons))

    def test_non_contiguous_max(self):
        aid = self.build("com.example.hostA", "android", 12, provides())
        self.patch(requires(), "v1")
        self.patch(requires(lottie="3.7.0"), "v2")
        self.patch(requires(), "v3")
        c = R.compute_compat(self.reg)
        self.assertEqual(c[aid]["max_patch"], 3)
        self.assertIsNone(c[aid]["first_break"])

    def test_same_hash_keeps_version(self):
        v1 = self.patch(requires(), "same")
        v2 = self.patch(requires(), "same")
        self.assertEqual(v1, v2)
        self.assertEqual(len(self.reg.patches), 1)


class ScenarioTest(Base):
    """host1 (build lại được) + hostA (kẹt) + hostD (app thay thế)."""

    def setUp(self):
        super().setUp()
        for t in range(1, 8):  # v1..v7 lottie 3.6.1
            self.patch(requires(), f"old{t}")
        self.build("com.example.host1", "android", 12, provides())
        self.build("com.example.hostA", "android", 12, provides())
        self.build("com.example.hostA", "ios", 9, provides())
        self.reg.set_bundle("com.example.hostA", ios_app_id=111)

    def test_before_v8_everyone_latest(self):
        res = self.ev()
        self.assertEqual(res.errors, [])
        for k, r in res.rows.items():
            self.assertEqual((r["target"], r["action"]), (7, "none"), k)

    def test_v8_hosts_stop_at_7_and_soft_rules(self):
        self.patch(requires(lottie="3.7.0"), "v8")
        # host1 bản mới đã build nhưng chưa live → host1 vc12 không bị mời sang app khác
        self.build("com.example.host1", "android", 13, provides(lottie="3.7.0"), store="submitted")
        self.reg.set_bundle("com.example.hostA", status="retired", redirect_bundle="com.example.hostD")
        self.build("com.example.hostD", "android", 20, provides(lottie="3.7.0"))
        self.build("com.example.hostD", "ios", 5, provides(lottie="3.7.0"))
        self.reg.set_bundle("com.example.hostD", ios_app_id=999)
        res = self.ev()
        self.assertEqual(res.errors, [])
        self.assertEqual(self.row(res, "com.example.host1", "android", 12)["action"], "none")
        self.assertEqual(self.row(res, "com.example.host1", "android", 13)["target"], 8)
        a = self.row(res, "com.example.hostA", "android", 12)
        self.assertEqual((a["target"], a["action"], a["url"]),
                         (7, "soft", "market://details?id=com.example.hostD"))
        i = self.row(res, "com.example.hostA", "ios", 9)
        self.assertEqual((i["action"], i["url"]), ("soft", "https://apps.apple.com/app/id999"))
        # host1 vc13 live → host1 vc12 được mời về store của chính nó
        self.reg.set_store("com.example.host1", "android", 13, "live")
        res = self.ev()
        h = self.row(res, "com.example.host1", "android", 12)
        self.assertEqual((h["action"], h["url"]), ("soft", "market://details?id=com.example.host1"))

    def _v14(self):
        for t in range(8, 15):
            self.patch(requires(lottie="3.7.0"), f"new{t}")
        self.build("com.example.host1", "android", 13, provides(lottie="3.7.0"))
        self.build("com.example.hostD", "android", 20, provides(lottie="3.7.0"))
        self.build("com.example.hostD", "ios", 5, provides(lottie="3.7.0"))
        self.reg.set_bundle("com.example.hostD", ios_app_id=999)

    def test_block_below_with_redirect_overrides_all(self):
        self._v14()
        self.reg.set_policy(min_allowed_patch=8,
                            force_redirect={"android": "com.example.hostD", "ios": "com.example.hostD"})
        res = self.ev()
        self.assertEqual(res.errors, [])
        for key in [("com.example.host1", "android", 12), ("com.example.hostA", "android", 12)]:
            r = res.rows[key]
            self.assertEqual((r["action"], r["url"]), ("force", "market://details?id=com.example.hostD"), key)
        r = self.row(res, "com.example.hostA", "ios", 9)
        self.assertEqual((r["action"], r["url"]), ("force", "https://apps.apple.com/app/id999"))
        self.assertEqual(self.row(res, "com.example.host1", "android", 13)["action"], "none")
        m = res.manifest
        self.assertEqual(m["latest"], 14)
        self.assertEqual(set(m["patches"]), {"7", "14"})
        self.assertEqual(m["hosts"]["com.example.host1"]["android"]["13"], {"patch": 14})

    def test_block_below_without_redirect_blocks_stuck_host(self):
        self._v14()
        self.reg.set_policy(min_allowed_patch=8, force_redirect={"android": None, "ios": None})
        res = self.ev()
        h = self.row(res, "com.example.host1", "android", 12)
        self.assertEqual((h["action"], h["url"]), ("force", "market://details?id=com.example.host1"))
        self.assertTrue(any("com.example.hostA/android/12" in e and "kẹt" in e for e in res.errors))

    def test_redirect_target_itself_forced_is_error(self):
        self._v14()
        # hostA làm app thay thế: build live của nó chỉ chạy tới v7 → bị force
        self.reg.set_policy(min_allowed_patch=8,
                            force_redirect={"android": "com.example.hostA", "ios": "com.example.hostD"})
        res = self.ev()
        self.assertTrue(any("cũng bị force" in e for e in res.errors))

    def test_removed_but_compatible_left_alone(self):
        self._v14()
        self.reg.set_store("com.example.host1", "android", 13, "removed")
        self.reg.set_bundle("com.example.host1", status="retired", redirect_bundle="com.example.hostD")
        res = self.ev()
        r = self.row(res, "com.example.host1", "android", 13)
        self.assertEqual((r["target"], r["action"]), (14, "none"))

    def test_force_vc(self):
        self._v14()
        fv = {"android": {"below": 13, "redirect": None}}
        self.reg.set_bundle("com.example.host1", force_vc=fv)
        res = self.ev()
        r = self.row(res, "com.example.host1", "android", 12)
        self.assertEqual((r["action"], r["url"]), ("force", "market://details?id=com.example.host1"))
        self.assertEqual(self.row(res, "com.example.host1", "android", 13)["action"], "none")

    def test_retract_lowers_target(self):
        self._v14()
        self.reg.retract(14)
        res = self.ev()
        self.assertEqual(self.row(res, "com.example.host1", "android", 13)["target"], 13)
        self.assertEqual(res.manifest["latest"], 13)

    def test_missing_file_is_error(self):
        os.remove(os.path.join(self.pub, self.reg.patches[7]["file"]))
        res = self.ev()
        self.assertTrue(any("thiếu" in e for e in res.errors))

    def test_duplicate_vc_different_abi_rejected(self):
        with self.assertRaises(R.RegError):
            self.build("com.example.host1", "android", 12, provides(lottie="9.9.9"))

    def test_commit_writes_and_reloads(self):
        changed = R.commit(self.reg, R.evaluate(self.reg))
        self.assertEqual(sorted(changed), ["prod"])  # env không có app → không có manifest
        again = R.Registry.load(self.reg.root)
        self.assertEqual(set(again.patches), set(range(1, 8)))
        self.assertTrue(os.path.isfile(R.manifest_path("prod", "com.example.host1")))
        # chạy lại không đổi gì → không env nào cần deploy
        self.assertEqual(R.commit(again, R.evaluate(again)), [])
        # chỉ giữ bytecode manifest trỏ tới
        self.assertEqual(sorted(f for f in os.listdir(self.pub) if f.endswith(".bytecode")),
                         [self.reg.patches[7]["file"]])


class StoreSplitTest(Base):
    """hosts/ = mọi bản build, store/ = chỉ bản đã lên store → chỉ store/ vào manifest."""

    def test_only_store_builds_reach_manifest(self):
        v = self.patch(requires(), "a")
        self.build("com.example.h", "android", 1, provides(), store="live")
        self.build("com.example.h", "android", 2, provides(), store="built")
        changed = R.commit(self.reg, R.evaluate(self.reg))
        self.assertEqual(changed, ["prod"])
        with open(R.manifest_path("prod", "com.example.h")) as f:
            self.assertEqual(json.load(f)["hosts"]["com.example.h"], {"android": {"1": {"patch": v}}})
        root = self.reg.root
        with open(os.path.join(root, "hosts", "com.example.h.json")) as f:
            hosts = json.load(f)["builds"]
        self.assertEqual([b["version_code"] for b in hosts], [1, 2])
        self.assertFalse(any("store" in b for b in hosts))
        with open(os.path.join(root, "store", "com.example.h.json")) as f:
            self.assertEqual([(b["version_code"], b["store"]) for b in json.load(f)["builds"]], [(1, "live")])
        # build mới (chưa lên store) → manifest không đổi → không cần deploy
        self.build("com.example.h", "android", 3, provides(), store="built")
        self.assertEqual(R.commit(self.reg, R.evaluate(self.reg)), [])
        # xác nhận lên store → vào manifest
        self.reg.set_store("com.example.h", "android", 3, "submitted")
        self.assertEqual(R.commit(self.reg, R.evaluate(self.reg)), ["prod"])
        self.assertIn(("com.example.h", "android", 3), self.ev().rows)
        # về built → bỏ khỏi store/; hết bản store → xoá file
        for vc in (1, 3):
            self.reg.set_store("com.example.h", "android", vc, "built")
        R.commit(self.reg, R.evaluate(self.reg))
        self.assertFalse(os.path.exists(os.path.join(root, "store", "com.example.h.json")))
        self.assertEqual(self.ev().rows, {})
        self.assertEqual(len(R.Registry.load(root).all_builds()), 3)

    def test_rejected_only_from_submitted_keeps_older(self):
        self.patch(requires(), "a")
        self.build("com.example.h", "ios", 1, provides(), store="live")
        self.build("com.example.h", "ios", 2, provides(), store="built")
        with self.assertRaises(R.RegError):  # built → rejected: không được
            self.reg.set_store("com.example.h", "ios", 2, "rejected")
        self.reg.set_store("com.example.h", "ios", 2, "submitted")
        self.assertIn(("com.example.h", "ios", 2), self.ev().rows)
        self.reg.set_store("com.example.h", "ios", 2, "rejected")
        self.assertEqual(self.reg.store_state("com.example.h", "ios", 2), "rejected")
        self.assertEqual(set(self.ev().rows), {("com.example.h", "ios", 1)})  # bản trước giữ nguyên
        with self.assertRaises(R.RegError):  # rejected → rejected
            self.reg.set_store("com.example.h", "ios", 2, "rejected")
        self.reg.save()
        again = R.Registry.load(self.reg.root)
        self.assertEqual(again.store_state("com.example.h", "ios", 2), "rejected")
        # nộp lại cùng bản → hết rejected, vào manifest lại
        again.set_store("com.example.h", "ios", 2, "submitted")
        self.assertNotIn("rejected", again.store["com.example.h"])
        self.assertEqual(again.store_state("com.example.h", "ios", 2), "submitted")

    def test_migrate_legacy_store_field(self):
        aid = self.reg.add_abi(provides())
        R.write_json(os.path.join(self.reg.root, "hosts", "com.example.old.json"), {
            "bundle_id": "com.example.old", "builds": [
                {"platform": "ios", "version_code": 1, "abi_id": aid, "store": "built"},
                {"platform": "ios", "version_code": 2, "abi_id": aid, "store": "live"}]})
        r = R.Registry.load(self.reg.root)
        self.assertEqual([bd["version_code"] for _, bd in r.builds()], [2])
        self.assertEqual(r.store_state("com.example.old", "ios", 1), "built")
        r.save()
        again = R.Registry.load(self.reg.root)
        self.assertEqual(again.dirty, set())
        self.assertEqual([(bd["version_code"], bd["store"]) for _, bd in again.builds()], [(2, "live")])


class EnvTest(Base):
    """staging: hostS · prod: hostP — patch chỉ tới env được chọn."""

    def setUp(self):
        super().setUp()
        self.build("com.example.hostS", "android", 1, provides(), env="staging")
        self.build("com.example.hostP", "android", 1, provides(), env="prod")

    def test_one_manifest_per_app(self):
        self.build("com.example.hostP", "android", 2, provides(), env="prod")
        self.build("com.example.hostP", "ios", 7, provides(), env="prod")
        self.build("com.example.hostQ", "android", 1, provides(lottie="3.7.0"), env="prod")
        v1 = self.patch(requires(), "a", envs=["prod"])
        v2 = self.patch(requires(lottie="3.7.0"), "b", envs=["prod"])
        R.commit(self.reg, R.evaluate(self.reg))
        files = sorted(R.local_manifests("prod"))
        self.assertEqual(files, ["com.example.hostP", "com.example.hostQ"])
        with open(R.manifest_path("prod", "com.example.hostP")) as f:
            p = json.load(f)
        # 1 app nhiều version store → chung 1 file, chỉ dòng + patch của app đó
        self.assertEqual(p["bundle"], "com.example.hostP")
        self.assertEqual(set(p["hosts"]), {"com.example.hostP"})
        self.assertEqual(set(p["hosts"]["com.example.hostP"]["android"]), {"1", "2"})
        self.assertEqual(set(p["hosts"]["com.example.hostP"]["ios"]), {"7"})
        self.assertEqual(set(p["patches"]), {str(v1)})
        self.assertEqual(p["latest"], v2)
        with open(R.manifest_path("prod", "com.example.hostQ")) as f:
            self.assertEqual(set(json.load(f)["patches"]), {str(v2)})
        # app chuyển env → file ở env cũ bị bỏ
        R._bundle_cfg_set("com.example.hostQ", "pre", R.load_envs())
        R.commit(self.reg, R.evaluate(self.reg))
        self.assertEqual(sorted(R.local_manifests("prod")), ["com.example.hostP"])
        self.assertEqual(sorted(R.local_manifests("pre")), ["com.example.hostQ"])

    def test_patch_only_reaches_chosen_env(self):
        v = self.patch(requires(), "a", envs=["staging"])
        ev = R.evaluate(self.reg)
        self.assertEqual(ev["staging"].manifest["latest"], v)
        self.assertEqual(ev["staging"].manifest["hosts"]["com.example.hostS"]["android"]["1"], {"patch": v})
        self.assertEqual(ev["prod"].manifest["latest"], 0)
        self.assertEqual(ev["prod"].manifest["hosts"], {"com.example.hostP": {"android": {"1": {"patch": 0}}}})
        self.assertNotIn("com.example.hostP", ev["staging"].manifest["hosts"])
        self.assertEqual(ev["pre"].manifest["hosts"], {})

    def test_promote_and_same_hash_adds_env(self):
        v = self.patch(requires(), "a", envs=["staging"])
        self.assertEqual(self.patch(requires(), "a", envs=["prod"]), v)  # compile lại y hệt → thêm env
        self.assertEqual(self.reg.patches[v]["envs"], ["prod", "staging"])
        self.assertEqual(R.evaluate(self.reg)["prod"].manifest["latest"], v)

    def test_same_hash_new_requires_is_new_version(self):
        # host đổi version package nhưng bytecode y hệt → vẫn phải ra version mới
        old = self.build("com.example.hostP", "android", 1, provides())
        new = self.build("com.example.hostP", "android", 2, provides(lottie="3.7.0"))
        v1 = self.patch(requires(), "a", envs=["prod"])
        v2 = self.patch(requires(lottie="3.7.0"), "a", envs=["prod"])
        self.assertEqual(v2, v1 + 1)
        self.assertEqual(self.reg.patches[v2]["file"], self.reg.patches[v1]["file"])
        rows = self.ev().manifest["hosts"]["com.example.hostP"]["android"]
        self.assertEqual(rows["1"]["patch"], v1)
        self.assertEqual(rows["2"]["patch"], v2)
        self.assertNotEqual(old, new)

    def test_gz_backfill_in_manifest(self):
        import gzip as _gz
        self.build("com.example.hostP", "android", 1, provides())
        v = self.patch(requires(), "a", envs=["prod"])
        self.assertNotIn("gz_file", self.ev().manifest["patches"][str(v)])  # chưa có bản nén
        R.backfill_gz(self.reg)
        p = self.ev().manifest["patches"][str(v)]
        self.assertEqual(p["gz_file"], p["file"] + ".gz")
        with open(os.path.join(self.pub, p["gz_file"]), "rb") as f:
            raw = _gz.decompress(f.read())
        self.assertEqual(hashlib.sha256(raw).hexdigest(), p["hash"])
        self.assertEqual(p["gz_size"], os.path.getsize(os.path.join(self.pub, p["gz_file"])))

    def test_policy_per_env(self):
        self.patch(requires(), "a", envs=["staging", "prod"])
        self.patch(requires(), "b", envs=["staging"])
        self.reg.set_policy(env="staging", min_allowed_patch=2)
        ev = R.evaluate(self.reg)
        self.assertEqual(ev["staging"].manifest["min_allowed_patch"], 2)
        self.assertEqual(ev["prod"].manifest["min_allowed_patch"], 0)
        self.assertEqual(ev["prod"].rows[("com.example.hostP", "android", 1)]["action"], "none")

    def test_retract_hits_every_env(self):
        v = self.patch(requires(), "a", envs=["staging", "prod"])
        self.reg.retract(v)
        ev = R.evaluate(self.reg)
        self.assertEqual((ev["staging"].manifest["latest"], ev["prod"].manifest["latest"]), (0, 0))

    def test_legacy_patch_without_envs_is_everywhere(self):
        v = self.patch(requires(), "a")
        del self.reg.patches[v]["envs"]
        ev = R.evaluate(self.reg)
        self.assertEqual((ev["staging"].manifest["latest"], ev["pre"].manifest["latest"]), (v, v))

    def test_unassigned_app_warns_and_is_left_out(self):
        self.reg.add_bundle("com.example.noenv")
        ev = R.evaluate(self.reg)
        self.assertTrue(any("com.example.noenv: chưa gán env" in w for w in ev.warnings))
        self.assertFalse(any("com.example.noenv" in r.manifest["hosts"] for r in ev.envs.values()))

    def test_domain_mismatch_warns(self):
        with open(R.app_cfg_path("com.example.hostS"), "w") as f:
            json.dump({"env": "staging", "rs_domain": "https://old.example.com"}, f)
        self.assertTrue(any("sync-configs" in w for w in R.evaluate(self.reg).warnings))

    def test_redirect_must_be_same_env(self):
        self.patch(requires(lottie="3.7.0"), "a", envs=["staging", "prod"])  # hostS không chạy được
        self.reg.set_policy(env="staging", min_allowed_patch=1,
                            force_redirect={"android": "com.example.hostP", "ios": None})
        self.assertTrue(any("không cùng env" in e for e in R.evaluate(self.reg).errors))


class CliTest(unittest.TestCase):
    """Lệnh ghi qua subprocess (env var trỏ hết vào tmp — không đụng repo)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="reg_cli_")
        setup_env_files(self.tmp)
        self.env = dict(os.environ, REGISTRY_DIR=os.path.join(self.tmp, "registry"), REGISTRY_PUBLISH=R.PUBLISH,
                        REGISTRY_RUNTIME_CFG_DIR=R.RUNTIME_CFG_DIR, REGISTRY_DEPLOY_FILE=R.DEPLOY_FILE,
                        REGISTRY_ARCHIVE=R.ARCHIVE, REGISTRY_CHANGED_FILE=R.CHANGED_FILE,
                        REGISTRY_APPS_DIR=os.path.join(self.tmp, "apps"), REGISTRY_OFFLINE="1",
                        REGISTRY_CONFIGS_OUT=R.CONFIGS_OUT)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def reg(self, *args):
        r = subprocess.run([sys.executable, "-B", R.__file__, *args], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def cfg(self, b):
        with open(os.path.join(R.RUNTIME_CFG_DIR, f"{b}.json")) as f:
            return json.load(f)

    def test_reserve_version_always_increases(self):
        self.reg("bundle-add", "com.example.v", "--env", "staging")
        self.assertEqual(self.reg("reserve-version", "com.example.v").strip(), "1.0.1+1")
        # build trước không đăng ký (debug / lỗi) → lần sau vẫn lên số mới
        self.assertEqual(self.reg("reserve-version", "com.example.v").strip(), "1.0.2+2")
        self.assertEqual(self.reg("next-version", "com.example.v").strip(), "1.0.3+3")  # chỉ xem
        self.assertEqual(self.reg("reserve-version", "com.example.v", "--version", "2.1.0+10").strip(), "2.1.0+10")
        self.assertEqual(self.reg("reserve-version", "com.example.v").strip(), "1.0.11+11")
        with open(os.path.join(self.env["REGISTRY_DIR"], "bundles.json")) as f:
            self.assertEqual(json.load(f)["com.example.v"]["last_version_code"], 11)

    def test_env_lifecycle_and_copy_configs(self):
        os.makedirs(R.CONFIGS_OUT)
        with open(os.path.join(R.CONFIGS_OUT, "com.example.b.json"), "w") as f:
            json.dump({"api_domain": "https://api-from-github/?"}, f)
        self.reg("bundle-add", "com.example.a", "--env", "staging")
        self.reg("bundle-add", "com.example.b", "--env", "staging")
        self.assertEqual(self.cfg("com.example.a")["rs_domain"], ENVS["staging"] + "/")  # nguyên văn deploy.json
        self.assertEqual(self.cfg("com.example.a")["api_domain"], "https://api-staging.example.com/?c=")  # mặc định env
        self.assertEqual(self.cfg("com.example.b")["api_domain"], "https://api-from-github/?")  # app đã có trên GitHub
        os.remove(os.path.join(R.CONFIGS_OUT, "com.example.b.json"))
        self.assertIn("staging", self.reg("changed-envs").split())  # lần đầu: mọi manifest mới
        self.assertIn("staging", self.reg("changed-envs", "--clear").split())  # chưa deploy → vẫn còn
        self.assertEqual(self.reg("changed-envs").split(), [])  # đã xoá dấu
        self.reg("regen")
        self.assertEqual(self.reg("changed-envs").split(), [])  # không đổi gì → không cần deploy
        self.assertIn("com.example.a\tactive\tstaging", self.reg("list-bundles"))

        self.reg("set-env", "com.example.b", "prod")
        self.assertEqual(self.cfg("com.example.b")["rs_domain"], ENVS["prod"] + "/")
        self.assertEqual(sorted(self.reg("changed-envs", "--clear").split()), ["prod", "staging"])

        self.reg("set-rs-domain", "staging", "https://new-stg.example.com/", "--ssh-path", "/srv/new")
        self.assertEqual(self.cfg("com.example.a")["rs_domain"], "https://new-stg.example.com/")
        self.assertEqual(self.cfg("com.example.b")["rs_domain"], ENVS["prod"] + "/")  # env khác không đụng
        with open(R.DEPLOY_FILE) as f:
            t = {x["name"]: x for x in json.load(f)["targets"]}
        self.assertEqual((t["staging"]["rs_domain"], t["staging"]["ssh"]["path"]),
                         ("https://new-stg.example.com/", "/srv/new"))
        self.assertEqual(t["prod"]["rs_domain"], ENVS["prod"] + "/")

        # chép config sang ../configs/apps: giữ key chỉ có bên kia (force_update),
        # không ghi rỗng, KHÔNG đụng git
        dst = os.path.join(R.CONFIGS_OUT, "com.example.a.json")
        with open(dst, "w") as f:
            json.dump({"api_domain": "x", "rs_domain": "https://old", "force_update": {"min_version_code": 3}}, f)
        with open(R.app_cfg_path("com.example.a")) as f:
            c = json.load(f)
        c["api_domain"] = ""  # local trống → KHÔNG xoá giá trị bên kia
        with open(R.app_cfg_path("com.example.a"), "w") as f:
            json.dump(c, f)
        R.copy_configs(["com.example.a"])
        with open(dst) as f:
            got = json.load(f)
        self.assertEqual(got["rs_domain"], "https://new-stg.example.com/")
        self.assertEqual(got["force_update"], {"min_version_code": 3})
        self.assertEqual(got["api_domain"], "x")
        self.assertEqual(got["env"], "staging")
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(R.CONFIGS_OUT), ".git")))


class IfaceParseTest(unittest.TestCase):
    def test_parse(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "i.yaml")
        with open(p, "w") as f:
            f.write("# c\ncallable:\n  - {library: 'dart:core'}\n  - {library: 'package:dio/dio.dart', class: 'Dio'}\n"
                    "\nextendable:\n  - {library: 'package:x/y.dart', class: 'A', member: 'b'}\n")
        s = R.parse_iface(p)
        self.assertEqual(s, {"callable|dart:core", "callable|package:dio/dio.dart#Dio",
                             "extendable|package:x/y.dart#A.b"})
        self.assertEqual(R.iface_package("callable|package:dio/dio.dart#Dio"), "dio")
        self.assertEqual(R.iface_package("callable|dart:core"), "dart")
        shutil.rmtree(d)


if __name__ == "__main__":
    unittest.main(verbosity=1)
