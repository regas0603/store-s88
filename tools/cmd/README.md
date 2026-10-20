# tools/cmd/ — tool con

4 tool dùng hằng ngày (`setup` / `check` / `snapshot` / `dynpub`) xem
[../README.md](../README.md). Các tool dưới đây được 4 tool đó gọi; chỉ gọi tay
khi cần đi sâu hoặc gỡ lỗi.

```
tools/cmd/
├── dynmod.sh           # engine + build host + compile module (cấp thấp)
├── dynpush.sh          # bytecode.manifest + kiểm/tải như app thật
├── dyniface.sh         # dynamic_interface.yaml + phân tầng package host/module
├── abicheck.sh         # ABI host ↔ module (nhiều app dùng chung 1 bytecode)
│   (release registry: tools/registry/registry.py + app_identity.py — xem cuối file)
├── modprep.sh          # áp templates/module vào ../app_package + kiểm
├── build_main_app.sh   # xuất apps/<bundleId>/main_app (mặc định apps/_reference) ra package ngoài repo
├── run.sh              # chạy app lúc dev
├── doctor.sh           # sức khoẻ máy build
├── ensure_deps.sh      # tự cài SDK thiếu (bước 0 của setup)
├── flutter_version.sh  # đọc version Flutter từ configs/flutter.json
├── abicheck/           # abi.py
├── modprep/            # vm_web_scan.py
└── dyniface/           # pipeline .py cho dynamic_interface
```

Env chung (có mặc định, tương đối từ folder project): `DYNMOD_WORK`
(`../dart-sdk-build`), `DYNMOD_ENGINE_SRC` (`../engine`), `DYNMOD_APP` (`app/`),
`DYNMOD_IFACE` (`dist/dynamic_interface.yaml`), `DYNMOD_REV` (ghi đè
`configs/flutter.json`).

## dynmod.sh — engine + host + module

```bash
bash tools/cmd/dynmod.sh sync                          # clone flutter @version + gclient sync
bash tools/cmd/dynmod.sh engine <host|android|ios|all> [--jobs N] [--bg]
bash tools/cmd/dynmod.sh app <android|ios>             # build host bằng engine ddm
bash tools/cmd/dynmod.sh module [module.dart]          # compile .bytecode
bash tools/cmd/dynmod.sh pubget                        # pub get app/ bằng flutter của checkout
bash tools/cmd/dynmod.sh backup [dir]                  # chép engine gọn sang ../engine
bash tools/cmd/dynmod.sh status | env | watch <target>
```

`setup.sh` gọi `sync` / `engine` / `backup` / `pubget`.

## dynpush.sh — manifest + kiểm như app thật

```bash
bash tools/cmd/dynpush.sh patch [--version N] [--min-force-update N] [--bytecode <f>]
bash tools/cmd/dynpush.sh check --rs <rs_domain> --module-version 0   # host đang ở v0 sẽ nhận gì?
bash tools/cmd/dynpush.sh fetch --rs <rs_domain>                       # tải + verify y hệt app
bash tools/cmd/dynpush.sh verify --file <f.bytecode> [--hash <sha256>]
bash tools/cmd/dynpush.sh release ...                                  # dynpub.sh release gọi
```

`dynpub.sh` [2] Ra patch = `modprep apply` → host tham chiếu (apps/_reference/main_app +
`dyniface bootstrap`) → `dyniface compile` → `tools/registry/registry.py
register-patch`. `dynpush.sh patch` (ghi `bytecode.manifest` 1 patch) là luồng
CŨ — app mới đọc `publish/app/manifest.json` do registry sinh.

## dyniface.sh — interface + ranh giới package

```bash
bash tools/cmd/dyniface.sh bootstrap                  # build lại anchor + gen lại iface
bash tools/cmd/dyniface.sh compile [module.dart]      # dart2bytecode --validate → .bytecode
bash tools/cmd/dyniface.sh status                     # anchor, yaml, bytecode
bash tools/cmd/dyniface.sh packages --write           # phân tầng → configs/abi/host_packages.yaml
bash tools/cmd/dyniface.sh packages check
bash tools/cmd/dyniface.sh loop [module.dart]         # (cứu hộ) augment iface từ lỗi compile
```

