# Kế hoạch "build host 1 lần — chỉ hot update module app_package"

> Mục tiêu: build `app/` (host) **một lần**, lên store. Sau đó mọi thay đổi của
> `../app_package` chỉ đi bằng `.bytecode` (dyn_modules), không build lại host.
>
> Tiền đề đã có: engine ddm @1be6586f (host/android/ios), `content_kit`,
> `dyn_loader`, `dynmod_gate_impl`, `dynpush.sh patch` (manifest tĩnh),
> `dyniface.sh` (vòng augment — sẽ được THAY ở P4).
>
> Liên quan: `dynmod_replace_shorebird_plan.md` (G0–G7), `dynmod_g0_audit.md`.

## 0. Nguyên tắc nền (đọc trước)

1. **Host = nền tảng đóng băng.** Thứ gì nằm trong host (engine, plugin native,
   version package, interface, assets, quyền native, hợp đồng content_kit)
   không đổi được nữa cho tới host release kế tiếp.
2. **Module chỉ thay được code Dart KHÔNG có trong host.** Library trùng URI
   với host → "already loaded". Không có "đè" version package của host.
3. **Mỗi library thuộc đúng 1 phía.** Anchor phải == kernel thật của host.
   Kiểm bằng máy, không bằng mắt.
4. **Interface sinh từ kernel, không sinh từ lỗi.** Library-level là mặc định.
5. **Một host release = 1 bộ khoá** `host_id = hash(pubspec.lock host,
   anchor.dill, dynamic_interface.yaml, engine rev)`. Module luôn gắn host_id.
6. Không nạp 2 version module trong 1 process → bản mới áp ở **lần mở app sau**.

## 1. Tổng quan giai đoạn

| Pha | Nội dung | Ước lượng | Ra quyết định gì |
|---|---|---|---|
| P0 | Spike rủi ro trên máy thật | 2–3 ngày | Cái gì bắt buộc nằm ở host |
| P1 | Chốt ranh giới package (manifest) | 1–2 ngày | Danh sách host packages v1 |
| P2 | Làm sạch app_package cho mô hình module | 3–5 ngày | — |
| P3 | Hợp đồng content_kit v2 (đóng băng) | 2 ngày | API host↔module trọn đời host |
| P4 | Host "fat": pin + anchor + interface từ kernel | 4–6 ngày | — |
| P5 | Pipeline module gắn host_id | 2 ngày | — |
| P6 | Vòng đời cập nhật trên máy + rollback | 2–3 ngày | — |
| P7 | E2E + đo đạc + đóng băng host v1 | 3–4 ngày | Go/No-go phát hành host |
| P8 | Vận hành | liên tục | Khi nào được phép build host lại |

Tổng: ~3–4 tuần công. P0 phải xong trước P1; P2 và P3 chạy song song được.

---

## P0 — Spike rủi ro (làm TRƯỚC mọi thứ)

Dùng module nhỏ (không phải cả app_package) để trả lời nhanh từng câu, trên
**Android máy thật + iOS máy thật**, engine ddm release.

| # | Câu hỏi | Cách thử | Nếu FAIL thì |
|---|---|---|---|
| S1 | Isolate chạy được hàm nằm trong module? (`IsolateManager`, `Isolate.run`, `compute`) | Module gọi `Isolate.run(() => fib(30))` + 1 worker `@isolateManagerWorker` khai trong module | Worker phải nằm ở host, nhận/trả `Map` → logic `ws_isolate_worker.dart` bị đóng băng theo host |
| S2 | Load module 2 lần trong 1 process (v1 rồi v2 cùng library URI) | Load v1, load v2 | Xác nhận phải áp ở lần mở sau (dự kiến FAIL — chỉ cần biết lỗi gì) |
| S3 | Module `implements`/`extends` class host có member private (stub noSuchMethod) | Module có `class X implements File` / `extends Notifier` | Danh sách entry private phải sinh (P4.4) |
| S4 | Plugin gọi từ module (platform channel) | Module gọi `audioplayers`, `sqflite`, `webview_flutter`, `game_engine` channel — plugin Dart ở host | Plugin đó chưa vào anchor đúng (kiểm P4.2) |
| S5 | Asset từ mạng thay `rootBundle` | Sprite atlas tải từ CDN + cache | Bundle sẵn trong host (đóng băng) |
| S6 | Hiệu năng màn nặng nhất (home, list, mini game) | Đo frame time module vs AOT | Đẩy package nóng vào host (P1 tầng T1) |
| S7 | `Image`/`Lottie`/`Rive` file trong module | Lottie + Rive từ URL | — |

**Nghiệm thu P0:** bảng S1–S7 có kết quả PASS/FAIL + log, ghi vào
`docs/dynmod_build_once_spike.md`.

---

## P1 — Chốt ranh giới host / module

### P1.1 Manifest nguồn sự thật: `configs/abi/host_packages.yaml`

```yaml
host_id_version: 1
tiers:
  t0_required:        # native, FFI, platform_interface, boot (loading_kit dùng)
    - audioplayers
    - audioplayers_android
    - audioplayers_darwin
    - audioplayers_platform_interface
    # ... (sinh bằng tool P1.2 rồi người duyệt)
  t1_frozen_pure_dart: # ổn định + nóng hiệu năng → AOT trong host
    - flutter_riverpod
    - riverpod
    - go_router
    - dio
    # ...
  module_allowed:     # pure-Dart muốn còn nâng version → đi theo module
    - lottie
    # ...
  excluded:           # web/desktop/dev tooling — không ở đâu cả
    - "*_web"
    - "*_windows"
    - "*_linux"
    - "*_macos"
    - web
    - dio_web_adapter
    - flutter_web_plugins
    - flutter_lints
    - lints
    - test_api
    - matcher
    - leak_tracker*
    - vm_service
```

