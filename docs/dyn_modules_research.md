# Nghiên cứu: Dart Dynamic Modules làm nền code-push self-host cho Flutter

> Tài liệu nền cho đồ án tốt nghiệp. Tổng hợp từ nguồn public của `dart-lang/sdk`
> (README `pkg/dynamic_modules`, issue tracker, lịch sử git). Trạng thái xác minh
> được ghi rõ ở mỗi mục: **[verified]** = đã tra nguồn; **[suy luận]** = suy ra,
> cần kiểm lại khi có source trên máy.

## 0. Câu hỏi nghiên cứu

> *Cơ chế **dynamic modules** chính chủ của Dart có dùng được làm nền **code-push
> self-host** cho Flutter không, và so với cách interpreter **private** của Shorebird
> thì khác/hơn/kém ở đâu về kiến trúc, bảo mật và ràng buộc triển khai?*

Điểm mấu chốt: cơ chế lõi mà Shorebird giữ private (interpreter chạy code đã patch
trong khi code cũ chạy AOT native) nay **đã có bản chính chủ, public, đang phát
triển tích cực** trong mainline Dart dưới tên `dyn_modules`. Đề tài không còn là
"tái tạo mù thứ bí mật" mà là "đánh giá + so sánh + mở rộng thứ công khai".

---

## 1. Bối cảnh: DBC → gỡ → dyn_modules

Timeline (từ lịch sử git + issue tracker, **[verified]** trừ chỗ ghi khác):

