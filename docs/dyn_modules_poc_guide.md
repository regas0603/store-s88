# PoC Guide: Dynamic Modules — pipeline chạy thật + ánh xạ sang Shorebird

> ✅ **ĐÃ CHẠY THÀNH CÔNG** trên máy này (macOS ARM64), 2026-09-30.
> SDK commit `53b0a5225e53f0c390d647c8174d5da16481994e` (Dart 3.14.0-edge).
> Build `--dart-dynamic-modules` mất **285s**. Artifact ở `xcodebuild/ReleaseARM64`
> (macOS KHÔNG tạo symlink `out/`). Script chạy thật: `../dart-sdk-build/run_poc_arm.sh`.
>
> **Transcript kết quả:**
> ```
> > + 1 2 3        → Result: 6          (built-in AOT native)
> > - 10 3         → Unknown operation  (chưa nạp module)
> > load basic     → Registered: - * /  (bytecode qua interpreter)
> > - 10 3         → Result: 7          ✅ interpreted, host KHÔNG rebuild
> > ^ 2 10         → Result: 1024       (module exponent)
> > sin 1.5707963  → Result: 0.9999…    (module trigonometry)
> ```
>
> ⚠️ **GOTCHA macOS (phát hiện thực nghiệm, đúng chủ đề §2 tài liệu gốc):**
> `dartaotruntime` build adhoc + hardened runtime → khi mmap code của AOT ELF snapshot
> thành executable, macOS **SIGKILL** ("Killed: 9") vì unsigned executable memory.
> **Fix:** ký lại runtime với entitlement JIT:
> ```bash
> codesign --force --sign - --entitlements ent.plist --options runtime \
>   xcodebuild/ReleaseARM64/dartaotruntime_product
> # ent.plist bật: com.apple.security.cs.allow-jit,
> #   allow-unsigned-executable-memory, disable-library-validation
> ```
> Trên macOS ta tự ký được → chạy. Trên **iOS thật KHÔNG ký kiểu này được** — đây
> chính là rào code-signing mà đồ án cần phân tích cho phần iOS.
>
> ⚠️ Chạy REPL không tương tác phải **nạp stdin có nhịp** (sleep giữa các lệnh), nếu
> nhồi cùng lúc sẽ lỗi `StreamSink is bound to a stream` (artifact IO, không phải lỗi
> dyn_modules).

> **Nguồn:** trích trực tiếp từ `dart-lang/sdk` `pkg/dynamic_modules/example/` (đã đọc
> file thật: `run.sh`, `host/main.dart`, `common/common.dart`, `modules/basic.dart`,
> `dynamic_interface.yaml`, `lib/dynamic_modules.dart`).
> **Đã verify:** nội dung lệnh + API (đọc source). **Chưa chạy:** bản thân build
> (`tools/build.py` cần full checkout depot_tools ~nhiều GB + thời gian dài — xem §0).

---

## 0. Chuẩn bị checkout đầy đủ (bắt buộc để build được)

Sparse clone (thứ tôi đã làm để đọc source) **không build được** — `tools/build.py`
cần toàn bộ deps qua depot_tools:

```bash
# depot_tools
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"

# full checkout Dart SDK (nặng, lâu)
mkdir dart-sdk && cd dart-sdk
fetch dart
cd sdk
```

macOS ARM (máy bạn) build ra `out/ReleaseARM64` thay cho `out/ReleaseX64` trong
`run.sh` — sửa biến `SDK_OUT` cho khớp. (Hoặc chạy PoC trên Linux x64 giống CI bot
`vm-aot-dyn-linux-product-x64` cho khớp tài liệu.)

---

## 1. Build SDK có dynamic modules **[verified từ run.sh]**

Khác biệt duy nhất so với build Dart thường là cờ `--dart-dynamic-modules`:

```bash
./tools/build.py -m release --dart-dynamic-modules \
  runtime runtime_precompiled utils/gen_kernel
```

Artifact sinh ra trong `out/Release<ARCH>/`:

| Biến | File | Vai trò |
|---|---|---|
| `GEN_KERNEL` | `gen/gen_kernel_aot.dart.snapshot` | compile Dart → kernel (.dill) |
| `GEN_SNAPSHOT` | `gen_snapshot_product` | kernel → AOT snapshot ELF |
| `DART2BYTECODE` | `gen/dart2bytecode.dart.snapshot` | **compile module → bytecode** |
| `AOT_RUNTIME` | `dartaotruntime_product` | runtime AOT **+ interpreter** |
| `VM_PLATFORM` | `vm_platform.dill` | platform dill |