### P1.2 Tool phân tầng (dry-run): `tools/cmd/dyniface/classify_packages.py`

- Input: `app/.dart_tool/package_config.json`, `app/pubspec.lock`, pubspec từng package.
- Luật tự động:
  - có `flutter: plugin:` → t0
  - import `dart:ffi` / depend `ffi`, `jni`, `objective_c` → t0
  - tên `*_platform_interface` của plugin t0 → t0
  - được `loading_kit`/`dyn_loader`/`main_app_package` dùng → t0 (host đằng nào cũng có)
  - đóng gói bắc cầu: dep của package t0/t1 → cùng tầng (không để package host
    phụ thuộc package module)
  - còn lại → đề xuất t1 hoặc module_allowed, **người duyệt**
- Output: bản nháp `host_packages.yaml` + báo cáo xung đột.

### P1.3 Quy tắc chọn t1 vs module_allowed

| Câu hỏi | t1 (host) | module_allowed |
|---|---|---|
| Có thể cần nâng version trong vòng đời host? | Không | Có |
| Chạy trong hot path (build/layout/parse JSON lớn)? | Có | Không |
| Có `extends`/`implements` dày đặc từ app_package? | Cân nhắc (cần extendable) | — |

Gợi ý mặc định: t1 = riverpod, go_router, dio, http, intl, protobuf, fixnum,
json_annotation, freezed_annotation, collection, meta, crypto, uuid, clock,
rxdart, flutter_svg/vector_graphics*, cached_network_image stack, hive*,
google_fonts, isolate_manager. module_allowed = widget UI nhỏ (gap, blur,
shimmer_animation, gradient_borders, grouped_list, pinput, styled_text,
qr_flutter, lottie, logger, pretty_dio_logger, dartz).

### P1.4 Plugin "phòng xa"

Liệt kê plugin native có thể cần trong vòng đời host (push, deep link,
permission_handler, image_picker, camera, local_auth, share…). Thứ nào có khả
năng >30% → đưa vào t0 ngay + khai quyền native (P4.6).

**Nghiệm thu P1:** `host_packages.yaml` được duyệt; mọi package trong
`package_config.json` thuộc đúng 1 tầng; tool exit 0.

### P1 — Kết quả (2026-10-09)

Tool: `bash tools/cmd/dyniface.sh packages [--write [--force]] | packages check`
(`tools/cmd/dyniface/classify_packages.py`). Manifest: `configs/abi/host_packages.yaml`.

Luật đã cài (khác bản nháp ở trên):
- Cạnh phụ thuộc tính theo **import thật trong `lib/`** (mọi nhánh conditional
  import), không theo pubspec — dep chỉ dùng trong `hook/build.dart`
  (`hooks`, `code_assets`, `yaml`, `args`, `package_config`…) không vào kernel.
  Ngoại lệ: plugin → plugin (cài đặt federated) luôn tính.
- Package có `flutter: assets:/fonts:` → t0 (`cupertino_icons`).
- `rive` → t1 (khoá version với `rive_native`).
- Dep khai trong pubspec module nhưng chưa import → `module_allowed`.

| Tầng | Số package |
|---|---|
| sdk | 2 |
| t0_required | 110 |
| t1_frozen_pure_dart | 18 |
| module_allowed | 15 |
| module_internal | 31 |
| excluded | 39 |

Phát hiện → chuyển việc sang P2/P4:
1. **`app_env` (nội bộ, logic nghiệp vụ) bị kéo vào host** vì `game_engine`
   export `platform_detect` (dùng 2 getter `AppDevice.isFirefoxBrowser/
   isPhoneBrowser`). → P2.9: gỡ phụ thuộc `game_engine` → `app_env`, nếu không
   `app_env` đóng băng theo host.
2. **66 package host lệch version** giữa `app/pubspec.lock` và
   `app_package/pubspec.lock` (vd. `video_player` 2.14.1 vs 2.10.1,
   `xml` 7.0.1 vs 6.6.1, `sentry` 9.30.1 vs 9.24.0). Module luôn compile bằng
   lock của host → P2.4: test app_package với version host trước khi freeze.
3. **96 package host chưa là direct dep của `app/pubspec.yaml`** → P4.1 thêm
   vào để file pin import hợp lệ.
4. G0 ghi nhầm: `flutter_in_app_pip` **không phải plugin native** (pure-Dart).
   `blur`, `grouped_list`, `lottie`, `flutter_in_app_pip` khai trong pubspec
   app_package nhưng **không file nào import** → xoá khỏi pubspec hoặc giữ ở
   `module_allowed`.
5. Việc duyệt → đã chốt (xem dưới).

### P1 — Quyết định đã chốt (2026-10-09) — P1 ĐÓNG

Sau duyệt: sdk 2 · t0 110 · **t1 24** · **module_allowed 9** · module_internal 31 · excluded 39.
`packages check` exit 0. `--write` giờ là merge (giữ lựa chọn đã duyệt + `planned_native`).

