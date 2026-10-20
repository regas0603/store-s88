#!/usr/bin/env python3
"""Deploy manifest + bytecode lên rs_domain qua SSH/SFTP (paramiko).

Cùng cách làm với s88-flutter/tools/upload_resources.py: key SSH lấy từ .env
(xem .env.example), env (staging / pre / prod) lấy từ configs/deploy.json:

  {"targets": [{"name": "prod", "rs_domain": "https://rs.example.site",
                "ssh": {"host": "1.2.3.4", "port": 22, "user": "deploy",
                        "path": "/var/www/rs"}}]}

File lên server: <path>/app/<file> (= <rs_domain>/app/<file>) — bytecode +
manifest riêng từng app (app/manifest/<bundle>.json); config app KHÔNG lên server.
Thứ tự mỗi env: bytecode (đã có cùng kích thước thì bỏ qua — tên file gắn hash
nội dung) → manifest, ghi file tạm rồi rename → máy không bao giờ
đọc phải manifest ghi dở hay manifest trỏ tới bytecode chưa lên. Đọc lại hash
qua SFTP xong mới chép config sang ../configs/apps (registry.copy_configs —
user tự commit + push repo configs).

Chạy:
  python3 tools/registry/deploy_sftp.py [--env E]… [--bundle B] [--dry-run]
                                        [--no-configs] [--key-file F] [--key-pass P]
  (= bash tools/dynpub.sh → [2], = bash tools/dynpub.sh reg deploy …)
"""
import argparse
import hashlib
import os
import posixpath
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def load_dotenv(path=os.path.join(ROOT, ".env")):
    """KEY=VALUE từ .env; KHÔNG ghi đè biến đã có trong os.environ."""
    if not os.path.isfile(path):
        return None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = (s.strip() for s in line.split("=", 1))
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        else:
            val = val.split(" #", 1)[0].strip()
        if key and key not in os.environ:
            os.environ[key] = val
    return path


def _ensure_paramiko():
    """Thiếu paramiko → pip install rồi import lại (giống upload_resources.py)."""
    try:
        import paramiko  # noqa: F401
    except ImportError:
        print("  [i]    thiếu thư viện paramiko, đang tự cài…")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko"])
        import importlib
        import site
        site.addsitedir(site.getusersitepackages())
        importlib.invalidate_caches()
    import paramiko
    return paramiko


class DeployError(Exception):
    pass


def resolve_ssh_key(ssh, cli_file=None, cli_pass=None):
    """CLI > ENV (.env) > ssh.key_file của target. Thiếu key → lỗi rõ."""
    key = (cli_file or "").strip() or os.getenv("SSH_KEY_FILE", "").strip() \
        or str(ssh.get("key_file", "")).strip()
    if cli_pass is not None and str(cli_pass).strip():
        pwd = str(cli_pass)
    else:
        pwd = os.getenv("SSH_KEY_PASS", "")
    if not key or key.startswith("<"):
        raise DeployError("thiếu SSH key — `cp .env.example .env` rồi sửa SSH_KEY_FILE "
                          "(hoặc truyền --key-file)")
    key = os.path.abspath(os.path.expanduser(key))
    if not os.path.isfile(key):
        raise DeployError(f"không tìm thấy SSH key: {key}")
    if pwd.startswith("<"):  # còn nguyên giá trị mẫu của .env.example
        pwd = ""
    return key, pwd


