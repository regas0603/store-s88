# Ghép Dynamic Modules vào Flutter engine + nối CLI có sẵn — feasibility & kế hoạch

> **Cập nhật 2026-10-01:** Ẩn số 1 ĐÃ GIẢI QUYẾT — bỏ fork Shorebird, dùng Flutter upstream
> `1be6586f` (Dart `0e7642b8`) có interpreter; engine `host_release_arm64` ddm build OK.
> GĐ1+GĐ3 Android: ✅ xong (`dyn_modules_android_result.md`). GĐ2: không cần vá flutter_tools (Cách A).
> GĐ4 iOS thiết bị thật: ✅ xong (`dyn_modules_ios_result.md`).
>
> ⚠️ **Phạm vi app: chỉ Android + iOS.** Các lần chạy E2E trên **macOS desktop**
> trong `dyn_modules_flutter_e2e_result.md` là thí nghiệm chứng minh khả thi
> (chạy nhanh nhất, không cần ký), **không phải target sản phẩm** — dự án
> này không build/shapp macOS. Engine `host` vẫn build trên macOS vì vai trò
> **công cụ build** (dartaotruntime/dart2bytecode + `--local-engine-host`).

> Trả lời câu: *"Ghép interpreter vào Flutter engine để chạy app thật thì sao? Gắn vào
> CLI có sẵn được không?"* — dựa trên khảo sát chính `shorebird-engine/` + `tools/` trong repo.

## Kết luận ngắn

**Khả thi hơn hẳn kết luận bi quan của tài liệu gốc** — vì phần khó nhất (engine hỗ trợ
interpreter) **upstream Flutter đã làm sẵn**, và repo của bạn đã có đủ hạ tầng engine-surgery.

- ✅ Engine build đã có cờ `dart_dynamic_modules` (`engine/src/flutter/tools/gn:685`).
- ✅ Có CI builder chính thức: **Android release** (`ci/android_release_arm64_ddm`),
  **iOS release** (`ci/ios_release_ddm`, build `flutter_framework`+`generate_snapshot_bins`),
  host, simulator.
- ✅ Repo bạn đã có `tools/build_engine.sh` (gn gen + ninja) + cơ chế patch flutter_tools
  (`patch_flutter_tools_no_linker.sh`) + upload artifact (`publish.sh`) + self-host server.
- ⚠️ **Khoảng trống chính:** `flutter_tools` CHƯA có plumbing dynamic modules (grep rỗng)
  → phải tự vá để `flutter build` chạy pipeline dyn_modules (2 pha kernel + dynamic-interface).
- ✅ ~~**Ẩn số 1:**~~ *(đã giải quyết — xem cập nhật đầu file)* Dart engine đang pin (`db98bdaa`) có compile interpreter không — chỉ khi
  build với `dart_dynamic_modules=true`. Engine binaries hiện tại của bạn (build không cờ này)
  **chưa** có interpreter → cần build engine MỚI.
- ⚠️ **Ẩn số 2 (iOS thiết bị thật):** engine iOS release ddm *build được*, nhưng việc nạp
  bytecode lúc chạy có qua được code-signing trên máy thật hay không
  **chưa kiểm chứng**. Interpreter (không exec code tải về) được thiết kế để qua — hứa hẹn
  hơn hướng `Dart_LoadELF`+PROT_EXEC (ngõ cụt cũ), nhưng đây đúng là **câu hỏi nghiên cứu**.

## Kiến trúc: cần gì để app Flutter thật chạy dynamic modules

```
[1] Engine build với dart_dynamic_modules=true   → interpreter nằm trong libflutter/framework
[2] App (host) compile:  kernel no-aot (anchor) + aot + --dynamic-interface  → app snapshot
[3] flutter_tools drive [2]  (← đang THIẾU, phải vá)
[4] Module: dart2bytecode → .bytecode  → upload self-host server
[5] App runtime: loadModuleFromUri(<server>/...) sau boot  → interpreter chạy
```

So với PoC CLI đã chạy: [4][5] **giống hệt** cái đã verify; [1] là build mới; [2][3] là
phần tooling mới.

## Kế hoạch nối vào CLI có sẵn (theo giai đoạn)

> ⚠️ **QUAN TRỌNG cho đồ án public:** `shorebird-engine/DEPS` trỏ Dart về **fork private
> của Shorebird** (`dart_sdk_git = shorebirdtech/dart-sdk`, `db98bdaa`). Để đồ án tái lập
> được từ nguồn công khai, **KHÔNG build trên fork đó** — dùng **Flutter engine upstream**
> tại revision có Dart upstream hỗ trợ dyn_modules (các builder `*_ddm.json` là bằng chứng
> upstream hỗ trợ). Hạ tầng `build_engine.sh` tái dụng được, nhưng trỏ DEPS về upstream.
> Như vậy toàn bộ chuỗi vẫn 100% public, đúng tinh thần đề tài.