| Mốc | Sự kiện |
|---|---|
| ~2018–2019 | Dart có bytecode interpreter **KBC** (Kernel ByteCode): `runtime/vm/interpreter.cc`, `runtime/vm/constants_kbc.h`, generator `pkg/vm/lib/bytecode/`. |
| Tag **2.9.3** | `interpreter.cc` còn nguyên vẹn (commit cuối chạm ~7/2020) → **baseline cũ để đọc-hiểu**. |
| **2020-10-28** | Đội Dart **gỡ bytecode mode** khỏi VM. Commit **`7588ed86dee`** "Remove bytecode mode from the VM" — tác giả **Alexander Markov** (alexmarkov), Gerrit CL 169147, review bởi Régis Crelier + Ryan Macnak. (Flutter engine PR #21741 gỡ phía engine ~13/10/2020.) |
| 11/2022 | Issue **#50406** "Allow to load AOT image dynamically at runtime" — feature request gốc (ví AOT image như `.dll/.so`). |
| **2024-08-15** | **Tái sinh interpreter** cho dynamic modules. Commit **`8fbca8ba673`** "[vm] Initial implementation of dynamic modules in the VM/AOT" — **cũng chính Alexander Markov** (người đã gỡ 2020). `interpreter.cc` quay lại mainline. |
| 12/2024 → nay | Phát triển active: `pkg/dynamic_modules`, compiler `pkg/dart2bytecode`, suite `dynamic_modules_suite/*`, CI bot `vm-aot-dyn-linux-product-x64`. Chuỗi commit `[vm,dyn_modules]` tới 7/2026 (Dup, RecordCoverage, dcall validation, FFI handling…). |

> **Chi tiết khảo cổ (verify từ full-history clone, HEAD `53b0a522`):** cùng một kỹ sư
> — Alexander Markov — vừa gỡ KBC bytecode 2020 vừa khởi xướng dynamic modules 2024.
> Đây là luận cứ tường minh: dyn_modules **không phải** copy Shorebird, mà là đội Dart
> tự làm lại cơ chế tương đương theo hướng chính chủ. (Interpreter KBC gốc trước đó:
> commit `41fcbd097ce` "Initial version of Kernel Bytecode interpreter", ~2018.)

**Luận điểm cho chương Background:** Shorebird (2022–2023) fork Dart *trong giai đoạn
interpreter đã bị gỡ khỏi mainline* → buộc phải tự maintain fork private. Đội Dart
sau đó tự làm lại cơ chế tương đương theo hướng chính chủ (`dyn_modules`). Đồ án đứng
trên bản chính chủ này.

---

## 2. Kiến trúc dynamic modules (chính chủ) **[verified]**

Ba thành phần, chuyển từ "closed-world compilation" sang "host mở rộng được":

- **Host Application** — app nền, build standalone, **khai báo API nào được lộ ra**.
- **Dynamic Interface** — file cấu hình (`dynamic_interface.yaml`) quy định *bề mặt
  API* mà module động được phép chạm tới.
- **Dynamic Module** — thư viện Dart mới, có entry-point, nạp *sau khi* host chạy.

Nguyên tắc bất biến quan trọng nhất:

> **"All extensions are additive. Dynamic modules cannot replace an existing
> declaration in the application."**

→ Module chỉ **thêm**, không **thay** khai báo có sẵn ⇒ giữ tính toàn vẹn của host.
(Đây là khác biệt bản chất so với "patch đè hàm cũ" kiểu Shorebird — xem §4.)

### Công nghệ thực thi
- AOT: dynamic module được compile ra **Dart bytecode (KBC)**, chạy bằng **embedded
  interpreter** trong `dartaotruntime`; code host vẫn chạy **AOT native**.
- Bytecode gọi vào code native của host **qua dynamic interface** (không phải map
  trực tiếp memory) — nên không cần `mmap` PROT_EXEC, không đụng rào code-signing.

---

## 3. Quy trình 8 bước (chính chủ) **[verified]**

1. **Build Dart tùy biến** với cờ `--dart-dynamic-modules` (SDK phát hành sẵn KHÔNG
   có — phải build từ source). ⭐ Đây là điểm khởi đầu thực hành của đồ án.
2. Xác định API surface host cần cho module.
3. Viết `dynamic_interface.yaml` — kiểm soát chi tiết cái gì *callable / extendable /
   overrideable / type-usable / dynamically-callable*.
4. **Compile host** với chế độ sửa đổi: bật interpreter support, **tắt một số
   tree-shaking/tối ưu**, nhúng **provenance** để validate.
5. Deploy host (đã lộ API surface).
6. Viết dynamic module theo hợp đồng interface (không được redefine library có sẵn).
7. Chuyển bytecode qua kênh bảo mật (TLS).
8. Runtime **validate** (format + provenance + interface) rồi mới execute entry-point.

`@pragma('dyn-module:entry-point')` đánh dấu hàm entry-point để **sống sót qua TFA
tree-shaking** (xem issue #63377) — cơ chế dispatch host↔module.

> **Cơ chế dispatch đã giải mã chi tiết** → `dyn_modules_dispatch_mechanism.md`:
> entry-point của hàm module = `InterpretCall` stub (không rẽ nhánh tại call-site);
> chiều ngược qua `Interpreter::InvokeCompiled`. Toàn bộ gói trong `DART_DYNAMIC_MODULES`.

`dart2bytecode`: compile module → bytecode, đồng thời **verify API usage vs interface**
và sinh **provenance metadata** (tool version, input spec) làm bằng chứng tương thích,
vì *"Dart bytecode format has no stable ABI"*.

---

## 4. So sánh: dyn_modules vs Shorebird vs CodePush

| Tiêu chí | Dart dyn_modules (chính chủ) | Shorebird | MS CodePush (RN) |
|---|---|---|---|
| Đơn vị cập nhật | Module **thêm mới** (additive) | **Patch đè** hàm đã đổi | Bundle JS |
| Cơ chế chạy | KBC interpreter trong dartaotruntime | Interpreter private (iOS) / bipatch AOT (Android) | JS engine (đã có sẵn) |
| Ranh giới an toàn | **Dynamic interface** (capability rõ ràng) | Không có bề mặt khai báo công khai | JS sandbox của RN |
| Nguồn mở | **Public, mainline** | dart-sdk fork **private** | Public |
| Thay được code cũ? | **Không** (chỉ thêm) | **Có** (mục tiêu chính là fix bug) | Có |
| Verify tương thích | Provenance + interface check | Serializer version (fragile → crash `ReadFill`) | Bundle hash |
| Trạng thái | Experimental, không production | Production (thương mại) | Production |

**Nhận định:** dyn_modules và Shorebird tối ưu cho **hai bài toán khác nhau**:
- Shorebird = *hotfix* (đè code cũ) → mạnh cho vá lỗi, nhưng fragile + private.
- dyn_modules = *extensibility* (thêm tính năng) → an toàn hơn (additive + capability
  interface), public, nhưng **không** thay được code đã ship.

→ Chính khác biệt "additive vs replace" là một **đóng góp phân tích** của đồ án: một
hệ code-push self-host thực dụng cần cái nào, và có thể lai ghép không?

---

## 5. Mô hình bảo mật **[verified]** — phần đáng viết nhất

README cảnh báo thẳng:

> *"Dynamic modules run in an interpreter, but you are loading code into the same
> context of the application... run together as a single program with a shared heap."*

- **Không sandbox** — module chạy chung process/heap với host; giới hạn chỉ đến từ
  API được lộ qua interface, không phải cô lập bộ nhớ.
- **Code không tin cậy = nguy hiểm** — README nói rõ không nạp code ngoài/không review/
  do LLM sinh.
- **Provenance** chống ABI skew + API lệch, **không** đảm bảo an toàn một mình.
- **Truy cập gián tiếp**: module có thể chạm dữ liệu bị hạn chế *thông qua* API đã lộ.

Đây là chất liệu tốt cho chương "Bảo mật & Toàn vẹn": so sánh mô hình capability của
dyn_modules với việc Shorebird không có bề mặt khai báo công khai.

---

## 6. Giới hạn hiện tại (chính chủ tự liệt kê) **[verified]**

Chưa làm: provenance validation đầy đủ; whole-program validation cho dynamic call;
JIT runtime dynamic-call validation; **FFI từ module**; authoring interface cho private
members. **Không kế hoạch**: web backend (DDC/dart2js/dart2wasm); versioning
production-ready. Chốt: *"We don't recommend taking a dependency on it for projects
used in production today."*

Hệ quả cho đồ án: đây là **cơ hội** — mỗi giới hạn là một hướng đóng góp (vd: đo app
size bloat do tắt tối ưu; đề xuất versioning; đánh giá khả thi trên iOS thật).

---

## 7. Ràng buộc triển khai production (giữ trung thực)

- Đồ án dừng ở **nghiên cứu khả thi + đo lường**, không nhắm vào sản phẩm: dyn_modules
  là experimental, README chính chủ khuyên không dùng cho project production.
- Câu hỏi mở đáng nghiên cứu tiếp: provenance, versioning ABI, sandbox cho module
  (hiện module chạy chung heap với host) — mỗi mục là một hướng đóng góp.

---

## 8. Lộ trình PoC (thực hành, từ nguồn public)

> **Đã có bản chi tiết verify:** xem `dyn_modules_poc_guide.md` — pipeline đầy đủ
> (build → compile host 2 lần → dart2bytecode → dartaotruntime) trích trực tiếp từ
> `pkg/dynamic_modules/example/run.sh`, kèm bảng ánh xạ 1:1 sang cơ chế Shorebird.
> Khung tóm tắt bên dưới giữ lại để tham chiếu nhanh.

```bash
# 0. Clone SDK
git clone https://github.com/dart-lang/sdk && cd sdk

# 1. Baseline cũ để đọc-hiểu interpreter Shorebird-style (tuỳ chọn)
git checkout 2.9.3
#   Đọc: runtime/vm/interpreter.cc, constants_kbc.h, pkg/vm/lib/bytecode/

# 2. Nền chính: mainline dyn_modules
git checkout main
ls pkg/dynamic_modules/{example,test,bin,lib}   # ví dụ chạy được + harness
sed -n '1,200p' pkg/dynamic_modules/README.md    # tài liệu gốc 27KB
ls pkg/dart2bytecode                              # compiler module → bytecode

# 3. Build Dart có dyn_modules
#    (tra đúng cú pháp trong tools/ + README; cờ: --dart-dynamic-modules)
#    ./tools/build.py ... với flag bật dynamic modules

# 4. Chạy thử vòng đời theo pkg/dynamic_modules/test:
#    a. viết dynamic_interface.yaml
#    b. dart2bytecode compile module
#    c. dartaotruntime nạp + chạy entry-point (@pragma('dyn-module:entry-point'))
```

**Mục tiêu PoC tối thiểu:** host AOT + 1 dynamic module in ra chuỗi mới sau khi host
đã chạy, KHÔNG rebuild host. Đạt được = đã dựng lại "lõi" code-push chính chủ.

**PoC mở rộng (hướng Flutter):** ghép interpreter dyn_modules vào Flutter engine
(tương tự cờ `SHOREBIRD_USE_INTERPRETER` mà tài liệu cũ nhắc), nạp module qua server
self-host. Đây là phần novel nếu làm được trên thiết bị thật.

---

## 9. Câu hỏi mở cho thesis

1. Additive-only có đủ cho một hệ code-push thực dụng không? Lai với "replace" được không?
2. Overhead interpreted vs native trên workload Flutter thực (đo cụ thể)?
3. App size bloat do tắt tree-shaking — định lượng bao nhiêu?
4. Provenance đủ chống patch độc hại tới đâu? Thiếu gì so với ký số?
5. Khả thi trên iOS thiết bị thật? (code-signing + không FFI).
6. So sánh định lượng với bipatch AOT (hướng Android của Shorebird).

---

## 10. Nguồn (public)

- `pkg/dynamic_modules/README.md` — dart-lang/sdk (tài liệu kiến trúc gốc, 27KB)
- `pkg/dart2bytecode` — compiler module → bytecode
- Issue #50406 — feature request gốc (load AOT image at runtime, 11/2022)
- Issue #60602 — dynamic interface + dart:core
- Issue #63377 — `dyn-module:entry-point` pragma vs TFA tree-shaking
- Flutter engine PR #21741 — gỡ bytecode mode (10/2020)
- `runtime/vm/interpreter.cc`, `runtime/vm/constants_kbc.h` — interpreter/KBC
- Shorebird issue #1871 — câu hỏi về interpreter iOS (không có lời giải chính thức)
- docs.shorebird.dev/code-push/system-architecture — kiến trúc Shorebird
