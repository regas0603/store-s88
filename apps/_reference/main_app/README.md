# apps/_reference/main_app — main_app THAM CHIẾU

Không phải app thật (không có `app.yaml`, wizard bỏ qua thư mục bắt đầu bằng
`_`). Hai vai trò:

1. **Host tham chiếu khi compile patch** — `tools/dynpub.sh` [2] luôn xuất
   main_app này trước khi compile, để "patch cần gì" chỉ phản ánh shell chung
   (không lẫn package riêng của app nào). Giữ nó TỐI GIẢN: chỉ phụ thuộc flutter.
2. **Khung cho app mới** — menu [4] → Thêm app chép thư mục này sang
   `apps/<bundleId>/main_app`.

Phần dưới là contract chung mọi `main_app` phải theo.

---

## main_app — nguồn "main app" (màn "sạch" của shell)

Folder này là **NGUỒN** (nằm trong repo này, ngang cấp `app/`): code UI màn
"sạch" + nhận diện app (title/tên/theme) + rule. App KHÔNG build trực tiếp từ
đây — chạy tool để **xuất** ra package ngoài rồi app mới path-dep vào bản xuất:

```bash
bash tools/cmd/build_main_app.sh              # xuất + pub get/analyze/test
bash tools/cmd/build_main_app.sh --dry-run    # xem trước, không ghi file
bash tools/cmd/build_main_app.sh --out-dir D  # xuất tới thư mục khác
bash tools/cmd/build_main_app.sh --no-verify  # chỉ copy, bỏ pub get/analyze/test
bash tools/cmd/build_main_app.sh check        # chỉ verify bản xuất hiện có
```

Bản xuất mặc định: `../main_app_package` (NGOÀI git repo — ngang cấp
`../app_package`). `app/pubspec.yaml` chỉ phụ thuộc bản xuất đó, CÓ Ở CẢ 2
mode (release + patch) — đây là UI chính build sẵn trong host. Khác với
`../app_package` (game) — cái đó CHỈ bay bằng module OTA.

## Contract (tool tự check — vi phạm là fail, app không build được)

| # | Rule |
|---|---|
| 1 | Tên package bắt buộc `main_app_package` — import cố định `package:main_app_package/main_app_package.dart` bên app |
| 2 | Export `MainAppScreen` — widget `const`, không tham số bắt buộc (`MainAppScreen.new` làm `appScreenBuilder` của BootShell) |
| 3 | Export `mainAppMeta` (`final MainAppMeta`): `appTitle` (AppBar), `appName` (MaterialApp.title / task-switcher), `theme` (ThemeData?, null = theme mặc định shell) |
| 4 | `lib/` KHÔNG chứa từ nhạy cảm (đặt tên trung tính, package tự chứa); pubspec KHÔNG phụ thuộc repo app |

## Cấu trúc

```
main_app/
├── lib/main_app_package.dart       # public API (exports) + doc contract
├── lib/main.dart                   # entry CHẠY THỬ standalone (preview)
├── lib/src/main_app_meta.dart      # MainAppMeta + mainAppMeta (title/tên/theme)
├── lib/src/main_app_screen.dart    # MainAppScreen — toàn bộ UI màn "sạch"
└── test/main_app_package_test.dart # smoke test contract
```

## Chạy thử UI standalone (không cần boot flow)

```bash
cd apps/_reference/main_app && flutter run   # xem màn "sạch" + title/tên từ mainAppMeta
```

> `lib/main.dart` ở đây CHỈ là preview — KHÔNG phải entry của app thật.
> Entry thật vẫn nằm ở `app/lib/main.dart`, vì file đó phải dựng `BootShell`
> (boot flow + gate dynamic module) của project app.

## Đổi diện mạo (white-label mới)

1. Sửa `lib/src/main_app_meta.dart` — `appTitle`, `appName`, `theme`.
2. Sửa UI `lib/src/main_app_screen.dart` (giữ tên class `MainAppScreen`,
   private widget thoải mái đổi).
3. `bash tools/cmd/build_main_app.sh` — xuất lại + verify.
4. Build app như thường: `bash tools/cmd/dynmod.sh app android` (hoặc `ios`),
   rồi đăng release bằng `bash tools/cmd/dynpush.sh release …`.

Muốn giữ nhiều bản cùng lúc: `--out-dir` tới thư mục khác rồi trỏ
`app/pubspec.yaml` sang bản đó.