### Giai đoạn 1 — Build engine ddm (Android release trước)
- Thêm target vào `tools/build_engine.sh`: gn với `--gn-args=dart_dynamic_modules=true`,
  `--runtime-mode release --android --android-cpu arm64` (giống `android_release_arm64_ddm`).
- Ninja: `flutter/lib/snapshot:generate_snapshot_bins` + engine libs.
- Chi phí: sync ~1-2h (nếu chưa), build android ~1-2h, disk ≥150GB (theo cảnh báo trong
  build_engine.sh). Nên tmux/nohup.
- **Kiểm chứng ẩn số 1 tại đây**: nếu build ra `gen_snapshot` + `dart2bytecode` có
  dynamic modules → Dart pin đã hỗ trợ. (Nếu không → phải bump Dart, việc lớn.)

### Giai đoạn 2 — Vá flutter_tools cho pipeline dyn_modules
- Thêm patch (cạnh `patch_flutter_tools_no_linker.sh`) để `flutter build` (hoặc lệnh
  con mới) chạy: gen_kernel 2 pha (no-aot anchor + aot) + truyền `--dynamic-interface`.
- Tham chiếu chính xác các cờ: xem `dyn_modules_poc_guide.md` §2 (đã verify với gen_kernel/
  gen_snapshot/dart2bytecode).
- Đây là phần engineering chính; Shorebird cũng làm đúng kiểu vá flutter_tools này.

### Giai đoạn 3 — Nối publish/self-host + app
- `publish.sh`/`sb.sh`: thêm mode `dyn-module` — compile code đã đổi bằng `dart2bytecode`
  → upload lên server (`POST /uploads/patch/:id`, đã có).
- App: trong `loading_kit`/coordinator, SAU boot gọi `loadModuleFromUri(<base_url>/...)`.
  (loading_kit đã có sẵn kỷ luật chỉ gọi mạng sau boot → hợp.)

### Giai đoạn 4 (nghiên cứu) — iOS thiết bị thật
> ✅ 2026-10-01: chạy được trên iPhone 16 Pro (iOS 26.2), ký ad hoc, không JIT entitlement
> → `dyn_modules_ios_result.md`.
- Build `ci/ios_release_ddm`, đóng `Flutter.xcframework`, thử nạp module trên máy thật.
- Đo: có bị code-signing chặn không (khác gotcha macOS đã gặp — iOS không tự ký được).
- Trả lời RQ4 (code-signing trên thiết bị thật). **Đây là đóng góp mới nếu làm được** — vượt
  kết luận "iOS = ngõ cụt" của tài liệu gốc.

## Rủi ro & ẩn số (nêu trung thực trong thesis)
1. ~~Dart pin có interpreter hay không~~ — đã giải quyết bằng upstream `1be6586f`.
2. flutter_tools plumbing chưa có → tự vá, có thể vênh theo version Flutter.
3. iOS device: engine build được ≠ chạy được trên máy thật — chưa verify.
4. dynamic modules là **experimental** (Dart tự ghi) → API `loadModuleFromBytes` "about to
   be removed" thay bằng API cần provenance; pin version chặt.
5. App-size bloat (+140% ở PoC nhỏ) áp lên cả engine ddm.

## Trả lời gọn 2 câu hỏi
- **"Ghép vào engine để chạy app thật?"** — Được về mặt build (Android release + iOS
  release ddm là target chính thức). Cần build engine mới + vá flutter_tools.
- **"Gắn vào CLI có sẵn?"** — Đúng chỗ để làm: repo bạn đã có build_engine.sh + patch
  flutter_tools + publish + server. Thêm 1 target engine + 1 patch flutter_tools + 1 mode
  publish là khớp kiến trúc hiện tại. Android khả thi rõ; iOS thiết bị thật là phần nghiên cứu.

## Con trỏ
- **Tool tự động hoá toàn chuỗi (upstream):** `tools/cmd/dynmod.sh` — `check | sync | engine <host|android|ios|all> [--patch-setjmp] | app <android|ios> | module <file> | status`.
  `engine host` = công cụ build (compile module + `--local-engine-host`), không phải target app.
- Cờ engine: `shorebird-engine/engine/src/flutter/tools/gn:685`
- Builder ddm: `.../ci/builders/{linux_android_aot,mac_ios,linux_host}_engine_ddm.json`
- Pipeline compile app/module: `dyn_modules_poc_guide.md`
- CLI hiện có: `tools/{build_engine,publish,sb,patch_flutter_tools_no_linker}.sh`