Luật chọn t1 vs module: **chạy trên đường build/layout/paint mỗi frame hoặc
được gọi khắp nơi → t1 (AOT)**; dùng ở 1–3 màn, ít chạy → module (còn nâng
version được).

| Quyết định | Package | Lý do |
|---|---|---|
| Chuyển → t1 | `gap` (175 file), `shimmer_animation` (18), `gradient_borders` | RenderObject/animation/paint mỗi frame — interpreter chậm nhất ở đây |
| Chuyển → t1 | `dartz` (29), `logger` (9) | Gọi khắp domain; dartz ngừng phát triển → đóng băng không mất gì |
| Chuyển → t1 | `lottie` (chưa dùng) | Nếu sau này dùng, parse+render trong interpreter sẽ rất chậm; đặt sẵn rẻ hơn build lại host |
| Giữ t1 mặc định | riverpod, go_router, cached_network_image, flutter_svg, hive, google_fonts, intl, isolate_manager, rive, web_socket_channel… | Hot path state/route/ảnh/socket |
| Giữ module | `pinput`, `styled_text`+`xmlstream`, `qr_flutter`+`qr`, `pretty_dio_logger` | 1–3 file, ít chạy |
| Giữ module, xoá ở P2 | `blur`, `grouped_list`, `flutter_in_app_pip` | Không file nào import |

`planned_native: []` — **không** đưa plugin dự phòng nào (chủ dự án chốt).
Boot + tải module không cần plugin mới. Hệ quả chấp nhận: tính năng cần
native mới (mở app từ link ngoài, chia sẻ, chọn ảnh, secure storage, push…)
= build lại host.

Hai vấn đề chuyển tiếp:
- **Lệch version (66 package):** chốt **version host thắng** — module luôn
  compile bằng lock của host; P2.4 cho app_package chạy test với lock host.
- **`app_env` bị kéo vào host:** chốt **sửa** (P2.9) thay vì chấp nhận đóng băng.
  Sau P2.9 chạy lại `packages --write` → `app_env` phải về `module_internal`.

---

## P2 — Làm sạch app_package cho mô hình module

> **Bối cảnh chốt (2026-10-09):**
> - `../app_package` là **bản SINH RA** bởi `convert_to_package.sh` của
>   s88-flutter — mỗi lần convert XOÁ SẠCH thư mục đích. **Không sửa tay
>   app_package.** Mọi việc dưới đây làm ở 1 trong 2 chỗ:
>   - **Nguồn s88-flutter** (sửa code thật — vd. P2.9), hoặc
>   - **Overlay sau convert** trong repo này: `templates/module/**` +
>     `bash tools/cmd/modprep.sh apply` (chép template + kiểm). Thêm file cho
>     module (entry, adapter interface…) = thêm vào `templates/module/`.
> - App chỉ **iOS + Android** — không web, không desktop.
>
> Quy trình mỗi lần có code mới:
> ```
> s88-flutter: bash convert_to_package.sh [--env=prod]   # sinh ../app_package
> bash tools/cmd/modprep.sh apply                        # áp modules/ + kiểm
> bash tools/cmd/dynpush.sh patch                         # compile + manifest
> ```

### P2 — Kết quả đợt 1

- **modprep** xong: `templates/module/modules/home_content.dart.tmpl` (entry
  `InfoEntry`, lấy từ bản cũ `../app_package_1`) + `tools/cmd/modprep.sh
  apply|check` + `tools/cmd/modprep/vm_web_scan.py`. Check: package name, bản
  áp khớp template, API `SunSports.init()`/`SunSportsApp`, package_config host
  trỏ đúng, nhánh VM không chạm web, `packages check` (P1).
- **P2.3 / P2.8 (web) — ĐÓNG, không cần sửa:** quét 1.894 file nhánh VM: **0**
  import `package:web`/`dart:html`/`dart:js_interop`. Conditional import tự
  chọn bản native, `kIsWeb` là hằng `false` → code web không vào module.
  `device_info_service_stub.dart` dù tên "stub" nhưng không nằm trên nhánh VM.
  Gỡ code web khỏi s88-flutter là **tuỳ chọn** (gọn source), không ảnh hưởng
  module; `modprep check` sẽ FAIL nếu sau này có import web lọt vào nhánh VM.
- **Package desktop** (`*_windows/_linux/_macos`, `win32`, `dbus`, `nm`,
  `posix`, `xdg_directories`): **không bỏ được và không cần bỏ.** Chúng là dep
  bắc cầu do pub kéo theo plugin (`device_info_plus`, `package_info_plus`,
  `connectivity_plus`, `path_provider`…), không khai trực tiếp ở đâu.
  `*_windows/_linux/_macos` không vào kernel iOS/Android (P1: excluded).
  `win32/dbus/nm/posix` vào kernel host vì plugin import thẳng — chỉ tốn ít
  size host; muốn bỏ phải fork plugin → không đáng.
- **P2.9 → làm ở nguồn s88-flutter:** `platform_detect.dart` (lý do kéo
  `app_env` vào host) **không có ai dùng**; `body_level_game_iframe.dart` chỉ
  thuộc nhánh web. Sửa trong s88-flutter `packages/game_engine`: xoá
  `platform_detect/` + export trong `_plugins/plugins.dart`, đọc UA trực tiếp
  trong `body_level_game_iframe.dart` (hoặc xoá hẳn runner web), bỏ `app_env`
  khỏi pubspec `game_engine`. Convert lại → `packages --write` → `app_env` về
  `module_internal`.