class SftpTarget:
    """1 kết nối SFTP tới thư mục <ssh.path>/app của 1 target."""

    def __init__(self, target, key_file=None, key_pass=None, dry_run=False):
        ssh = target.get("ssh") or {}
        miss = [k for k in ("host", "user", "path") if not ssh.get(k)]
        if miss:
            raise DeployError(f"target {target.get('name', '?')}: ssh thiếu {', '.join(miss)}")
        self.host, self.user = ssh["host"], ssh["user"]
        self.port = int(ssh.get("port") or 22)
        self.dir = posixpath.join(ssh["path"].rstrip("/"), "app")
        self.dry_run = dry_run
        self.key_file, self.key_pass = resolve_ssh_key(ssh, key_file, key_pass)
        self.client = self.sftp = None

    def __enter__(self):
        paramiko = _ensure_paramiko()
        print(f"  [i]    SSH {self.user}@{self.host}:{self.port}  key {self.key_file}")
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            self.client.connect(hostname=self.host, port=self.port, username=self.user,
                                key_filename=self.key_file, passphrase=self.key_pass or None,
                                timeout=20, allow_agent=False, look_for_keys=False)  # chỉ đúng key .env — không thử key lạ (tránh bị server ban vì đăng nhập sai)
        except Exception as e:
            raise DeployError(f"không kết nối SSH được {self.user}@{self.host}:{self.port}: {e}")
        self.sftp = self.client.open_sftp()
        if not self.dry_run:
            try:
                self._mkdirs(self.dir)
            except IOError as e:
                raise DeployError(f"không tạo được {self.dir} trên server (quyền ghi?): {e}")
        return self

    def __exit__(self, *exc):
        if self.sftp:
            self.sftp.close()
        if self.client:
            self.client.close()

    def _mkdirs(self, d):
        cur = "/" if d.startswith("/") else ""
        for part in d.strip("/").split("/"):
            cur = posixpath.join(cur, part)
            try:
                self.sftp.stat(cur)
            except IOError:
                self.sftp.mkdir(cur)

    def remote(self, name):
        return posixpath.join(self.dir, name)

    def size(self, name):
        try:
            return self.sftp.stat(self.remote(name)).st_size
        except IOError:
            return None

    def sha256(self, name):
        h = hashlib.sha256()
        with self.sftp.open(self.remote(name), "rb") as f:
            f.prefetch()
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()

    def put(self, path, name):
        """Ghi <name>.tmp rồi rename đè — người đọc không thấy file ghi dở."""
        if self.dry_run:
            print(f"  [dry-run] upload {name} → {self.remote(name)}")
            return
        tmp = self.remote(name + ".uploading")
        parent = posixpath.dirname(self.remote(name))
        if parent != self.dir:  # vd configs/<bundle>.json → tạo <dir>/configs nếu chưa có
            self._mkdirs(parent)
        t0 = time.time()
        try:
            self.sftp.put(path, tmp)
        except IOError as e:
            raise DeployError(f"upload {name} → {tmp} thất bại: {e}")
        try:
            self.sftp.posix_rename(tmp, self.remote(name))
        except IOError:  # server không có posix-rename@openssh.com
            try:
                self.sftp.remove(self.remote(name))
            except IOError:
                pass
            self.sftp.rename(tmp, self.remote(name))
        print(f"  📤 {name}  ({os.path.getsize(path) / 1e6:.2f} MB, {time.time() - t0:.1f}s)")


def main(argv):
    ap = argparse.ArgumentParser(description="Deploy bytecode + manifest lên rs_domain của từng env, rồi chép config app sang ../configs/apps")
    ap.add_argument("--env", "--target", dest="env", action="append",
                    help="chỉ deploy env này (lặp được); mặc định: mọi env")
    ap.add_argument("--bundle", help="chỉ app này (bytecode + manifest env của nó, chép config của app)")
    ap.add_argument("--dry-run", action="store_true", help="chỉ in việc sẽ làm, không ghi lên server / ../configs")
    ap.add_argument("--no-configs", action="store_true", help="không chép config sang ../configs/apps")
    ap.add_argument("--key-file", help="private key SSH (đè SSH_KEY_FILE)")
    ap.add_argument("--key-pass", help="passphrase key SSH (đè SSH_KEY_PASS)")
    a = ap.parse_args(argv)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import registry
    try:
        registry.deploy(envs=a.env, bundle=a.bundle, dry_run=a.dry_run, key_file=a.key_file,
                        key_pass=a.key_pass, copy_cfg=not a.no_configs)
    except (registry.RegError, registry.deploy_sftp.DeployError, DeployError) as e:
        print(f"LỖI: {e}", file=sys.stderr)
        return 1
    return 0


load_dotenv()

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
