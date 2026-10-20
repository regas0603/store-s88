# TỐC ĐỘ: interpreted vs native trong app Flutter thật (iPhone + Android)

> Đo 2026-10-01. Cùng một module `bench.bytecode` (2067 B), cùng thân hàm ở hai phía
> (native AOT trong app ↔ interpreted trong module). Mỗi số = median qua các reps (đã warm-up),
> lấy median của 3 lần chạy độc lập. Raw: `../dart-sdk-build/bench_module/*_run*.txt`.
>
> **Phát hiện chính:** ngoài slowdown vốn có của interpreter (~10–16× với code tính toán thuần),
> bản Dart hiện tại có **lỗi hiệu năng riêng trên Android**: interpreter dùng `setjmp` lưu
> signal mask → **một syscall `sigprocmask` mỗi lần chuyển interpreter↔runtime/native**.
> Áp lựa chọn `_setjmp` mà Dart đã dùng trên Apple → workload nhiều chuyển tiếp nhanh lên **3–4.5×**.

## 1. Phương pháp

- Host: `sample_app/lib/bench_main.dart`; workload: `lib/bench/workloads.dart`; module
  `modules/bench.dart` **sinh tự động** từ workloads.dart (thân hàm giống hệt, đã `diff`).
  Module phải *chép* thân hàm, không import, nếu không nó sẽ gọi lại code native của host.
- Cả hai nhánh đều gọi qua `Operation.apply`, nên chi phí gọi như nhau, chỉ khác phần thân
  chạy native hay interpreted.
- Workload: `arith` 20M vòng, `fib(32)`, `alloc` 3M list, `map` 1M thao tác Map, `str` 1M
  lần `StringBuffer.write`, `xcall` = host gọi 1M lần một hàm thân rỗng trong module.
  `arith`/`fib`/`alloc` giống hệt bench CLI trước đây, nên so sánh được.
- Build release (AOT, product). Bench chạy 2 s sau frame đầu để không đo lẫn phần khởi động.
- Thiết bị: **iPhone 16 Pro, iOS 26.2** (ký Development, không JIT entitlement);
  **Android emulator** API 35 arm64 (Apple Silicon, 4 vCPU). Chưa có máy Android thật.

## 2. Kết quả

**Slowdown (interp/native), median 3 lần chạy:**

| Workload | CLI macOS (cũ) | **iPhone 16 Pro** | Android emu (engine gốc) | Android emu (**vá `_setjmp`**) |
|---|---|---|---|---|
| arith | 13.1× | **13.0×** | 16.0× | 16.5× |
| fib | 10.8× | **10.5×** | 13.4× | 13.3× |
| alloc | 63.7× | **63.2×** | 411× | 93× |
| map | – | **6.0×** | 30.0× | 9.8× |
| str | – | **3.0×** | 12.5× | 3.4× |
| xcall (ns/lần gọi) | – | **107 ns** (native 1.9) | 486 ns | 131 ns |

**Thời gian interpreted tuyệt đối (ms), để thấy tác dụng của bản vá:**

| Workload | iPhone | Android gốc | Android vá | Vá nhanh hơn |
|---|---|---|---|---|
| arith | 322 | 378 | 383 | 1.0× (không đổi) |
| fib | 115 | 124 | 123 | 1.0× (không đổi) |
| alloc | 283 | 1750 | 393 | **4.5×** |
| map | 77 | 359 | 120 | **3.0×** |
| str | 74 | 323 | 88 | **3.7×** |
| xcall (1M) | 107 | 486 | 131 | **3.7×** |

Thời gian nạp module (gắn bytecode và gọi entry-point đăng ký 6 op): iPhone khoảng 2–4 ms ở lần
đầu; module 903 B thì khoảng 65 µs (`dyn_modules_ios_result.md`).

## 3. Diễn giải

1. **Code tính toán thuần (`arith`, `fib`) chậm khoảng 10–16×** và ổn định giữa các nền tảng:
   iPhone trùng gần như tuyệt đối với CLI macOS (13.0 so với 13.1, 10.5 so với 10.8). Đây là
   chi phí bản chất của việc thông dịch từng lệnh bytecode.
2. **Code gọi nhiều vào thư viện lõi chậm ít hơn hẳn: `str` khoảng 3×, `map` khoảng 6×.** Lý do
   là `StringBuffer` và `Map` của `dart:core` vẫn chạy **native** kể cả khi caller là bytecode.
   Interpreter chỉ điều phối, còn việc nặng do mã AOT làm. Code-push thực tế (logic nghiệp vụ,
   format, gọi API framework) gần với trường hợp này hơn là với `arith`.
3. **`alloc` khoảng 63× bị phóng đại bởi native.** Bản native chỉ mất khoảng 1.4 ns/vòng, nhiều
   khả năng AOT đã khử cấp phát (allocation sinking / escape analysis) với list cục bộ không
   thoát ra ngoài, trong khi interpreter cấp phát thật. Vì vậy con số này đo "cấp phát thật so
   với không cấp phát" chứ không thuần là tốc độ interpreter. *(Cần kiểm chứng bằng biến thể
   cho list thoát ra ngoài, ghi vào hướng mở.)*