| # | Việc | File/chỗ đã thấy |
|---|---|---|
| P2.1 | **Asset**: tạo `AssetSource` (CDN + cache, fallback asset host). Thay `rootBundle.*` | `lib/core/utils/sprite/sprite_atlas.dart` (~15 chỗ dùng) |
| P2.2 | **Isolate**: theo kết quả S1 — giữ trong module hoặc tách worker sang host | `lib/core/services/websocket/isolate/ws_isolate_worker.dart`, `ws_isolate_processor.dart` |
| P2.3 | **Web leak**: rà conditional import; file stub mặc định KHÔNG được import `package:web`/`dart:html` | `lib/core/services/auth/device_info_service_stub.dart` (import `package:web`) + các `*_web.dart` |
| P2.4 | **Khớp version**: script so `app_package/pubspec.lock` với `app/pubspec.lock` cho mọi package t0/t1 → fail nếu lệch | vd. `shared_preferences` ^2.2.0 vs ^2.5.3 |
| P2.5 | `flutter_inappwebview` đang ở dev_dependencies nhưng `game_engine` dùng thật → chuyển dependencies | `app_package/pubspec.yaml` |
| P2.6 | Init native (Sentry, Clarity, RiveNative, Wakelock, audio session) — quyết định cái nào host gọi sẵn, cái nào module gọi | `SunSports.init()` |
| P2.7 | MethodChannel tự viết: chốt tên + giao thức (đóng băng phía native) | `game_engine` (`com.caxilo.engine.surface_compositor`), `game_launcher` |
| P2.8 | Không dùng `dart:mirrors`, FFI, `dart:html` trên nhánh VM | grep CI |
| P2.9 | Gỡ `game_engine` → `app_env` (chỉ dùng 2 getter `AppDevice`) để `app_env` không bị đóng băng theo host | `packages/game_engine/lib/src/_plugins/platform_detect/platform_detect.dart`, `ih_runner/html_iframe/body_level_game_iframe.dart` |

**Nghiệm thu P2:** `flutter analyze` sạch; script P2.4 PASS; grep P2.3/P2.8 rỗng
trên nhánh VM; app_package vẫn chạy standalone.

### P2 — Kết quả đợt 2 (2026-10-09)

| # | Trạng thái | Ghi chú |
|---|---|---|
| P2.1 asset | **Đóng — không cần sửa** | Không chỗ nào tạo `AtlasSource` từ asset, không có literal `'assets/'`; sprite/ảnh game đều là URL từ data. Nhánh `rootBundle`/`Image.asset` là code chết (path không phải http → errorWidget). |
| P2.2 isolate | Chờ máy thật | Cần test `IsolateManager` với worker trong module (S1). |
| P2.3 / P2.8 web | **Đóng** | 0 import web trên nhánh VM; `modprep check` canh. |
| P2.4 version | Chấp nhận | Module luôn compile bằng lock host (host thắng). 71 package lệch lock của app_package — chỉ ảnh hưởng chạy s88-flutter độc lập. |
| P2.5 inappwebview | **Không cần** | Module compile bằng package_config host — có `flutter_inappwebview`. |
| P2.6 init native | Giữ module tự init | `SunSports.init()` chạy trong module (1 lần — template v2 bỏ lần gọi trùng). |
| P2.7 channel | Ghi nhận | `game_engine` giờ ở module → giao thức `com.caxilo.engine.surface_compositor` phía native đóng băng theo host. |
| P2.9 app_env | **Đóng — không sửa nguồn** | Luật P1 mới: plugin NỘI BỘ chỉ đăng ký native (`pluginClass`, không `dartPluginClass`/FFI) → Dart theo module. `game_engine` + `app_env` về `module_internal`. Không đụng s88-flutter (team đã cố ý gom UA vào `AppDevice`). |

Tool: publish module gộp vào **`bash tools/dynpub.sh patch`** (= modprep apply
→ dyniface compile → dynpush patch); `setup.sh` bước 5 cũng gọi modprep apply.

---

## P3 — Hợp đồng content_kit v2 (đóng băng trọn đời host)

Hiện `ContentEntry` chỉ có `version / init / buildView`. Mở rộng trước khi
freeze — sau P7 KHÔNG được sửa (chỉ được thêm ở host release mới).

```dart
abstract interface class ContentEntry {
  String get version;
  int get contractVersion;                     // module tự khai, host kiểm
  Future<void> init(HostServices host);
  Widget buildView(BuildContext context);
  // sự kiện platform host chuyển tiếp
  void onLifecycle(AppLifecycleState state) {}
  Future<bool> onDeepLink(Uri uri) async => false;
  Future<void> onPushMessage(Map<String, Object?> data) async {}
  Future<bool> onBackPressed() async => false;
  // kênh mở rộng tương lai (chiều host → module)
  Future<Object?> invoke(String method, Map<String, Object?> args) async => null;
  Future<void> dispose() async {}
}

abstract interface class HostServices {
  String get hostId;                           // để module tự bật/tắt tính năng
  int get hostContractVersion;
  Set<String> get capabilities;                // 'audio','webview','pip','push',...
  Future<Object?> invoke(String method, Map<String, Object?> args); // module → host
  void reportFatal(Object error, StackTrace st); // cho rollback (P6)
  void markHealthy();                          // module báo khởi động OK
}
```

