# Ôn vấn đáp — Đồ án Dynamic Modules code-push

> ~25 câu hội đồng hay hỏi, kèm câu trả lời ngắn + bằng chứng/con trỏ file. Số liệu từ
> thực nghiệm trên máy (macOS ARM64, Dart SDK `53b0a522…`). Con số **1 máy, 1 workload**
> — nói rõ điều này khi trình bày (tính khiêm tốn khoa học).

## Pitch 30 giây
> "Flutter compile AOT ra machine code nên không cập nhật nóng được như JavaScript.
> Shorebird giải quyết bằng interpreter nhưng đóng phần lõi (dart-sdk fork private).
> Đồ án dựng lại cơ chế đó **hoàn toàn từ nguồn chính chủ public** — tính năng *dynamic
> modules* của Dart — chạy được PoC code-push self-host qua mạng, đo được cái giá hiệu
> năng (13.4× cho vòng lặp số học), và phân tích vì sao iOS là rào khó nhất."

---

## A. Nền tảng (chắc chắn bị hỏi)

**Q1. Vì sao code Flutter release không patch trực tiếp được?**
Release = **AOT snapshot** (machine code + dữ liệu VM bất biến). Không có bytecode để
sửa; muốn thay code phải sinh lại snapshot. Thêm nữa serializer của snapshot gắn chặt
version VM — lệch version là crash khi đọc (`TypeDeserializationCluster::ReadFill`).

**Q2. Vậy giải pháp chung là gì?**
Cho VM chạy được code **chưa** AOT-compile: biểu diễn code mới ở dạng portable (**KBC —
Kernel ByteCode**) và chạy bằng **interpreter**, trong khi code cũ vẫn chạy AOT native.

**Q3. Dynamic modules là gì?**
Cơ chế chính chủ của Dart cho phép app (host) **nạp thêm** code Dart lúc chạy, dạng
bytecode chạy interpreter. Ba phần: **Host** (AOT, khai báo API lộ ra) + **Dynamic
Interface** (bề mặt API cho module) + **Module** (bytecode nạp sau). Nguồn:
`pkg/dynamic_modules/README.md`.

**Q4. (Câu ăn điểm) VM quyết định chạy interpreter hay native tại mỗi lời gọi thế nào?**
**Không rẽ nhánh tại call-site.** Khi nạp module, mỗi hàm được `AttachBytecode` và
**entry-point của nó bị đặt = `InterpretCall` stub** (`object.cc:8154`). Caller AOT gọi
theo calling convention thường → tự nhảy vào stub → vào `Interpreter::Call` chạy bytecode.
Chiều ngược (module gọi API host) qua `Interpreter::InvokeCompiled`. Do đó code native
**không mất một lệnh kiểm tra nào**. Chi tiết: `dyn_modules_dispatch_mechanism.md`.

**Q5. KBC bytecode khác gì AOT?**
KBC = lệnh trung gian, kiến trúc-độc lập, chạy bằng vòng lặp interpreter
(`interpreter.cc`). AOT = machine code cho CPU cụ thể. KBC portable + patch được nhưng
chậm hơn.

---

## B. Kiến trúc & thiết kế

**Q6. "Additive-only" nghĩa là gì và vì sao quan trọng?**
Module chỉ **thêm** khai báo mới, **không đè** khai báo có sẵn của host. Giữ được tính
toàn vẹn của host, tránh module phá code cũ. Khác Shorebird (patch *đè* hàm để fix bug).

**Q7. Dynamic interface để làm gì?**
File `dynamic_interface.yaml` khai báo module được **gọi/kế thừa/override/dùng-làm-kiểu**
những gì (capability model). Vi phạm → lỗi **compile-time** (khi `dart2bytecode --validate`),
không phải runtime. Đây là bề mặt an toàn tường minh mà Shorebird không có công khai.

**Q8. Provenance là gì?**
Metadata gắn vào bytecode (version tool, input) để chứng minh module tương thích host,
vì *"bytecode không có ABI ổn định"*. (Lưu ý trung thực: **chưa hiện thực đầy đủ** trong
package hiện tại — README ghi rõ.)

