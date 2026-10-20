# Quy tắc dự án flutter-self-host

## 1. CHỈ dùng Flutter của engine — KHÔNG dùng `flutter` trong PATH

Mọi lệnh Flutter / Dart trong repo này (test, analyze, pub get, run, build,
format, gen code…) PHẢI chạy bằng Flutter trong thư mục engine:

```
/Users/admin/Documents/work/engine/flutter-framework/bin/flutter   (= ../engine/flutter-framework)
/Users/admin/Documents/work/engine/flutter-framework/bin/dart
```

KHÔNG dùng `flutter` / `dart` trong PATH (`/Users/admin/flutter`, bản stable
khác version), kể cả để "chạy test nhanh".

**Vì sao:** mỗi lệnh `flutter test` / `analyze` / `run` tự chạy `pub get`.
Flutter khác version ghim version package khác → lặng lẽ ghi lại
`pubspec.lock` (đã xảy ra: `clock 1.1.3 → 1.1.2`, `meta`, `vector_math`…).
Version package host = ABI của bản build: lock trôi → host build ra ABI khác →
registry đánh dấu patch không tương thích → máy người dùng dừng ở patch cũ.

**Mọi thứ cần để DÙNG nằm trong 1 thư mục `../engine`:**

| Trong `../engine` | Là gì |
|---|---|
| `flutter-framework/` | CLI `bin/flutter`, `bin/dart` + framework + `.git` (cùng revision engine, KHÔNG gồm source engine) |
| `out/` | engine đã build (`android_release_arm64`, `ios_release`, `host_release_arm64`) — tool tự truyền `--local-engine-src-path` |
| `flutter/` | nguồn SDK + package `dynamic_modules` (app path-dep) |
| `logs/` | log của tool |

`../dart-sdk-build` (~57GB, source engine) CHỈ cần khi build lại engine (đổi
version Flutter qua `tools/setup.sh`); bước `dynmod.sh backup` tự chép lại vào
`../engine`.

**Cách chạy:**

| Việc | Lệnh |
|---|---|
| pub get cho `app/` | `bash tools/cmd/dynmod.sh pubget` |
| test / analyze 1 package | `cd <package> && /Users/admin/Documents/work/engine/flutter-framework/bin/flutter test` |
| chạy app lúc dev | `bash tools/cmd/run.sh …` |
| build / patch / phát hành | `bash tools/dynpub.sh` |

**Lưới chặn đã có:**
- pubspec của `app/`, `loading_kit/*`, `apps/*/main_app` yêu cầu
  `sdk: ^3.13.0`, `flutter: ">=3.47.0"` → Flutter PATH bị pub từ chối ngay.
- `app/pubspec.lock` được commit (lock tham chiếu). `tools/cmd/lockcheck.py`
  + `dynpub.sh` dừng nếu package đã có đổi version (main_app của app chỉ được
  THÊM package).
- `dynpub.sh` kiểm Flutter đúng commit trong `configs/flutter.json`.
- `.vscode/settings.json` trỏ IDE vào Flutter của engine.

**Đổi version package host có chủ đích:** sửa → pub get bằng Flutter engine →
commit `app/pubspec.lock` TRƯỚC khi build / ra patch (đây là đổi ABI).

**Nếu lỡ chạy nhầm** (hoặc lock đổi ngoài ý muốn): dừng, báo lại;
`git checkout -- app/pubspec.lock && bash tools/cmd/dynmod.sh pubget`.

## 2. Sau khi chạy lệnh Flutter, kiểm lock không đổi ngoài ý muốn

`python3 tools/cmd/lockcheck.py` phải PASS và `git diff --stat -- app/pubspec.lock` sạch, trừ khi việc đang làm là cố
ý đổi dependency. Đổi version package host là đổi ABI → nói rõ với người dùng.

## 3. Khác

- Code app chỉ build Android + iOS (không web/desktop).
- `../app_package` là bản SINH RA (convert_to_package.sh) — sửa ở nguồn hoặc
  `templates/module` rồi `tools/cmd/modprep.sh apply`, không sửa bản áp.
- Thiết kế phát hành: `docs/release_registry_design.md`; tool: `tools/README.md`.