- Chỉ dùng kiểu Dart/Flutter cơ bản trên biên giới (không riverpod, không
  model của app_package) — biên giới hẹp, interface nhỏ.
- `invoke` dùng chuỗi method + `Map` để thêm tính năng mà không đổi interface.

**Nghiệm thu P3:** content_kit v2 + test; `dynmod_gate_impl` gọi đủ hook;
wrapper `app_package/modules/home_content.dart` cài đặt v2.

### P3 — Kết quả (2026-10-09) — ĐÓNG

Bản thật **gọn hơn bản nháp trên**: module chạy CHUNG isolate với host nên
lifecycle, nút back, Navigator, mọi package host đã tự dùng trực tiếp — hợp
đồng chỉ giữ thứ CHỈ host biết. Đã bỏ khỏi hợp đồng: deep link, push, back,
lifecycle, dispose (không có plugin tương ứng — `planned_native: []`).

`loading_kit/content_kit/lib/content_kit.dart` — `kContentContractVersion = 2`:
- `HostServices`: `contractVersion`, `hostVersion`, `moduleVersion`,
  `appConfig` (`rs_domain`), `capabilities` (= `kHostPackages`, sinh từ
  manifest P1 → `app/lib/shell/host_packages.g.dart`), `invoke` (host v1 chưa
  có method — để dành), `markHealthy`, `reportError`.
- `ContentEntry`: `version`, `contractVersion`, `init(HostServices)`,
  `buildView`, `invoke`.
- `ContentEntrypoint = void Function(ContentRegistry)`.

**Bug sửa kèm:** `dyn_loader.loadFromBytes` kiểm
`result is ContentEntry Function(ContentRegistry)` — closure entrypoint thật
có kiểu `void Function(ContentRegistry)` nên **mọi module thật bị từ chối**
("entrypoint sai kiểu"). Giờ kiểm `ContentEntrypoint`. Test:
`loading_kit/content_kit/test/content_kit_test.dart`.

Host: `app/lib/shell/dynmod_host_services.dart` (`AppHostServices`); gate kiểm
`entry.contractVersion <= kContentContractVersion` (lớn hơn → đánh dấu hỏng,
fail-open). Template `templates/module/modules/home_content.dart.tmpl` cài v2,
bỏ lần gọi `SunSports.init()` trùng.