**Q9. Mô hình bảo mật? Có sandbox không?**
**Không sandbox.** Module chạy **cùng process, cùng heap** với host. Giới hạn chỉ đến từ
API lộ qua interface. → Không được nạp code không tin cậy. Trong đồ án đây là *rủi ro cần
nêu*, không phải giấu.

---

## C. Kết quả thực nghiệm (số liệu)

**Q10. Chạy interpreted chậm bao nhiêu?**
Slowdown **không đồng đều theo workload** (median, macOS ARM64):

| Workload | native | interp | slowdown |
|---|---|---|---|
| Số học thuần (20M vòng) | 23.1 ms | 303 ms | **13.1×** |
| Gọi hàm/đệ quy (fib 32) | 9.2 ms | 99.5 ms | **10.8×** |
| Cấp phát nhiều (3M list) | 4.0 ms | 257 ms | **63.7×** |

**Điểm ăn điểm:** code **cấp phát nhiều chậm hơn hẳn (63.7×)** vì mỗi allocation trong
interpreter đi qua runtime path chậm; còn số học/gọi hàm chỉ ~11–13×. Hệ quả thực dụng:
code-push hợp cho **vá logic/luồng điều khiển**, đắt cho **hot-loop cấp phát nhiều**.
Đa số app vẫn native → slowdown tổng thể phụ thuộc tỉ lệ code được patch.

**Q11. Một bản cập nhật nặng bao nhiêu? Nạp mất bao lâu?**
Module bench = **1376 bytes**; các module calculator 2.2–3.1 KB. Thời gian nạp (attach
bytecode + set entry stub) = **54 µs** — gần như tức thì, vì không map/exec code, đúng
như cơ chế dispatch (Q4).

**Q12. Vì sao nạp nhanh thế mà chạy lại chậm?**
Nạp chỉ gắn bytecode + đổi entry-point (O(số hàm), rẻ). Cái chậm là *thực thi* từng lệnh
bytecode qua interpreter thay vì CPU chạy machine code trực tiếp.

**Q12b. Bật dynamic modules làm app to hơn bao nhiêu?**
Đo host calculator, AOT snapshot: **KHÔNG dyn-modules 1.83 MB → CÓ 4.39 MB, tức
+2.68 MB (+140%)**. Nguyên nhân: `dynamic_interface` cho `dart:core`+`dart:math` là
callable → **không tree-shake được** phần đó nữa. Caveat trung thực: đây là app *nhỏ*
nên bloat tương đối lớn; phần ~2.7MB (giữ dart:core+math) gần như **cố định**, nên app
lớn sẵn dùng nhiều dart:core thì bloat *tương đối* nhỏ đi nhiều. → chi phí kể cả user
không bao giờ nhận patch.

**Q13. Con số này tin được không?** *(câu hỏi phương pháp)*
1 máy, 1 workload, median 7 lần, có warm-up. Để chặt chẽ hơn cần đo nhiều loại workload
(số học / gọi hàm nhiều / cấp phát nhiều) vì overhead interpreter khác nhau — đây là
việc mở rộng ở Chương 6.

---

## D. Ràng buộc triển khai (iOS — dễ bị vặn)

**Q14. Vì sao iOS là khó nhất?**
Ở PoC CLI trên máy macOS mình gặp **SIGKILL** khi load AOT snapshot: runtime ký
adhoc + hardened runtime, mmap code executable bị OS chặn. Mình fix bằng **ký lại với
entitlement JIT** (`allow-jit`, `allow-unsigned-executable-memory`) — chỉ làm được trên
macOS desktop. Trên **iOS không ký kiểu này được** → đó là rào thật. (Bằng chứng thực
nghiệm: `dyn_modules_poc_guide.md` §gotcha.)

> Cập nhật: câu hỏi này **đã được thực nghiệm giải quyết** trên iPhone thật —
> interpreter **không cần** JIT entitlement nào, kể cả chữ ký ad hoc. Xem
> `dyn_modules_ios_result.md`. Gotcha trên là đặc thù macOS desktop, không áp cho iOS.

**Q15. Interpreter có chạy được trên iOS không?**
Được về mặt kỹ thuật: interpreter chạy bytecode trên page read-only, **không exec code tải
về**, không cần JIT entitlement — đã thực nghiệm thành công trên iPhone thật
(`dyn_modules_ios_result.md`). Nhưng còn giới hạn **chưa hỗ trợ FFI từ module** → chưa thể
khẳng định production-ready trên iOS.

