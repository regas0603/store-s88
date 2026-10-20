# Full checkout + build Dart SDK (dynamic modules) — từng bước, macOS ARM

> Máy bạn đã verify đủ: Xcode đầy đủ, Python 3.12, git 2.48, arm64, ~641GB trống.
> Vị trí checkout tôi dùng: `../dart-sdk-build/` (ngoài git
> repo `flutter-self-host` để không làm bẩn repo). Đổi tuỳ ý.

## "Full checkout" là gì
Sparse clone chỉ tải vài thư mục để đọc → **không build được**. `tools/build.py` cần
toàn bộ source + third_party deps. Phải dùng **depot_tools** (`fetch` + `gclient sync`)
của Google để kéo đủ về.

---

## Bước 1 — Cài depot_tools

```bash
cd ../dart-sdk-build
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"
# (thêm dòng export vào ~/.zshrc để lần sau khỏi gõ lại)
```

## Bước 2 — Fetch Dart SDK (phần lâu nhất, ~vài GB)

```bash
cd ../dart-sdk-build
mkdir dart && cd dart
fetch --no-history dart      # --no-history: nhỏ & nhanh hơn, vẫn build được
# xong sẽ có thư mục con: sdk/
cd sdk
```

> Muốn xem `git log` của `interpreter.cc` cho chương Background thì bỏ `--no-history`
> (nặng hơn nhiều), hoặc lấy lịch sử riêng từ bản clone khác.

## Bước 3 — Pin commit (để thesis tái lập được)

```bash
git -C ../dart-sdk-build/dart/sdk rev-parse HEAD
# GHI hash này vào thesis. dyn_modules là experimental, có thể đổi/xoá bất kỳ lúc nào.
```

## Bước 4 — Build có dynamic modules

```bash
cd ../dart-sdk-build/dart/sdk
./tools/build.py -m release --dart-dynamic-modules \
  runtime runtime_precompiled utils/gen_kernel
# Máy ARM → output ở out/ReleaseARM64  (KHÔNG phải ReleaseX64 như run.sh gốc)
```

## Bước 5 — Chạy ví dụ calculator

`example/run.sh` gốc hardcode `out/ReleaseX64`. Trên ARM phải sửa. Chạy bản đã sửa:

```bash
cd ../dart-sdk-build/dart/sdk
SDK_OUT=out/ReleaseARM64 bash pkg/dynamic_modules/example/run.sh
# (xem run_poc_arm.sh nếu tôi đã tạo — bản run.sh sửa sẵn cho ARM)
```

REPL kỳ vọng:
```
> + 1 2 3        → 6      (built-in, AOT native)
> - 10 3         → Error: Unknown operation "-"
> load basic     → nạp bytecode qua interpreter
> - 10 3         → 7      (interpreted, host KHÔNG rebuild)   ← PoC thành công
```

---

## Nếu build lỗi
- Thiếu Xcode license: `sudo xcodebuild -license accept`.
- `gclient` hook fail: chạy lại `gclient sync` trong `dart/` (không phải `dart/sdk/`).
- Sai arch trong run.sh: kiểm `ls out/` xem tên thư mục thật rồi set `SDK_OUT`.

## Dọn dẹp
Toàn bộ nằm trong `../dart-sdk-build/` — xoá thư mục này là
sạch, không đụng gì tới repo `flutter-self-host`.
