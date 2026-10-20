# KẾT QUẢ iOS THIẾT BỊ THẬT: Dynamic Modules chạy dưới code-signing của iOS

> ✅ **ĐÃ CHẠY THÀNH CÔNG** 2026-10-01 trên **iPhone 16 Pro thật, iOS 26.2 (23C55)**.
> App Flutter release (AOT) nạp `power.bytecode` lúc chạy qua interpreter → `2^10=1024`,
> **không có entitlement JIT / dynamic-codesigning nào**, kể cả với chữ ký **ad hoc
> (Apple Distribution, `get-task-allow=false`)**. 100% nguồn public.
>
> → Trả lời thực nghiệm **RQ4 (phần kỹ thuật)**: rào code-signing của iOS KHÔNG chặn cơ chế
> này, vì interpreter không sinh/không map mã máy mới — bytecode chỉ là *dữ liệu*.

## Bằng chứng

| Cấu hình ký | Identity | Entitlements | Kết quả |
|---|---|---|---|
| Development (`dev1`) | Apple Development | app-id, team-id, `get-task-allow=true` | ✅ 10/10, load median **65 µs** |
| **Ad hoc (`adhoc1`)** | **Apple Distribution** | app-id, team-id, **`get-task-allow=false`** | ✅ **10/10**, load median **~67 µs** |
| Đối chứng âm: engine prebuilt chính thức | Apple Development | như trên | ❌ `Unsupported operation: Loading of dynamic modules is not supported.` |

```
POC_RESULT ops=[^] 2^10=1024 bytes=903 fetch_us=13618 load_us=69 src=file   ← lần đầu (dev)
```
App được launch bằng `devicectl device process launch`, **không gắn debugger**. Như vậy kết quả không dựa vào ngoại lệ JIT mà iOS chỉ cấp khi có debugger gắn vào.

File bằng chứng nằm ở `../dart-sdk-build/ios_evidence/`: `first_run.txt`, `runs.txt` (dev), `runs_adhoc.txt`, `stock_negative_control.txt`, `size_{ddm,stock}.txt`.

**Vì sao chạy được (đối chiếu với Shorebird Android):** Shorebird Android nạp patch bằng
`Dart_LoadELF`, tức `mmap` + `PROT_EXEC` một file ELF mới. Trên iOS, kernel từ chối việc này
với mọi trang nhớ thực thi chưa được Apple ký. Dynamic modules thì gắn bytecode vào hàm và đặt
entry-point về stub `InterpretCall` có sẵn trong `Flutter.framework` đã ký
(`dyn_modules_dispatch_mechanism.md`). CPU chỉ chạy mã máy đã ký; bytecode được đọc như dữ liệu.

## Chuỗi đã làm (tái lập được)

### 1. Build engine iOS ddm (theo `ci/ios_release_ddm`, thêm `--no-lto`)
Script: `../dart-sdk-build/build_ios_engine.sh`
```bash
flutter/tools/gn --ios --runtime-mode release --no-lto --no-prebuilt-dart-sdk \
  --gn-args=dart_dynamic_modules=true
ninja -C out/ios_release flutter/lib/snapshot:generate_snapshot_bins \
  flutter/shell/platform/darwin/ios:flutter_framework          # 7157 bước, exit 0
```

### 2. App (`sample_app/ios`)
- `flutter create --platforms=ios`, sau đó sửa `project.pbxproj` (target Runner):
  `PRODUCT_BUNDLE_IDENTIFIER=com.gamevee.th1`, `DEVELOPMENT_TEAM=NFWVFL2567`,
  `CODE_SIGN_STYLE=Manual`, `PROVISIONING_PROFILE_SPECIFIER=dev1` (hoặc `adhoc1` +
  `CODE_SIGN_IDENTITY=Apple Distribution`).
- **Không** thêm entitlement nào. **Không** tắt ATS (xem mục giới hạn).
```bash
flutter build ios --release --local-engine-src-path $FF/engine/src \
  --local-engine=ios_release --local-engine-host=host_release_arm64 \
  --extra-front-end-options=--dynamic-interface=dynamic_interface.yaml
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
```

### 3. Module + nạp
- `out/ios_release/flutter_patched_sdk/platform_strong.dill` **giống byte** với bản Android/host
  → dùng lại **đúng** `power.bytecode` 903 B (cùng một file cho Android và iOS).
- Đưa module vào app: `xcrun devicectl device copy to --domain-type appDataContainer
  --domain-identifier com.gamevee.th1 --source power.bytecode --destination Documents/power.bytecode`
- App đọc file `<container>/Documents/power.bytecode` → `loadModuleFromBytes`, rồi ghi kết quả
  vào `Documents/poc_result.txt`; kéo file về bằng `devicectl device copy from`.

## Kích thước (Runner.app, arm64)

| | stock (prebuilt) | ddm | chênh |
|---|---|---|---|
| Runner.app | 14,064 KB | 23,132 KB | +9.07 MB (+64%) |
| `App.framework/App` (AOT app) | 3,408 KB | 5,440 KB | **+2.0 MB (+60%)** |
| `Flutter.framework/Flutter` | 9,208 KB | 16,244 KB | +6.9 MB (+76%)* |

Phần `App` tăng lên tương đương với Android (+55%), cùng nguyên nhân là `dart:core` callable nên không tree-shake được. \* Phần `Flutter` **bị phóng đại**, vì bản stock là build chính thức có LTO còn bản ddm build `--no-lto`. Cần build thêm engine stock `--no-lto` để so công bằng.

## Giới hạn & phạm vi kết luận (trung thực)
- **Đã chứng minh:** interpreter chạy được trên iPhone thật dưới chữ ký phát hành (ad hoc),
  không cần JIT entitlement.
- **Phạm vi:** đây là thí nghiệm nghiên cứu tính khả thi kỹ thuật (nạp module trên thiết bị
  thật), không phải sản phẩm — provenance, versioning ABI và FFI từ module vẫn là việc còn
  thiếu (ghi rõ ở cuối file).
- **Đường truyền:** bản iOS nạp module từ file cục bộ. Khi làm, mình đã định tắt ATS
  (`NSAllowsArbitraryLoads`) để tải qua HTTP trong LAN nhưng **bị chặn vì làm yếu bảo mật truyền
  tải**, nên đã gỡ ra. Đường mạng đã kiểm chứng trên Android. Muốn có end-to-end trên iOS thì
  dùng **HTTPS với chứng chỉ hợp lệ** (đây cũng là yêu cầu production), không tắt ATS.
- Chưa kiểm sha256 / chữ ký module trong app.
- Một máy, một module nhỏ. Slowdown của interpreter trên iPhone chưa đo.
- Thí nghiệm đã **cài đè `com.gamevee.th1` v1.0.4** trên máy. Hiện máy đang chạy bản PoC
  (ad hoc). Cần cài lại bản 1.0.4 nếu bạn còn dùng.