Test: content_kit 2/2, dyn_loader 14/14, loading_kit 146/146, app 14/14
(chạy bằng flutter hệ thống `/Users/admin/flutter` — `.dart_tool` của
loading_kit/* được pub get bằng nó; chạy bằng flutter checkout ddm sẽ lỗi
"SemanticsRole not exhaustively matched" do lệch framework/engine).

---

## P4 — Host "fat": pin + anchor + interface từ kernel

### P4.1 Sinh pin tự động — thay `dynmod_shared_libs_pin.dart`

`tools/cmd/dyniface/gen_host_pin.py` → `app/lib/shell/host_packages.g.dart`:
import **mọi library public** (lib/ không thuộc src/) của t0 + t1, bỏ file
web/desktop. Chỉ import (CFE giữ mọi library đã import trong kernel), không
cần liệt kê Type. `main.dart` import file này.

### P4.2 Anchor = kernel thật của host

Chọn 1 (thử theo thứ tự):
1. Lấy `app.dill` do `flutter build` sinh trong `app/.dart_tool/flutter_build/<hash>/`
   (kiểm có cần link platform không).
2. Hoặc `gen_kernel_aot` thêm `--source …/dart_plugin_registrant.dart` +
   `-Dflutter.dart_plugin_registrant=…` như flutter_tools.

Kiểm: tập library của anchor ⊇ tập library của kernel host thật; mọi package
t0/t1 có mặt trong anchor.

### P4.3 Interface library-level sinh từ kernel

Tool Dart `tools/dyniface_gen/` (dùng `package:kernel`):
- Duyệt `Library` trong anchor thuộc t0/t1 + `dart:*` cần thiết + `package:flutter`.
- `callable` + `can-be-used-as-type`: `{library: …}` cho TẤT CẢ library (kể cả `src/`).
- `extendable` + `can-be-overridden`: library-level cho package module kế thừa
  (flutter widgets/material/cupertino/rendering/painting, riverpod, go_router,
  dio Interceptor, hive TypeAdapter, content_kit…). Danh sách lấy từ P4.4.
- `dynamically-callable`: chỉ khi module có dynamic call (JSON / `dynamic`).
- Bỏ hẳn: regex trên source, `augment_*`, `fix_disambiguation`, `repair_containers`.

### P4.4 Vá validator chế độ "emit" cho phần còn sót

Patch `pkg/front_end/lib/src/kernel/dynamic_module_validator.dart` (chỉ host
tools, không đụng engine máy): cờ `--dynamic-interface-emit=<file>` → thay vì
báo lỗi thì ghi entry đúng tên kernel. Chạy 1 lần với cả app_package → merge
vào yaml (chủ yếu member private / extendable thiếu). Giữ patch dạng file
`.patch` trong repo, `dynmod.sh engine host` tự áp.

### P4.5 Kiểm tra tách biệt

`tools/cmd/dyniface/check_split.py`: library trong module (dump_bytecode) ∩
library trong anchor = ∅; module không chứa package t0/t1. Chạy sau MỖI lần
compile module.

### P4.6 Cấu hình native superset

AndroidManifest + Info.plist: mọi quyền/usage description của t0 (kể cả plugin
phòng xa), URL scheme/universal link, background mode (audio), ATS (HTTPS thật).

### P4.7 Module mồi đóng gói trong host

Bundle 1 `.bytecode` của app_package vào asset host → lần mở đầu offline vẫn
vào được; cũng là đích rollback cuối cùng (P6).

**Nghiệm thu P4:** compile cả app_package thành `.bytecode` trong **1 lần**,
`--validate` exit 0, `check_split` PASS, yaml < ~1.500 dòng, không file `.bak`.
Ghi lại size APK/IPA trước/sau (giá của việc giữ API public).

### P4 — Kết quả (2026-10-09)

**Gốc rễ thật của việc "build bytecode module phức tạp" bị tắc** (không phải
cách khai interface — generator cũ ĐÃ khai mức library):
1. Anchor thiếu library: phần Dart của plugin không nằm trên cây import của
   `main.dart` → module tự compile bản riêng → lỗi validate + "already
   loaded" lúc nạp. File pin viết tay chỉ vá vài package.
2. Danh sách library lấy bằng `strings anchor` → bắt cả URI chỉ là chuỗi
   (nhánh web của conditional import) → validator crash "not indexed".
3. `dynamically-callable` liệt kê từng class bằng regex → bắt nhầm class trong
   comment → crash "Container not found". Mỗi crash che toàn bộ lỗi phía sau.
4. Vòng augment sửa yaml SAU khi host đã build → iface lệch host.

Đã làm:
- **P4.1 pin tự động** — `tools/cmd/dyniface/gen_host_pin.py` →
  `app/lib/shell/host_packages.g.dart`: import 249 library public (bỏ 10 lib
  web) của 125 package host, trên cây import của `main.dart` (qua
  `dynmod_host_services.dart`). Xoá `dynmod_shared_libs_pin.dart`. Không lộ
  `win32/dbus/nm/posix/ffi/jni/objective_c` (binding FFI/desktop — chống phình).
- **P4.2 anchor** — `dyniface.sh bootstrap` LUÔN build lại (~10s);
  `dynpub release` gọi bootstrap ngay trước khi build host (đóng băng).
- **P4.3 interface** — `gen_dynamic_interface.py`: tập library tính bằng đi
  import theo nhánh VM từ `main.dart` (không dùng `strings`), lọc theo manifest
  P1; `dynamically-callable` = library-level cho `dart:core/async/collection/
  convert/math/typed_data`; entry private không sinh được nằm trong
  **`configs/abi/dynamic_interface.extra.yaml`** (trong repo, hiện 2 dòng:
  `_RequestConfig` của dio, `_RRectLike` của dart:ui). Bỏ carry-over từ yaml
  cũ và bỏ file `.bak` — iface tái lập 100% từ repo.
- **P4.4** không cần vá validator.
- **P4.5** generator FAIL nếu kernel host chứa package module.
- `dyniface.sh compile` = compile **1 lần, không augment** (lỗi = sửa module
  hoặc thêm extra.yaml + build lại host).
- Sửa ở nguồn s88-flutter (chưa commit):
  `lib/core/services/websocket/websocket_messages.dart` — bỏ
  `_DefaultDateTime implements DateTime` + `noSuchMethod` (hack const, trả
  `DateTime` cho MỌI getter → `timestamp.millisecondsSinceEpoch` crash), thay
  `timestamp ?? DateTime.now()`. Đã áp cùng thay đổi vào app_package hiện tại.

| | Trước | Sau |
|---|---|---|
| Compile module | augment loop nhiều vòng, không hội tụ | **1 lần, exit 0** |
| Interface | 8.311 dòng vá tay/tự động + `.bak` | 8.502 dòng sinh lại y hệt từ repo (56 package lộ) + file extra |
| `.bytecode` | 22,8MB (mang Dart của plugin) | **7,6MB** |
| `dynpub patch` (apply→compile→manifest) | — | **6,5 giây** |

**Giá dung lượng host (Android arm64, `libapp.so`):**

| Host | libapp.so | APK |
|---|---|---|
| Trước P4 | 39,4MB | 80,9MB |
| Lộ cả 125 package host | 88,1MB | 129,5MB |
| Lộ 56 package | 73,3MB | 114,8MB |
| **Lộ 71 package (+15 tiện ích: path, collection, rxdart, xml…) — hiện tại** | **78,5MB** | **120,0MB** |

Lộ = package module import TRỰC TIẾP (47, tự tính từ code module lúc đóng băng)
+ tầng t1 + `expose-packages:` trong `configs/abi/dynamic_interface.extra.yaml`
(`async`, `webview_flutter_platform_interface` + 15 package tiện ích lộ SẴN để
thêm thư viện thuần Dart vào module không phải build lại host — +5,2MB).
`check.sh` (bước app-package) báo sớm nếu module import package host CHƯA lộ. Đánh đổi: module sau này
dùng package host CHƯA lộ → compile báo lỗi → phải build lại host (thêm vào
`expose-packages`). +34MB còn lại là giá giữ TOÀN BỘ API public của
Flutter + 55 package cho module tương lai; thu nhỏ hơn nữa = lộ theo từng
member module đang dùng → mất tự do sửa module (ngược mục tiêu build-once).

**Bug cache build tìm ra kèm:** flutter/gradle KHÔNG coi NỘI DUNG file
`--dynamic-interface` là input (cùng đường dẫn) — đổi iface mà Dart không đổi
→ gradle 4–10s, `libapp.so` cũ giữ nguyên (host lệch iface, im lặng). Sửa:
`dynpub release` truyền `--dart-define=DYNMOD_IFACE_HASH=<sha256 iface>` (nằm
trong khoá cache) → buộc compile lại.

Cảnh báo còn lại: module vẫn có dynamic call (vd. `sb_http_manager.dart`) —
validator chỉ kiểm theo TÊN selector; đích là object host ngoài thư viện lõi
có thể lỗi lúc chạy → kiểm trên máy thật (P7).

**Quan trọng:** module compile theo hợp đồng v2 + anchor mới **chỉ chạy trên
host build mới**. Không deploy `dist/rs/app` hiện tại lên rs_domain đang phục
vụ host cũ (P5 sẽ gắn host_id để chặn tự động).

---

## P5 — Pipeline module gắn host_id

### P5 — Kết quả (2026-10-09) — KHÔNG chặn theo anchor (nhiều app, 1 bytecode)

Kiến trúc chốt: **nhiều app, mỗi app 1 `main_app` khác nhau, sau boot cùng nạp
1 bytecode.** Anchor = cả kernel host (gồm main_app) nên khác nhau giữa các
app dù module không phụ thuộc main_app → **không** chặn theo anchor:
- Gate không truyền `anchorHash` cho `DynModuleLoader` (cơ chế chặn có sẵn
  trong loader, không phải của Dart dyn_modules — VM chỉ kiểm định dạng
  bytecode, không kiểm host).
- `dynpub patch` gọi `dynpush patch --no-anchor-hash` → manifest
  `min_host_anchor: null`.
- `dynpub release` chỉ nhúng `--dart-define=DYNMOD_IFACE_HASH` (để phá cache
  build khi iface đổi) và in hash đó ra.

**Điều kiện để các app dùng chung 1 bytecode an toàn** (không có gì chặn lúc
chạy — lệch thì crash/"already loaded" khi nạp):
1. Cùng engine (`DYNMOD_REV`, cùng bộ `host_release_arm64`).
2. Cùng `dist/dynamic_interface.yaml` — `dynpub release` in `iface <hash>`;
   mọi app phải ra CÙNG hash.
3. Cùng version mọi package host mà module dùng (`app/pubspec.lock`) — `main_app`
   của từng app KHÔNG được kéo thêm dependency làm đổi version package dùng chung.
4. Cùng `content_kit` (hợp đồng v2).
Chỉ đổi UI / text / theme trong `main_app` → thoả cả 4.

**Tool kiểm (2026-10-09):** `tools/cmd/abicheck.sh` + `configs/abi/module_abi.json`
(ABI đóng băng: engine rev, sha256 iface, contract content_kit, version 128
package host — package path như content_kit tính bằng hash nội dung `lib/`;
bỏ vỏ host `main_app_package/loading_kit/dyn_loader`).
- `main-app <dir>`: resolve host với main_app đó trong thư mục TẠM (giữ
  `app/pubspec.lock`, không đụng app/) → so ABI; quét import main_app — kéo
  package MODULE vào host là FAIL ("already loaded"). `build_main_app.sh` tự gọi.
  Đã thử: main_app thật → OK; thêm `http '>=1.5.0 <1.6.0'` → FAIL http +
  flutter_cache_manager (bắc cầu); import `pinput` (module_allowed) → FAIL.
- `app-package [--accept]`: mọi ràng buộc version trong pubspec app_package +
  packages/* phải được version host đóng băng thoả (vi phạm = pub get host sẽ
  nâng → bytecode lệch host đã phát hành) + báo ràng buộc ĐỔI so với mốc
  `configs/abi/app_package_deps.json` (bắt AI tự nâng version). `modprep check`
  (→ `dynpub patch`, `setup`) tự gọi; vi phạm thì dừng patch. Đã thử: `dio
  ^5.12.0`, `gap ^3.0.2` → FAIL + liệt kê thay đổi.
- `host` / `snapshot`: `dynpub release` kiểm host vs ABI; chưa có → chụp; lệch
  → dừng, trừ `DYNMOD_ABI_ACCEPT=1` (cố ý đổi ABI → patch lại + build lại MỌI app).

## P6 — Vòng đời cập nhật trên máy

```
Mở app → load module ĐANG ÁP (đã verify) → hiển thị
       → nền: check manifest(host_id) → tải bản mới → sha256 + Ed25519
       → lưu "pending" → áp ở lần mở sau (hoặc popup restart nếu < min_force_update)
```

- **Rollback crash-loop:** đánh dấu "booting" trước khi load; module gọi
  `markHealthy()` sau first frame + vài giây. Nếu 2 lần mở liên tiếp không
  healthy → quay về bản trước → về module mồi (P4.7).
- `reportFatal` → gửi kèm `host_id + module version` lên Sentry.
- Lưu tối đa 2 bản (hiện tại + trước đó).

**Nghiệm thu P6:** test cố tình đẩy module throw lúc init → máy tự quay về bản
trước ở lần mở thứ 3, không cần cài lại.

### P6 — Kết quả (2026-10-09)

Đã có sẵn từ trước trong `dynmod_gate_impl.dart`: tải nền + áp ở lần mở sau,
popup theo `min_force_update`, fail-open, isolate "poisoned" sau lần nạp hỏng,
state 2 nguồn (file + prefs).

Thêm: `app/lib/shell/dynmod_health.dart` — mỗi lần nạp hash H tăng bộ đếm;
module gọi `markHealthy()` (template: first frame + 5s) → reset. **3** lần mở
liên tiếp không báo khoẻ → lần thứ 4 đánh dấu H hỏng: xoá cache, không nạp,
`checkAndPrefetch(accept:)` **không tải lại** đúng H → fail-open cho tới khi
server phát hash khác. Test: `app/test/dynmod_health_test.dart` (3 ca).

Khác bản nháp: **không giữ "bản trước"** (cache chỉ 1 file, 22MB) và **chưa có
module mồi trong host** (P4.7) → khi bản mới hỏng máy về màn demo (fail-open),
không về bản module cũ. Còn lại: nghiệm thu trên máy thật.

---

## P7 — E2E, đo đạc, đóng băng host v1

### Ma trận thay đổi phải hot được (không build host)

| # | Thay đổi trong app_package | Kỳ vọng |
|---|---|---|
| E1 | Sửa UI/text/màu | Hot OK |
| E2 | Sửa logic, provider, route mới | Hot OK |
| E3 | Thêm package pure-Dart mới (module_allowed) | Hot OK |
| E4 | Dùng thêm API của package t1 chưa từng dùng | Hot OK (library-level) |
| E5 | Subclass class host mới (vd. widget Flutter khác) | Hot OK nếu library ở extendable |
| E6 | Thêm asset mới | Hot OK qua CDN (P2.1) |
| E7 | Nâng version package t1 | **Bị chặn** lúc compile — đúng thiết kế |
| E8 | Thêm plugin native | **Bị chặn** — cần host release |

### Đo đạc

Load time module, first frame, scroll fps màn nặng, RSS, size APK/IPA host,
size `.bytecode`. So với bản AOT thường của app_package.

### Đóng băng

Checklist trước khi lên store host v1: P0–P6 PASS, E1–E6 PASS trên Android +
iOS máy thật, archive host_id đã backup, content_kit v2 không còn TODO.

---

### P7 — Kết quả đợt 1 (2026-10-09) — iPhone 16 Pro thật

Host IPA ad-hoc (engine ddm, anchor `871c8a99…`) + module v4 trên
`rs_domain = https://common-s88.sandboxg1.win/` (bundle `com.gamevee.th1`):
- `[DynmodGate] cache v4 OK → live ngay`, `module v4 loaded → live`,
  `[DynmodGate-bg] khong co ban moi`, `[DynmodHost] module v4 báo khoẻ`.
- 0 exception trong 80s sau khi mở (chưa đi qua màn socket/game/video).

Lỗi tìm ra + sửa: **Rive trên iOS không chạy** (`dlsym … 'init' /
'loadRiveFile' symbol not found`) — độc lập với dyn module. Plugin iOS đang
qua Swift Package Manager; bản SPM của `rive_native` link thư viện tĩnh
KHÔNG `-force_load` → hàm C cho FFI bị linker bỏ (`nm`: 0 symbol). Sửa:
`app/pubspec.yaml` → `flutter: config: enable-swift-package-manager: false`
(plugin qua CocoaPods, podspec rive có `-force_load`) + gỡ
`FlutterGeneratedPluginSwiftPackage` khỏi `ios/Runner.xcodeproj/project.pbxproj`
(Flutter không tự gỡ → "Missing package product"). Sau sửa:
`rive_native.framework` có `_init`, `_loadRiveFile`; 21 framework plugin; IPA
35,4MB.

Log iOS release: `print` của Dart vào syslog thiết bị (`flutter: …`), đọc bằng
`idevicesyslog` (đi kèm flutter: `bin/cache/artifacts/libimobiledevice`; cần
đặt binary trong `bin/` cạnh các dylib vì nó tìm `@loader_path/../`).

Còn lại: đi qua màn socket (isolate worker), game (webview/Cocos), video,
các luồng có dynamic call; Android máy thật (APK đã build); test rollback
(đẩy module cố tình throw).

## P8 — Vận hành sau khi phát hành host

- **Được làm bằng module:** mọi thứ E1–E6.
- **Bắt buộc host release mới:** E7, E8, nâng Flutter/engine, store bắt nâng
  target SDK, đổi content_kit, đổi quyền native.
- Server giữ ma trận `host_id ↔ module`; host cũ vẫn nhận module compile riêng
  cho nó cho tới khi tỉ lệ người dùng đủ thấp.
- CI cho mỗi PR của app_package: compile module với host_id đang chạy →
  validate + check_split + P2.4 → báo ngay nếu PR đòi host mới.

## Rủi ro chính

| Rủi ro | Giảm thiểu |
|---|---|
| Isolate không chạy hàm module (S1) | Worker ở host + giao thức Map |
| Hiệu năng interpreter không đủ | Đẩy package nóng vào t1; màn nặng giữ ở webview/Cocos |
| Size host phình do giữ API public | Đo ở P4; thu hẹp extendable/can-be-overridden |
| dyn_modules experimental, API đổi | Pin engine rev, archive toolchain theo host_id |
| Mất archive host | Backup ngoài máy, kiểm ở P5 |
| Module hỏng làm app không vào được | Rollback P6 + module mồi P4.7 |
