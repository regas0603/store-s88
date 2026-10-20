# Cơ chế dispatch native↔interpreted trong Dart Dynamic Modules

> **Phần C** — trả lời câu hỏi mở "tầng 2" trong `dyn_modules_research.md`:
> *VM quyết định chạy interpreter hay native tại mỗi lời gọi như thế nào?*
> Verify trực tiếp trên source HEAD `53b0a522…` + commit tái sinh `8fbca8ba673`
> (alexmarkov, 2024-08-15, Gerrit CL 380281, review bởi Slava Egorov).
> Toàn bộ subsystem gói trong `#if defined(DART_DYNAMIC_MODULES)` — bật bởi cờ build
> `--dart-dynamic-modules`.

## Kết luận cốt lõi (một câu)

**Dispatch KHÔNG cần rẽ nhánh tại mỗi call-site.** Nó được "nướng" vào **entry-point**
của Function: hàm native có entry-point là machine code thật; hàm bytecode (dynamic
module) có entry-point trỏ tới **`InterpretCall` stub**. Calling convention thống nhất
lo phần còn lại — caller AOT không cần biết callee là native hay interpreted.

## Chi tiết cơ chế (verify từ source)

### 1. Gắn bytecode + đặt entry-point — `runtime/vm/object.cc:8154`
```cpp
void Function::AttachBytecode(const Bytecode& value) const {
  ...
  untag()->set_ic_data_array_or_bytecode(value.ptr());  // gắn bytecode vào Function
  // Set the code entry_point to InterpretCall stub.
  SetInstructions(StubCode::InterpretCall());            // ← MẤU CHỐT
}

bool Function::IsInterpreted(FunctionPtr function) {
  return function->untag()->code() == StubCode::InterpretCall().ptr();
}
```
→ Không có cờ boolean riêng. "Hàm này interpreted?" = "entry-point của nó có phải
InterpretCall stub không?". Khi dynamic module được nạp, mỗi hàm trong module được
`AttachBytecode` → entry-point thành stub.

### 2. Native → bytecode: xuyên qua stub, không rẽ nhánh
- Caller đã AOT-compile phát lệnh call theo calling convention thường → nhảy tới
  entry-point của callee.
- Nếu callee là hàm module, entry-point đó = `InterpretCall` stub
  (`GenerateInterpretCallStub`, `compiler/stub_code_compiler_arm64.cc:3288`).
- Stub gọi runtime entry `InterpretCall` (`runtime_entry.cc:5762`):
```cpp
extern "C" uword InterpretCall(function_in, argdesc_in, argc, argv, thread) {
  Interpreter* interpreter = Interpreter::Current();
  ...
  ObjectPtr result =
      interpreter->Call(function, argdesc, argc, argv, Array::null(), thread);
  ...
}
```
→ `Interpreter::Call` (`interpreter.cc:1654/1959`) chạy KBC bytecode của hàm.
Ghi chú quan trọng trong code: *"We stay in 'in generated code' execution state when
interpreting code"* — interpreter chạy như thể vẫn trong generated code, nên transition
native↔interpreted rất nhẹ.

### 3. Bytecode → native: chiều ngược
Khi interpreter gặp lời gọi tới hàm ĐÃ AOT-compile:
- `Interpreter::InvokeCompiled(...)` (`interpreter.h:187`) chuyển về chạy machine code.
- Đối xứng có `InvokeBytecode(...)` (bytecode gọi bytecode) và `Invoke(...)` (điều phối).
- Stub hỗ trợ: `InvokeDartCodeFromBytecodeStub` (`stub_code_compiler_arm64.cc:1807`).

### 4. Sơ đồ
```
   [Host AOT native]  --call-->  entry_point(callee)
                                     |
              callee là module? entry_point == InterpretCall stub
                                     |  (không rẽ nhánh tại call-site)
                                     v
                   InterpretCall stub  ->  RuntimeEntry InterpretCall
                                     |
                                     v
                        Interpreter::Call  (chạy KBC bytecode)
                                     |
              module gọi API host? --> Interpreter::InvokeCompiled
                                     |     (InvokeDartCodeFromBytecodeStub)
                                     v
                          quay lại [Host AOT native]
```

## Vì sao đây là thiết kế hay (luận điểm cho thesis)
1. **Zero-overhead cho code native:** hàm không-module chạy đúng như AOT thường,
   không thêm một lệnh kiểm tra nào tại call-site.
2. **Trong suốt với caller:** không cần recompile/patch caller khi nạp module — chỉ
   entry-point của callee thay đổi. Đây là điều làm "additive-only" khả thi sạch sẽ.
3. **Đối xứng hai chiều:** native↔interpreted qua stub + `InvokeCompiled`, nên module
   gọi được API host và ngược lại, cùng một heap.

## So với Shorebird (điền vào bảng §4 research doc)
- Shorebird (iOS) cũng dùng interpreter cho code patched, nhưng cơ chế dispatch của họ
  private. Cơ chế dyn_modules ở trên là **bản công khai tương đương**: entry-point =
  InterpretCall stub. Nếu Shorebird dùng cùng ý tưởng (rất có thể, vì cùng nền KBC),
  thì đây chính là "hộp đen" mà đồ án của bạn nay mở được bằng nguồn chính chủ.

## Con trỏ file (để trích dẫn trong thesis)
| Vai trò | File:dòng |
|---|---|
| Gắn bytecode + set entry stub | `runtime/vm/object.cc:8154` (`AttachBytecode`) |
| Định nghĩa IsInterpreted | `runtime/vm/object.cc:8171` |
| Runtime entry vào interpreter | `runtime/vm/runtime_entry.cc:5762` (`InterpretCall`) |
| Vòng lặp interpreter | `runtime/vm/interpreter.cc:1654` (`Interpreter::Call`) |
| Điều phối gọi hàm | `runtime/vm/interpreter.h:180-195` (`Invoke*`) |
| Stub native→interp (arm64) | `compiler/stub_code_compiler_arm64.cc:3288` |
| Stub interp→native (arm64) | `compiler/stub_code_compiler_arm64.cc:1807` |
| KBC opcodes | `runtime/vm/constants_kbc.h` |
| Đọc bytecode | `runtime/vm/bytecode_reader.cc` |
| Cờ build bật toàn bộ | `DART_DYNAMIC_MODULES` (từ `--dart-dynamic-modules`) |