4. **Mỗi lần host gọi vào module tốn khoảng 107 ns trên iPhone** (native là 1.9 ns). Không đáng
   kể với vài lần gọi, nhưng đáng kể nếu module nằm trên đường nóng (vd. `build()` của widget
   gọi mỗi frame với hàng nghìn phần tử). Khuyến nghị thiết kế: đặt **ranh giới module ở mức
   thô** (một lời gọi làm nhiều việc), tránh callback mịn.

## 4. Phát hiện: lỗi hiệu năng của interpreter trên Android

**Triệu chứng:** trên Android, `arith`/`fib` ngang iPhone, nhưng mọi workload có nhiều
lần chuyển interpreter↔runtime chậm thêm 4–6×. Tăng emulator từ 1 lên 4 vCPU không thay đổi gì,
nên nguyên nhân không nằm ở GC hay song song.

**Profile** (`simpleperf record --app`, app khai báo `<profileable android:shell="true"/>`,
symbol từ `libflutter.so` chưa strip; `bench_module/perf_report_baseline.txt`):

| Hàm | % mẫu CPU |
|---|---|
| `[kernel]` (chủ yếu xử lý syscall) | ~33% |
| `libc __rt_sigprocmask` | **19.3%** |
| `dart::Interpreter::Run` (chạy bytecode thật) | 18.7% |
| `__emutls_get_address` + `pthread_getspecific` | ~3.6% |
| `sigsetjmp` + `art::__sigprocmask` | ~3% |

→ Thời gian dành cho syscall `sigprocmask` **lớn hơn** thời gian chạy bytecode.

**Nguyên nhân trong mã nguồn** (Dart `0e7642b8`):
- `runtime/platform/globals.h:321`:
  ```c
  #if defined(__APPLE__)
  // Avoid expensive saving of sigmask in setjmp/longjmp ...
  #define DART_SETJMP _setjmp
  #else
  #define DART_SETJMP setjmp      // bionic: lưu signal mask = syscall
  ```
- `runtime/vm/interpreter.cc:697, 714, 789`: `InvokeRuntime`, `InvokeNative` và đường gọi sang
  mã compiled đều `DART_SETJMP` **mỗi lần** được gọi. Mỗi lần cấp phát qua runtime, gọi native
  hay gọi vào hàm AOT (vd. `List.[]`, `Map.[]=`) từ bytecode đều tốn một syscall.
- iOS/macOS đã tránh được nhờ `_setjmp`. Android/Linux thì chưa.

**Thí nghiệm kiểm chứng:** vá cục bộ `interpreter.cc` (`bench_module/interpreter_sjfix.diff`),
chỉ đổi cặp setjmp/longjmp của interpreter sang `_setjmp/_longjmp` trên Android. Build ra
`out/android_release_arm64_sjfix`, rồi đã hoàn nguyên source. Kết quả ở bảng mục 2: các workload
có chuyển tiếp nhanh lên 3–4.5×, các workload thuần không đổi. Đây đúng là dấu hiệu của một
nguyên nhân duy nhất.

**Phần chênh còn lại so với iPhone** (vd. `map` 9.8× so với 6.0×, `xcall` 131 so với 107 ns) có
thể do **emulated TLS**: trên Android, `OSThread::current_vm_thread_` (dùng cho
`Thread::Current()`) đi qua `__emutls_get_address` (`strings libflutter.so | grep emutls`), và
cũng có thể do emulator. Cần máy Android thật để tách bạch.

**Lưu ý:**
- Đây là thí nghiệm, **chưa phải bản sửa đã được review**. Cần upstream xác nhận rằng không có
  đường longjmp nào của interpreter phụ thuộc vào signal mask. Apple đã dùng `_setjmp` cho cùng
  mã này, nên lựa chọn này về nguyên tắc đã được chấp nhận.
- Số đo Android là trên emulator. Syscall trong máy ảo đắt hơn máy thật, nên mức phạt trên máy
  thật có thể nhỏ hơn, nhưng cơ chế (một syscall mỗi lần chuyển) vẫn như vậy.
- Đây là đóng góp có thể báo lên Dart SDK (issue kèm profile và diff).

## 5. Kiểm hash module (đã thêm)

App (`lib/main.dart`) so sha256 của bytes tải về với `hash` mà `patches/check` trả về, và
**từ chối nạp** nếu lệch. Đã kiểm trên Android:
- Module đúng: nạp OK (`evidence/sha256_ok.txt`).
- Server trả module bị thêm 1 byte: `POC_ERROR Bad state: hash mismatch: c704…3f8c != f01b…27be`,
  không nạp (`evidence/sha256_tampered.txt`).

Hash chỉ chống hỏng hoặc sửa *trên đường truyền*. Chống server bị chiếm thì cần chữ ký
(`hash_signature`), là hướng tiếp.

## 6. Hướng tiếp
- Lặp lại trên **máy Android thật** (cả engine gốc lẫn bản vá).
- Biến thể `alloc` cho list thoát ra ngoài, để đo chi phí cấp phát của interpreter không bị allocation sinking làm méo.
- Đo emulated TLS: thử build engine với `-fno-emulated-tls` (API ≥ 29) để tách phần chênh còn lại.
- Soạn issue upstream cho Dart SDK.
