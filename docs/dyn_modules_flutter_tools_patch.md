# Vá flutter_tools cho pipeline dynamic modules — thiết kế cụ thể

> Phần "engine-independent" của Giai đoạn 2. Nghiên cứu trên flutter framework upstream
> mới nhất (`flutter-framework`, rev `1be6586f`, 2026-09-30). Kết quả: **nhẹ hơn dự kiến**
> — phần lớn inject được qua flag có sẵn, chỉ 1 gap nhỏ cần vá.

## Phát hiện chính

`KernelSnapshot` (`build_system/targets/common.dart:138`) compile app Dart→kernel qua
frontend_server, và **đã có passthrough** `extraFrontEndOptions` (dòng 210) → truyền
thẳng mọi cờ vào frontend_server:

```dart
final List<String> extraFrontEndOptions =
    decodeCommaSeparated(environment.defines, kExtraFrontEndOptions);
...
await compiler.compile(..., extraFrontEndOptions: extraFrontEndOptions, ...);
```

→ Người dùng đưa cờ qua `flutter build ... --extra-front-end-options=<cờ>`.

## Cần gì & vá gì

| Việc | Cách làm | Vá flutter_tools? |
|---|---|---|
| Bật interpreter trong engine | build engine `dart_dynamic_modules=true` | Không (việc của engine) |
| Truyền `--dynamic-interface` khi compile host | `--extra-front-end-options=--dynamic-interface=<yaml>` | **KHÔNG** — dùng flag có sẵn* |
| Sinh **anchor dill** (kernel no-aot) làm mỏ neo cho module | KernelSnapshot chỉ ra 1 dill (aot). Cần thêm 1 dill no-aot | **CÓ** — gap nhỏ (xem dưới) |
| Compile module → bytecode | `dart2bytecode --import-dill <anchor> --validate <yaml>` ngoài `flutter build` | Không (bước riêng, như PoC) |
| App nạp module lúc chạy | `loadModuleFromUri(<server>/...)` sau boot | Không (code app) |

*Với điều kiện **frontend_server của engine ddm chấp nhận `--dynamic-interface`** — cần
verify sau khi build engine (frontend_server build từ Dart dyn_modules thì có; PoC CLI đã
dùng đúng cờ này trên `gen_kernel_aot`).

## Gap duy nhất phải vá: sinh anchor dill

`dart2bytecode` cần `--import-dill <host_no_aot.dill>` để module bám đúng "hình dạng" API
host. `flutter build` AOT chỉ tạo dill đã tối ưu. Hai cách:

**Cách A (không vá — khuyến nghị làm trước):** chạy thủ công 1 lệnh gen_kernel no-aot trên
đúng `lib/main.dart` + package_config của app, tạo anchor dill riêng — y như bước [1]
trong `dyn_modules_poc_guide.md`. Không đụng flutter_tools. Chỉ cần trỏ đúng
`flutterPatchedSdk` + platform dill của engine ddm.

**Cách B (vá gọn):** thêm vào `KernelSnapshot.build()` một nhánh (bật bằng define mới,
vd `kDynamicModulesInterface`): sau khi compile aot, gọi thêm `compiler.compile(aot:false,
outputFilePath: <buildDir>/app_anchor.dill, extraFrontEndOptions:[--dynamic-interface=...])`.
~15-20 dòng, đặt cạnh block `recordedUses`.

→ Đề xuất: MVP dùng **Cách A** (0 dòng vá), chứng minh vòng lặp trên Android trước; sau
đó mới cân nhắc Cách B cho tiện.

## Lệnh build host (dự kiến, Android release, engine ddm)

```bash
# engine ddm đã build + set qua --local-engine
flutter build apk --release \
  --local-engine=android_release_arm64_ddm \
  --local-engine-host=host_release \
  --extra-front-end-options=--dynamic-interface=dynamic_interface.yaml
# → app AOT có interpreter + interface. Anchor dill: tạo riêng (Cách A).
```

> Repo bạn đã ép `--local-engine` trong `sb.sh/publish.sh` (theo tài liệu gốc) → chỗ nối
> tự nhiên: thêm mode trỏ tới out-dir engine ddm + thêm `--extra-front-end-options`.

## Việc verify sau khi engine xong
> Cập nhật 2026-10-01: (1) ✅ frontend_server ddm nhận `--dynamic-interface`;
> (2) ✅ `flutter build` với `--local-engine=<ddm>` chạy trơn (verify lần đầu trên macOS
> desktop — nền tảng lab, **không phải target app**; app thật chỉ build android + ios);
> (3) ✅ anchor dill Cách A + dart2bytecode ra `power.bytecode` hợp lệ;
> (4) ✅ **Android** + server: chạy được (`dyn_modules_android_result.md`);
> (5) ✅ **iOS thiết bị thật**: chạy được (`dyn_modules_ios_result.md`).
1. frontend_server ddm có nhận `--dynamic-interface` không (kỳ vọng: có).
2. `flutter build` với `--local-engine=<ddm>` chạy trơn không.
3. Anchor dill (Cách A) + `dart2bytecode` ra `.bytecode` hợp lệ với app thật.
4. App Android nạp module qua `loadModuleFromUri` từ self-host server.

## Con trỏ
- KernelSnapshot: `flutter-framework/packages/flutter_tools/lib/src/build_system/targets/common.dart:138`
- Passthrough: cùng file dòng ~210 (`extraFrontEndOptions`)
- AOT: `common.dart:361` (`AotElfBase`), `449` (`AotElfRelease`)
- Pipeline tham chiếu: `dyn_modules_poc_guide.md` §2
