# Đề cương đồ án tốt nghiệp

**Đề tài (đề xuất):** *Đánh giá cơ chế Dart Dynamic Modules như nền tảng code-push
self-host cho ứng dụng Flutter: kiến trúc, hiệu năng và ràng buộc triển khai.*

> Bản đồ cương này bám vào phần đã làm được thực nghiệm (xem `dyn_modules_poc_guide.md`,
> `dyn_modules_research.md`). Mỗi chương ghi rõ **đầu vào đã có** vs **việc cần làm thêm**.

---

## Chương 1 — Mở đầu

- **1.1 Bối cảnh.** Ứng dụng mobile cần vá lỗi/cập nhật nhanh mà không phải rebuild
  và phân phối lại toàn bộ app. Code-push (OTA) rút ngắn vòng lặp.
- **1.2 Vấn đề.** Flutter compile **AOT ra machine code** → không patch trực tiếp được
  như JS (CodePush). Giải pháp thương mại (Shorebird) đóng phần lõi (dart-sdk fork
  private).
- **1.3 Câu hỏi nghiên cứu.**
  - RQ1: Cơ chế **dynamic modules** chính chủ của Dart có đủ làm nền code-push
    self-host cho Flutter không?
  - RQ2: Overhead (thời gian nạp, tốc độ chạy interpreted vs native, kích thước
    module) là bao nhiêu?
  - RQ3: Mô hình bảo mật/capability (dynamic interface) khác Shorebird ra sao?
  - RQ4: Ràng buộc triển khai thực tế (iOS code-signing, FFI, versioning) là gì?
- **1.4 Đóng góp.**
  - (i) PoC self-host code-push dựng **hoàn toàn từ nguồn public** (đã chạy được).
  - (ii) Phân tích so sánh dyn_modules ↔ Shorebird ↔ CodePush.
  - (iii) Đo lường overhead thực nghiệm.
  - (iv) Phân tích ranh giới triển khai iOS.
- **1.5 Phạm vi & giới hạn.** Thí nghiệm trên **Android + iOS** (2 nền tảng mục tiêu
  nghiên cứu). Thực nghiệm: **Android** release ddm trên emulator ✅
  và **iOS thiết bị thật** (iPhone 16 Pro, ký ad hoc) ✅. macOS chỉ là **máy build +
  engine `host`** (bộ công cụ biên dịch module) và là nơi chạy PoC CLI; **không phải
  target của app**.

## Chương 2 — Nền tảng & Công trình liên quan

- **2.1 Ba chế độ thực thi Dart:** JIT, AOT, và bytecode interpreter (KBC) đã bị gỡ.
- **2.2 AOT snapshot & tính bất biến:** vì sao không patch trực tiếp; serializer
  versioning (minh hoạ crash `TypeDeserializationCluster::ReadFill`).
- **2.3 Lịch sử KBC → gỡ → dyn_modules** *(đầu vào đã có: commit thật)*:
  - Gỡ: `7588ed86dee` (alexmarkov, 2020-10-28, Gerrit CL 169147).
  - Tái sinh: `8fbca8ba673` (alexmarkov, 2024-08-15).
  - KBC gốc: `41fcbd097ce` (~2018).
- **2.4 Related work:**
  - Shorebird (đóng) — interpreter iOS + bipatch AOT Android.
  - Microsoft CodePush / React Native — bytecode JS nên dễ.
  - Flutter deferred components — split AOT lib (khác mục tiêu).
  - Native dynamic linking (.so/.dll) — analogy issue #50406.

## Chương 3 — Kiến trúc Dynamic Modules

*(đầu vào đã có: `pkg/dynamic_modules/README.md`, đọc source)*
- **3.1 Ba thành phần:** Host / Dynamic Interface / Module.
- **3.2 Nguyên tắc additive-only** (không đè khai báo cũ) — hệ quả thiết kế.
- **3.3 Chuỗi công cụ:** `dart2bytecode`, `dartaotruntime` (+ interpreter), gen_kernel,
  gen_snapshot.
- **3.4 Dynamic interface** (`dynamic_interface.yaml`): callable / extendable /
  can-be-overridden / can-be-used-as-type / dynamically-callable → **capability model**.