`configs/abi/host_packages.yaml` — người duyệt chỉ chuyển package giữa
`t1_frozen_pure_dart` ↔ `module_allowed`; tầng khác do luật trong tool quyết định.

Script con trong `dyniface/`:

- `gen_dynamic_interface.py` — sinh baseline yaml từ anchor dill + platform dill
  (t1 tự được lộ cho module).
- `classify_packages.py` — phân tầng package (sdk / t0 / t1 / module / excluded).
- `gen_host_pin.py` — sinh `app/lib/shell/host_packages.g.dart` (import mọi
  package host để kernel host chứa trọn, module không mang bản riêng).
- `gen_host_iface.py` — sinh `dynamic_interface.host.yaml` = bản đầy đủ **−**
  entry `dynamically-callable` trỏ library không có trong host. Bản đầy đủ dùng
  cho `dart2bytecode --validate`; bản host dùng cho anchor + `flutter build`
  (giữ entry đó ở bản host → crash `The library 'X' has not been indexed`).
- `augment_from_validate.py`, `fix_disambiguation.py`, `repair_containers.py` —
  sửa yaml theo log validate (chỉ dùng qua `loop`).
- `check_iface_vs_anchor.py` — soi yaml ↔ anchor: entry nào sẽ crash host build.
- `dynmod_iface_deny.json` — deny list cho generator.

## abicheck.sh — ABI host ↔ module

```bash
bash tools/cmd/abicheck.sh host                    # app/ khớp configs/abi/module_abi.json?
bash tools/cmd/abicheck.sh main-app [<dir>]        # main_app dùng chung bytecode được?
bash tools/cmd/abicheck.sh app-package [--accept]  # version app_package vs host đóng băng
bash tools/cmd/abicheck.sh snapshot                # chụp ABI host hiện tại
```

`check.sh` gọi `host` / `main-app` / `app-package`; `snapshot.sh` gọi
`app-package --accept` + `snapshot`; `build_main_app.sh` gọi `main-app`.

## modprep.sh — chuẩn bị module

```bash
bash tools/cmd/modprep.sh apply [--no-check]   # áp templates/module/ vào ../app_package (+ kiểm)
bash tools/cmd/modprep.sh check
```

`app_package` là bản SINH RA (`convert_to_package.sh` của s88-flutter) — sửa
template ở `templates/module/`, không sửa bản áp.

## Khác

| Tool | Lệnh |
|---|---|
| `build_main_app.sh` | `bash tools/cmd/build_main_app.sh [--dry-run] [--out-dir D] [--no-verify] [check]` — xuất `main_app/` ra `../main_app_package` |
| `run.sh` | `bash tools/cmd/run.sh <ios\|ios-sim\|android\|android-emu\|devices> [--release]` (`APP_ENV=pre` …) |
| `doctor.sh` | `bash tools/cmd/doctor.sh [--full]` — exit 0 = máy sẵn sàng |
| `ensure_deps.sh` | `bash tools/cmd/ensure_deps.sh [--dry-run] [--no-install]` — Xcode cài tay |
| `flutter_version.sh` | `bash tools/cmd/flutter_version.sh [--commit \| --stamp <out_dir>]` |

## tools/registry/ — release registry

```bash
python3 tools/registry/registry.py plan | validate | regen | deploy | check-links
python3 tools/registry/registry.py --help          # mọi lệnh (dynpub.sh wizard gọi)
python3 tools/registry/test_registry.py            # test kịch bản host kẹt / force / retract
python3 tools/registry/app_identity.py --help      # áp apps/<bundleId>/app.yaml vào bản build
```

`registry.py` giữ `registry/` (ABI từng bản build, patch, policy), tính bản build
nào chạy được tới patch nào, sinh `publish/app/manifest.json` và chặn ghi khi
validator báo lỗi. `app_identity.py` áp bundle id / tên / ký / icon theo
`apps/<bundleId>/app.yaml` (Android qua env, iOS qua
`ios/Flutter/AppIdentity.xcconfig`, icon backup + khôi phục sau build).
