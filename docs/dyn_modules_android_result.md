# KẾT QUẢ ANDROID: Code-push self-host trên Flutter Android bằng Dynamic Modules

> ✅ **ĐÃ CHẠY THÀNH CÔNG** 2026-10-01, Android emulator `Medium_Phone_API_35` (arm64-v8a, API 35).
> App Flutter release (AOT, Impeller/OpenGLES) hỏi **server self-host** của repo → tải
> `power.bytecode` qua HTTP → nạp bằng interpreter → `2^10=1024`. 100% nguồn public.

## Bằng chứng
```
I flutter : POC_RESULT ops=[^] 2^10=1024 bytes=903 fetch_us=75859 load_us=236
            src=http://10.0.2.2:8790/artifacts/patch/1/power.bytecode
```
- Server `checks.log`: `{"app_id":"dynmod-poc","platform":"android","arch":"aarch64",...,
  "response":{"patch_available":true,"number":1}}`
- Ảnh màn hình: `../dart-sdk-build/android_module/evidence/android_poc.png`
- 10/10 lần khởi động lạnh đều thành công: `evidence/runs.txt`

**Đối chứng âm** (cùng source, engine prebuilt chính thức, không ddm):
```
POC_ERROR Unsupported operation: Loading of dynamic modules is not supported.
#0 _loadDynamicModule (dart:_internal-patch/internal_patch.dart:453)
```
→ khả năng code-push đến từ **engine ddm**, không phải từ code app. (`evidence/stock_negative_control.txt`)

## Chuỗi đã làm (tái lập được)

### 1. Build engine Android ddm
Script: `../dart-sdk-build/build_android_engine.sh`
```bash
cd flutter-framework/engine/src          # Flutter monorepo 1be6586f, Dart 0e7642b8
flutter/tools/gn --runtime-mode release --android --android-cpu arm64 --no-lto \
  --no-prebuilt-dart-sdk --gn-args=dart_dynamic_modules=true
ninja -j$(sysctl -n hw.ncpu) -C out/android_release_arm64     # 8310 bước, exit 0
```
- Android deps đã có sẵn trong checkout (DEPS: `download_android_deps` mặc định true trên mac).
- Kiểm chứng: `strings libflutter.so` có `Unexpected Dart bytecode magic`, `interpreter_trace_file_max_bytes`.

⚠️ **Gotcha:** `autoninja` (depot_tools) crash khi target Android trên macOS — nó bật
"android build server" và đọc `/proc/self/fd/1` (chỉ có trên Linux) → `FileNotFoundError`.
Cách xử lý: gọi `ninja` trực tiếp.

### 2. Build app (không vá flutter_tools)
```bash
flutter build apk --release --target-platform android-arm64 \
  --local-engine-src-path $FF/engine/src \
  --local-engine=android_release_arm64 --local-engine-host=host_release_arm64 \
  --extra-front-end-options=--dynamic-interface=dynamic_interface.yaml \
  --dart-define=CHECK_URL=http://10.0.2.2:8790/api/v1/patches/check
```
Android manifest: thêm `INTERNET` + `usesCleartextTraffic="true"` (HTTP trong lab; production dùng HTTPS).

### 3. Compile module
Giống PoC đầu (anchor dill no-aot → `dart2bytecode`), dùng
`out/android_release_arm64/flutter_patched_sdk/platform_strong.dill`.

**Phát hiện:** `platform_strong.dill` của Android và host **giống hệt byte**, và
`power.bytecode` compile cho Android **trùng byte với bản build lab trên macOS** →
**một module dùng cho mọi nền tảng/kiến trúc** (kể cả iOS). Trái với Shorebird
Android: patch là bidiff của `libapp.so`, phải sinh riêng cho từng ABI
(arm64-v8a, armeabi-v7a, x86_64).

### 4. Server self-host (instance thí nghiệm, tách khỏi production)
```bash
cd server && SELFHOST_DATA_DIR=<../dart-sdk-build>/poc-server-data PORT=8790 node src/index.js
```
`poc-server-data/db.json`: app `dynmod-poc`, release `1.0.0+1`, patch #1 = `power.bytecode`
(sha256 `f01b0b57…`, `downloadUrl` trỏ `10.0.2.2:8790`). **Không đụng `server/data/db.json`.**

### 5. Luồng runtime trong app (`sample_app/lib/main.dart`)
```
boot → POST /api/v1/patches/check  (cùng giao thức updater Shorebird)
     → download_url → GET .bytecode → loadModuleFromBytes → entry-point(Registry)
```

## Số liệu (emulator, sơ bộ)

**Thời gian** (10 lần khởi động lạnh, `evidence/runs.txt`):