> `dartaotruntime` build với cờ này = đúng thứ Shorebird giữ private: AOT runtime có
> nhúng interpreter KBC.

---

## 2. Pipeline compile (4 artifact) **[verified]**

Điểm quan trọng: **host phải compile 2 lần** (no-aot + aot). Bản `no-aot` là "mỏ neo"
(anchor) để sau này compile module bám vào — chính là vai trò của "release snapshot làm
diff-base" trong Shorebird.

```bash
# (a) HOST kernel KHÔNG tối ưu  → làm anchor cho module
$AOT_RUNTIME $GEN_KERNEL --target vm --packages .dart_tool/package_config.json \
  -Ddart.vm.product=true -Ddynamic.modules.test.mode=aot \
  --no-aot --no-embed-sources --platform $VM_PLATFORM \
  --output $BUILD_DIR/main_no_aot.dill \
  --dynamic-interface $INTERFACE_YAML \
  $HOST_DIR/main.dart

# (b) HOST kernel AOT tối ưu
$AOT_RUNTIME $GEN_KERNEL ... --aot ... \
  --output $BUILD_DIR/main_aot.dill --dynamic-interface $INTERFACE_YAML $HOST_DIR/main.dart

# (c) HOST AOT snapshot (ELF) — app chạy thật
$GEN_SNAPSHOT --snapshot-kind=app-aot-elf \
  --elf=$BUILD_DIR/main.snapshot $BUILD_DIR/main_aot.dill

# (d) MODULE → bytecode (lặp mỗi module)
$AOT_RUNTIME $DART2BYTECODE --target vm --platform $VM_PLATFORM \
  --packages .dart_tool/package_config.json \
  -Ddart.vm.product=true -Ddynamic.modules.test.mode=aot \
  --import-dill $BUILD_DIR/main_no_aot.dill \   # ← bám vào anchor host
  --validate $INTERFACE_YAML \                  # ← ép module tuân thủ interface
  --bytecode-options=source-positions \
  --output $APP_DATA_DIR/basic.bytecode \
  --prefix-library-uris import/prefix \
  $MODULES_DIR/basic.dart
```

`--dynamic-interface` (host) và `--validate` (module) đảm bảo module chỉ chạm API đã
khai báo → lỗi **compile-time** nếu vi phạm, không phải runtime.

---

## 3. Chạy + nạp module runtime **[verified]**

```bash
$AOT_RUNTIME $BUILD_DIR/main.snapshot "$APP_DATA_DIR"
# REPL:
#   > + 1 2 3        → 6   (built-in, đã AOT native)
#   > - 10 3         → Error: Unknown operation "-"
#   > load basic     → nạp basic.bytecode, chạy interpreter, đăng ký -, *, /
#   > - 10 3         → 7   (chạy INTERPRETED, host không rebuild)
```

Bản chất "load" (từ `host/main.dart`):

```dart
final bytes = await file.readAsBytes();
final entrypointResult = await loadModuleFromBytes(Uint8List.fromList(bytes));
if (entrypointResult is void Function(Registry)) entrypointResult(registry);
```

API nạp (`lib/dynamic_modules.dart`) → `dart:_internal`:
`loadModuleFromBytes(bytes)` / `loadModuleFromUri(uri)` → `internal.loadDynamicModule(...)`.
Entry-point module (`modules/basic.dart`):

```dart
@pragma('dyn-module:entry-point')
Object? dynamicModuleEntrypoint() =>
    (Registry registry) { registry.addOperation(SubtractionOperation()); ... };
```

---

## 4. Ánh xạ 1:1 sang cơ chế Shorebird — (bảng phân tích cho thesis)

| Bước Shorebird (private) | Tương đương dyn_modules (public) |
|---|---|
| Release AOT snapshot làm diff-base | `main_no_aot.dill` (anchor) + `main.snapshot` |
| Compile hàm đã đổi → format portable | `dart2bytecode` → `.bytecode` |
| Interpreter iOS chạy patch (private) | `dartaotruntime` + `interpreter.cc` (public) |
| `base_url` tải patch từ server | `File.fromUri(...)` / `loadModuleFromUri` (thay bằng HTTP) |
| Không có bề mặt khai báo công khai | `dynamic_interface.yaml` (capability tường minh) |
| Verify: serializer version (fragile) | Provenance metadata (đang làm) + interface validate |
| Patch **đè** hàm cũ | Module **thêm** (additive-only) ← khác biệt lõi |