- **3.5 Cơ chế dispatch host↔module** *(ĐÃ GIẢI MÃ → `dyn_modules_dispatch_mechanism.md`)*:
  entry-point hàm module = `InterpretCall` stub (`object.cc:8154`), không rẽ nhánh tại
  call-site; chiều ngược `Interpreter::InvokeCompiled`; `@pragma('dyn-module:entry-point')`
  sống sót TFA (issue #63377). Nguồn: commit `8fbca8ba673`, verify trên HEAD.
- **3.6 Provenance & validation:** chống ABI skew (bytecode không có ABI ổn định).

## Chương 4 — Thiết kế hệ thống code-push self-host

- **4.1 Kiến trúc tổng thể:** app Flutter (host) ↔ server phân phối module ↔ CDN.
- **4.2 Luồng nạp:** boot → check update → tải `.bytecode` qua HTTPS →
  `loadModuleFromUri`/`loadModuleFromBytes` → chạy interpreter.
- **4.3 Ánh xạ sang server có sẵn** trong repo (`server/`): endpoint check + tải
  artifact. *(hiện thực ở phần B)*.
- **4.4 Versioning & tương thích:** pin SDK commit + provenance; chiến lược khi host
  đổi version.
- **4.5 Bảo mật:** ký module, TLS, kiểm provenance; thảo luận "no sandbox / shared heap".

## Chương 5 — Hiện thực (PoC)

*(đầu vào đã có: PoC calculator chạy được)*
- **5.1 Môi trường (2 thí nghiệm, 2 commit — ghi cả hai):**
  - PoC CLI + benchmark: Dart SDK `53b0a522`, `tools/build.py --dart-dynamic-modules`,
    output `xcodebuild/ReleaseARM64`, macOS ARM64.
  - E2E Flutter: Flutter monorepo `1be6586f` (Dart `0e7642b8`), engine
    `dart_dynamic_modules=true` (`host_release_arm64`; Android `android_release_arm64`).
- **5.2 Pipeline build:** host 2 lần (no-aot anchor + aot) → snapshot → dart2bytecode.
- **5.3 Nạp runtime + kết quả:** transcript calculator (load basic/exponent/trig).
- **5.4 Gotcha code-signing macOS:** SIGKILL + fix entitlement JIT — bắc cầu sang
  phân tích iOS (Chương 7).
- **5.5 Mở rộng nạp qua mạng** *(phần B)*.

## Chương 6 — Đánh giá thực nghiệm

**Số liệu đã có (macOS ARM64, median, warm-up):**
- Slowdown theo workload (`run_bench.sh`): số học **13.1×**, gọi hàm **10.8×**,
  cấp phát **63.7×** → *không đồng đều*, cấp phát đắt nhất.
- Module bench **1376 B**, thời gian nạp **54 µs** (`run_bench.sh`); module calculator 2.2–3.1 KB;
  module Flutter `power.bytecode` 903 B. *(Số cũ "~1.9 KB / ~70 µs" ở bản trước là lần đo sớm,
  đã thay bằng số từ `run_bench.sh` — cần đo lại N≥10 trên máy rảnh trước khi chốt.)*
- App-size bloat (`run_bloat.sh`): 1.83MB → 4.39MB (**+140%**, do giữ dart:core+math).
- → diễn giải: `dyn_modules_defense_qa.md` mục C.

**Số liệu trên app Flutter thật (2026-10-01) → `dyn_modules_speed_result.md`:**
- iPhone 16 Pro: arith 13.0×, fib 10.5×, alloc 63.2×, map 6.0×, str 3.0×, xcall 107 ns/lần
  → khớp CLI macOS; code gọi nhiều vào dart:core chậm ít (3–6×).
- **Phát hiện:** interpreter trên Android dùng `setjmp` lưu signal mask (Apple dùng
  `_setjmp`) → syscall `sigprocmask` mỗi lần chuyển interpreter↔runtime; vá thử → nhanh 3–4.5×.
  Bằng chứng simpleperf + thí nghiệm vá. Đáng thành 1 mục riêng (6.x) + issue upstream.

**Phương pháp đo (thiết kế cụ thể):**
- **6.1 Kích thước module:** so `.bytecode` vs source vs (giả định) patch AOT.
  *(đã có: basic 2200B, exponent 3151B, trigonometry 2374B)*.
- **6.2 Thời gian nạp module:** đo `loadModuleFromBytes` (wall-clock, N=100, median +
  p95). Biến thiên theo kích thước module.
- **6.3 Tốc độ thực thi interpreted vs native:** microbenchmark cùng một hàm (vd vòng
  lặp số học, đệ quy) chạy (a) built-in AOT vs (b) trong dynamic module. Báo cáo tỉ số
  slowdown. Chú ý warm-up.
- **6.4 App size bloat:** so host build thường vs host build dyn_modules (tắt
  tree-shaking) — đo kích thước snapshot.
- **6.5 Bộ nhớ:** RSS trước/sau nạp module.
- **Công cụ:** `Stopwatch` trong Dart cho (6.2/6.3); `ls -l`/`size` cho snapshot;
  `/usr/bin/time -l` cho RSS. Mỗi số chạy ≥10 lần, báo median + độ lệch.

## Chương 7 — Ràng buộc triển khai

- **7.1 iOS code-signing:** interpreter không exec code tải về (khác `Dart_LoadELF`
  PROT_EXEC), không cần JIT entitlement; nhưng gotcha macOS §5.4 cho thấy
  ngay cả code động nội bộ cũng đụng ký. Phân tích: vì sao macOS ký được, iOS không.
- **7.2 Giới hạn hiện tại:** chưa FFI từ module; provenance chưa đủ; không web backend.

## Chương 8 — Kết luận & Hướng phát triển

- Tóm tắt trả lời RQ1–RQ4.
- Hướng mở: ghép interpreter vào Flutter engine (mobile), versioning production, ký số
  module, so sánh định lượng với bipatch AOT.

---

## Phụ lục (đã có sẵn để đưa vào)
- A. Lệnh build + pipeline đầy đủ → `dyn_modules_poc_guide.md`.
- B. Timeline commit + khảo cổ git → `dyn_modules_research.md` §1.
- C. Transcript PoC calculator.
- D. `dynamic_interface.yaml` mẫu + module mẫu.

## Việc cần làm thêm (checklist thực nghiệm)
- [x] Viết microbenchmark interpreted-vs-native (Chương 6.3) — `run_bench.sh`.
- [x] Đo thời gian nạp (6.2) — 54 µs; [ ] lặp N≥10 lấy median + p95 trên máy rảnh.
- [x] Build host 2 kiểu để đo bloat (6.4) — `run_bloat.sh`, +140%.
- [x] PoC nạp qua mạng (phần B, CLI) — `run_poc_net.sh`.
- [x] Đọc commit `8fbca8ba673` cho §3.5 → `dyn_modules_dispatch_mechanism.md`.
- [x] App Flutter thật nạp module (macOS) → `dyn_modules_flutter_e2e_result.md`.
- [x] Engine ddm Android + app Flutter Android nạp module qua server self-host
      → `dyn_modules_android_result.md` (emulator; đối chứng âm OK).
- [x] Android: thời gian nạp (~177 µs median), kích thước APK (+24%, libapp +55%).
- [x] Slowdown interpreter trên iPhone + Android emu (6 workload) + tìm ra lỗi setjmp Android.
- [x] Kiểm sha256 module trong app (đúng → nạp; sửa 1 byte → từ chối).
- [ ] Android máy thật (gốc + vá); biến thể alloc không bị allocation sinking; thử -fno-emulated-tls.
- [ ] Soạn issue upstream Dart SDK về setjmp trên Android.
- [x] iOS máy thật (iPhone 16 Pro, iOS 26.2): chạy được cả chữ ký Development và **ad hoc**
      (`get-task-allow=false`), không JIT entitlement → `dyn_modules_ios_result.md` (RQ4 kỹ thuật).
- [ ] iOS: tải module qua HTTPS (không tắt ATS) + chữ ký module.