| Đại lượng | median | min | max |
|---|---|---|---|
| `load_us` (loadModuleFromBytes, 903 B) | **~177 µs** | 73 µs | 3224 µs |
| `fetch_us` (check + tải qua NAT emulator) | ~83 ms | 8.8 ms | 125 ms |

Nạp module rất rẻ, đúng với kết quả trên CLI (54 µs). Phương sai lớn là do lúc khởi động lạnh còn tranh CPU với việc khởi tạo engine. Thời gian tải phụ thuộc vào mạng (ở đây là NAT của emulator), không phụ thuộc vào cơ chế.

**Kích thước** (arm64-v8a, cùng source + cùng `CHECK_URL`):

| | stock (prebuilt) | ddm | chênh |
|---|---|---|---|
| APK | 15,231,411 B | 18,924,419 B | **+3.69 MB (+24.2%)** |
| `libapp.so` (AOT app) | 3,474,392 B | 5,374,936 B | **+1.90 MB (+54.7%)** |
| `libflutter.so` (engine) | 11,335,328 B | 13,127,792 B | +1.79 MB (+15.8%)* |

- Phần `libapp.so` to thêm do `dynamic_interface` khiến `dart:core` thành callable, nên không tree-shake được. Đây là cùng nguyên nhân với mức +140% đo trên CLI, nhưng app Flutter vốn đã lớn nên tỉ lệ tương đối nhỏ hơn.
- \* Phần `libflutter.so` chênh **bị phóng đại**: engine stock là bản chính thức (build có LTO), còn engine ddm được build `--no-lto`. Muốn tách riêng chi phí của interpreter thì phải build thêm một engine `--no-lto` không có ddm để so cho công bằng.

## Giới hạn / việc tiếp
- Mới chạy trên emulator. Cần lặp lại trên máy Android thật và đo N≥30.
- App chưa kiểm sha256 của module so với `hash` trong response check (server đã trả về `hash`). Cần thêm bước này, cùng với chữ ký module (`hash_signature`).
- Chưa đo slowdown của interpreter trên Android (bench trước đó mới chạy trên CLI macOS).
- iOS thiết bị thật: **đã chạy** (2026-10-01, `dyn_modules_ios_result.md`).

## Artifact
- Engine: `flutter-framework/engine/src/out/android_release_arm64`
- App: `sample_app/` (đã thêm `android/`)
- Module + bằng chứng: `../dart-sdk-build/android_module/{power.bytecode,anchor.dill,evidence/}`
- Log: `build_android_engine.log`, `ninja_android_full.log`, `build_android_app*.log`

## Bổ sung: module mang theo PACKAGE MỚI (2026-10-01)

**Câu hỏi:** code-push có thêm được một package mà host chưa từng có không?
**Kết quả: CÓ (với package thuần Dart).**

1. Build và cài host (`main.dart`, có `CHECK_URL`) **trước khi** package tồn tại.
2. Tạo `pkgs/thesis_mathx` (lũy thừa nhanh), phụ thuộc vào `pkgs/thesis_util` (bắc cầu).
3. `modules/power_pkg.dart` import `package:thesis_mathx` → `bash tools/cmd/dynmod.sh module …` →
   `power_pkg.bytecode` 1830 B. `strings` cho thấy cả `package:thesis_mathx` và
   `package:thesis_util` đều được biên dịch **vào module**.
4. Đăng lên server làm **patch #2** → app đang cài (không build lại) hỏi server → nạp:
   ```
   POC_RESULT ops=[^, via thesis_mathx@1.0.0] 2^10=1024 bytes=1830 ... src=.../patch/2/power_pkg.bytecode
   ```
   `via thesis_mathx@1.0.0` = `FastPow.id` → `tag()` của thesis_util, tức code của cả 2 package đã chạy.
5. Kiểm chứng ngược: `libapp.so` của host chứa `thesis_mathx` **0 lần** và `FastPow` **0 lần**.

Ghi chú: package chỉ cần có trong `package_config` để `dart2bytecode` resolve được (thêm
`path:` vào pubspec). Host không import nên package không vào app.

**Giới hạn (chưa thử / đã biết):**
- Package có **mã native** (plugin Kotlin/Swift như camera, firebase): KHÔNG được. Phần native
  phải được biên dịch vào app lúc build. Module cũng chưa hỗ trợ FFI.
- Package dùng widget/`dart:ui`: cần interface khai báo `package:flutter` là callable/extendable.
  Chưa thử.
- Package host **đã có**: module dùng bản của host (không mang phiên bản khác được), và chỉ
  được gọi các thành viên mà interface cho phép.

Bằng chứng: `android_module/evidence/new_package_module.txt`.