→ Để biến ví dụ calculator thành "code-push self-host" thật: thay bước copy file
`.bytecode` vào `APP_DATA_DIR` bằng **tải qua HTTPS từ server của bạn** (dùng
`loadModuleFromUri` hoặc tải bytes rồi `loadModuleFromBytes`). Đây chính là chỗ
server self-host trong repo này ghép vào.

---

## 4b. PoC code-push QUA MẠNG ✅ (đã chạy)

Script `../dart-sdk-build/run_poc_net.sh` + host bản mạng
`pkg/dynamic_modules/example/host_net/main.dart`: host tải `.bytecode` qua **HTTP**
rồi `loadModuleFromBytes`, thay vì đọc file cục bộ.

**Transcript (đã chạy):**
```
> load basic     → Fetching http://127.0.0.1:8799/basic.bytecode
                   Downloaded 2200 bytes; loading via interpreter...
> - 10 3         → Result: 7      ✅ code tải từ MẠNG, host không rebuild
> load exponent  → Downloaded 3151 bytes → ^ 2 8 = 256  ✅
```

Cơ chế nối: host đọc `MODULE_BASE_URL`, `GET $BASE/<name>.bytecode`. Trong PoC dùng
`python3 -m http.server` giả lập. **Điểm nối server self-host thật** (`server/` trong
repo): endpoint `GET /artifacts/patch/:artifactId/:filename` đã stream đúng
`application/octet-stream` — chỉ cần:
1. `dart2bytecode` ra `<name>.bytecode`.
2. Copy vào `server/data/artifacts/patch/<id>/` + thêm record `patchArtifacts`
   `{id, filename, uploaded:true, storedPath}` vào `db.json` (hoặc qua route upload
   `POST /uploads/patch/:artifactId`).
3. Host trỏ `MODULE_BASE_URL` = `<server>/artifacts/patch/<id>` (hoặc lấy `download_url`
   từ `POST /api/v1/patches/check`).

> ⚠️ KHÔNG seed vào `db.json` production của bạn (app `com.gamevee.th1`) — tạo app/db
> riêng cho thí nghiệm (`SELFHOST_DATA_DIR=/tmp/poc-db node src/index.js`).

## 5. Khoảng cách tới Flutter thật (hướng mở rộng)

Ví dụ trên là **Dart CLI thuần** (`dartaotruntime`). Để lên Flutter cần:
1. Flutter engine build với runtime dyn_modules (tương tự cờ `SHOREBIRD_USE_INTERPRETER`
   mà tài liệu cũ nhắc) — **phần khó, novel**.
2. Bootstrap gọi `loadModuleFromUri` sau khi engine chạy.
3. iOS: interpreter không exec code tải về (không cần JIT entitlement), nhưng còn
   ràng buộc **chưa hỗ trợ FFI** từ module.

---

## 6. Cảnh báo trung thực từ chính chủ (đưa vào thesis)

- Ví dụ **chưa có provenance validation** (`example/README.md` nói rõ) — API
  `loadModuleFromBytes` "about to be removed and replaced" bằng API yêu cầu provenance.
- `dart2bytecode` + `dynamic_modules`: **experimental, không published, có thể bị xoá
  bất kỳ lúc nào** — cần pin đúng commit SDK khi làm đồ án để tái lập được.
- Không sandbox: module chạy chung heap host (xem §5 `dyn_modules_research.md`).

---

## 7. Việc cần làm tiếp (checklist PoC)

- [x] Full checkout qua depot_tools (`fetch dart`), pin commit `53b0a522` → ghi vào thesis.
- [x] Build cờ `--dart-dynamic-modules` (output thực tế: `xcodebuild/ReleaseARM64`).
- [x] Chạy `pkg/dynamic_modules/example/run.sh` → `load basic` hoạt động (`run_poc_arm.sh`).
- [x] Host tải module qua HTTP (`host_net`, `run_poc_net.sh`) — dùng `http.server` giả lập;
      nối vào server self-host thật: ✅ bản Flutter Android.
- [x] Đo: thời gian nạp, overhead interpreted vs native, kích thước `.bytecode` (`run_bench.sh`).
- [x] Ghép vào Flutter engine — Android chạy được (`dyn_modules_android_result.md`);
      iOS thiết bị thật chạy được (`dyn_modules_ios_result.md`).
      *(Lần E2E đầu trên macOS desktop chỉ để chứng minh khả thi — lab, không phải target app.)*
