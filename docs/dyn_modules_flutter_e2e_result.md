# KẾT QUẢ E2E: Code-push trên Flutter THẬT bằng Dynamic Modules (từ nguồn public)

> ✅ **ĐÃ CHẠY THÀNH CÔNG** trên máy này, 2026-10-01, macOS ARM64.
> App Flutter thật (Impeller/Metal) nạp module bytecode lúc chạy qua interpreter,
> thêm tính năng mới KHÔNG rebuild app. Toàn bộ từ **Flutter/Dart upstream public**,
> KHÔNG dùng fork private của Shorebird.

> ⚠️ **Doc này là THÍ NGHIỆM trên macOS desktop, không phải target sản phẩm.**
> Dự án chỉ build & ship **Android + iOS**. macOS được chọn ở bước E2E vì chạy
> nhanh nhất và không cần ký code — nó chứng minh *cơ chế* dynamic modules hoạt
> động trên app Flutter thật. Số đo ở đây **không dùng làm số liệu sản phẩm**
> (số chính thức lấy từ Android/iOS: `dyn_modules_android_result.md`,
> `dyn_modules_ios_result.md`). Các gotcha sandbox/JIT dưới đây là đặc thù macOS
> desktop — iOS không có (đã verify chạy được không cần entitlement JIT), nên
> **không mang sang app thật**.

## Bằng chứng
```
POC_RESULT ops=[^] 2^10=1024
```
App khởi động chỉ có phép `+`. Lúc chạy nạp `power.bytecode` (903 B) → interpreter đăng ký
`^`, `sqrt`... → tính `2^10=1024`. Code `^` KHÔNG có trong app đã build.

## Lật kết luận tài liệu gốc
Tài liệu gốc (`DEPLOYMENT_LOG.md`) kết luận iOS/engine OTA = ngõ cụt, "phải port dart-sdk
fork private (404) của Shorebird". **Sai với thực tế hiện tại**: Flutter/Dart upstream ĐÃ có
tính năng dynamic modules chính chủ (interpreter + dart2bytecode), build engine bật cờ
`dart_dynamic_modules=true` là dùng được — không cần fork private.

## Chuỗi đã làm (tái lập được)

### 1. Nguồn (public)
- Flutter monorepo `flutter/flutter` @ `1be6586f` (bundled engine), Dart `0e7642b8`
  (có interpreter.cc + pkg/dart2bytecode + pkg/dynamic_modules + `DART_DYNAMIC_MODULES`).
- Setup: copy `engine/scripts/standard.gclient` → `.gclient` (solution `name="."`) vào
  gốc checkout, `gclient sync -D --no-history`.

### 2. Build engine ddm (host macOS arm64)
```bash
cd flutter-framework/engine/src
flutter/tools/gn --runtime-mode release --no-lto --mac-cpu arm64 \
  --no-prebuilt-dart-sdk --full-dart-sdk --gn-args=dart_dynamic_modules=true
autoninja -C out/host_release_arm64
# → gen_snapshot, dart2bytecode, frontend_server, dart-sdk, FlutterMacOS.framework (đều có dyn_modules)
```
⚠️ Gotcha: ninja dừng vì thiếu **Metal Toolchain** → `xcodebuild -downloadComponent MetalToolchain`
(839MB, tự động) rồi resume.

### 3. Build app Flutter với engine ddm
```bash
flutter build macos --release \
  --local-engine-src-path <FF>/engine/src \
  --local-engine=host_release_arm64 --local-engine-host=host_release_arm64 \
  --extra-front-end-options=--dynamic-interface=dynamic_interface.yaml
```
→ frontend_server **nhận `--dynamic-interface`** (không cần vá flutter_tools).

### 4. Compile module (target=flutter)
```bash
# anchor dill (no-aot) — mỏ neo
dartaotruntime gen/gen_kernel_aot.dart.snapshot --platform flutter_patched_sdk/platform_strong.dill \
  --target flutter --no-aot --no-link-platform --packages <app>/.dart_tool/package_config.json \
  --dynamic-interface dynamic_interface.yaml -Ddart.vm.product=true --output anchor.dill <app>/lib/main.dart
# module → bytecode
dartaotruntime gen/dart2bytecode.dart.snapshot --platform ...platform_strong.dill \
  --target flutter --import-dill anchor.dill --validate dynamic_interface.yaml \
  --packages ... -Ddart.vm.product=true --output power.bytecode <app>/modules/power.dart
```

### 5. Runtime: app nạp module
`loadModuleFromBytes(file.readAsBytes())` → `(ep as void Function(Registry))(reg)`.

## Gotchas macOS (ghi cho thesis — đều là chất liệu phân tích iOS)
1. **Metal Toolchain** thiếu → tải component.
2. **App Sandbox** bật mặc định → app không đọc file module / ghi ngoài container. Tắt
   `com.apple.security.app-sandbox=false` (hoặc để file trong container).
3. **JIT entitlements** cho interpreter: `allow-jit`, `allow-unsigned-executable-memory`,
   `disable-library-validation` (thêm vào Release.entitlements). Đây đúng rào code-signing —
   macOS tự ký được, **iOS thì KHÔNG** → chính là câu hỏi nghiên cứu cho iOS thật.

## Ý nghĩa cho đồ án
- RQ1 (khả thi): **CÓ** — code-push trên Flutter thật chạy được từ nguồn public.
- Đóng góp: tái lập + tài liệu hoá đầy đủ chuỗi mà Shorebird đóng; chứng minh không cần
  fork private.
- Kết luận RQ1: khả thi trên **cả 2 nền tảng sản phẩm** — Android release ddm ✅
  (2026-10-01, `dyn_modules_android_result.md`) và iOS thiết bị thật ✅ (ký ad hoc,
  KHÔNG cần entitlement JIT, `dyn_modules_ios_result.md`). Lần chạy macOS desktop ở
  doc này chỉ là bằng chứng khả thi đầu tiên, không phải số liệu sản phẩm.
- ⚠️ Gotcha #3 (JIT entitlement) là **đặc thù macOS desktop**: iOS thiết bị thật đã
  chạy được mà không cần `allow-jit`/`allow-unsigned-executable-memory` → không phát
  sinh rào cho app thật.

## Artifact
- App: `../dart-sdk-build/sample_app/` (host + modules/power.dart + dynamic_interface.yaml)
- Engine: `../dart-sdk-build/flutter-framework/engine/src/out/host_release_arm64`
- Module: `../dart-sdk-build/power.bytecode`