**Q16. Đã chạy trên app Flutter thật chưa?** *(phải trả lời trung thực)*
Chưa. PoC hiện là **Dart CLI thuần** (`dartaotruntime`). Ghép interpreter vào **Flutter
engine** là bước lớn (Shorebird làm điều này qua engine build riêng) — đặt ở "hướng phát
triển". Đây là giới hạn phạm vi đã nêu ở Chương 1.

---

## E. So sánh & phản biện

**Q17. Khác Shorebird thế nào?**
Shorebird: patch *đè* hàm, iOS interpreter (private) + Android bipatch AOT (native).
Dynamic modules: *thêm* module, interpreter chính chủ public, có capability interface.
Shorebird tối ưu *hotfix*; dyn_modules tối ưu *extensibility* + minh bạch.

**Q18. Nếu đã có Shorebird rồi thì đóng góp của đồ án là gì?**
(i) Dựng lại cơ chế **từ nguồn public**, không phụ thuộc fork private; (ii) **giải mã +
tài liệu hoá** cơ chế dispatch mà Shorebird giấu; (iii) **đo lường** cái giá; (iv) phân
tích ranh giới triển khai iOS. Tức là mở "hộp đen" bằng phương pháp tái lập được.

**Q19. Vì sao không dùng CodePush (React Native)?**
CodePush dễ vì RN chạy **JS** (vốn đã interpreted). Flutter/Dart compile **AOT native**
nên bài toán khác hẳn — đó chính là lý do đề tài tồn tại.

**Q20. dynamic modules còn experimental, sao dựa vào?**
Đúng, Dart ghi rõ "không dùng production". Nhưng đồ án là **nghiên cứu tính khả thi +
đo lường**, không phải sản phẩm. Đã **pin commit SDK** (`53b0a522…`) để tái lập.

---

## F. Câu "bẫy" trung thực

**Q21. Đây là sản phẩm hay nghiên cứu?**
Nghiên cứu. Dynamic modules là tính năng **experimental** của Dart (chính chủ ghi rõ
"không dùng production"). Đồ án đo lường tính khả thi + cái giá hiệu năng bằng phương
pháp tái lập được từ nguồn public, không nhằm xây sản phẩm thương mại.

**Q22. Provenance chưa xong thì bảo mật thế nào?**
Hiện dựa vào TLS khi truyền + interface validate lúc compile. Ký số + provenance đầy đủ
là việc còn thiếu (đã nêu ở phần giới hạn) — trung thực là điểm mạnh khi phản biện.

**Q23. 13.4× có phải luôn đúng?**
Không. Là worst-case loop số học. Workload gọi API host nhiều sẽ khác (chi phí transition
native↔interpreter). Cần đo thêm — đã ghi là hướng mở rộng.

**Q24. Tại sao host phải compile 2 lần (no-aot + aot)?**
Bản `no-aot` (kernel chưa tối ưu) làm **mỏ neo** để `dart2bytecode` compile module bám
vào đúng "hình dạng" API host. Bản `aot` là app thật chạy. Tương tự vai trò "release làm
diff-base" của Shorebird.

**Q25. Nếu host đổi version thì module cũ còn chạy không?**
Không đảm bảo — bytecode không có ABI ổn định, cần provenance khớp. Đây là bài toán
versioning production còn mở (Dart cũng chưa giải xong).

---

## Con trỏ nhanh khi bị hỏi sâu
- Kiến trúc tổng thể → `dyn_modules_research.md`
- Pipeline + PoC + gotcha iOS → `dyn_modules_poc_guide.md`
- Cơ chế dispatch (Q4) → `dyn_modules_dispatch_mechanism.md`
- Timeline + commit khảo cổ → `dyn_modules_research.md` §1
- Đề cương chương mục → `dyn_modules_thesis_outline.md`
- Số benchmark → `run_bench.sh` (arith 13.1× / fib 10.8× / alloc 63.7× ; load ~70µs)
- App-size bloat → `run_bloat.sh` (1.83MB → 4.39MB, +140%)
