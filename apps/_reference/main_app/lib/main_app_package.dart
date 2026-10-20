/// Main app UI — màn hình "sạch" + nhận diện app (title/tên/theme) của shell.
///
/// Nguồn của package nằm trong repo app (thư mục `main_app/`); bản package
/// app thực sự build phụ thuộc được XUẤT ra ngoài bằng
/// `tools/cmd/build_main_app.sh` (mặc định `../main_app_package`) — app chỉ
/// path-dep vào bản xuất, không phụ thuộc thư mục nguồn.
///
/// CONTRACT (rule bắt buộc — tool `build_main_app.sh` tự check, app build
/// fail ngay lúc compile nếu vi phạm):
///
/// 1. **Tên package: `main_app_package`** — `lib/main.dart` +
///    `lib/main_patch.dart` bên app import cố định
///    `package:main_app_package/main_app_package.dart`. Đổi diện mạo app =
///    sửa nguồn `main_app/` rồi chạy lại tool xuất, KHÔNG sửa code app.
/// 2. **Export `MainAppScreen`** — widget `const`, không tham số bắt buộc
///    (dùng cho `MainAppScreen.new` làm `appScreenBuilder` của shell).
/// 3. **Export `mainAppMeta`** — `final MainAppMeta`: `appTitle` (AppBar),
///    `appName` (MaterialApp.title / tên trên task-switcher), `theme`
///    (ThemeData?, null = theme mặc định của shell).
/// 4. `lib/` KHÔNG chứa từ nhạy cảm và KHÔNG phụ thuộc repo app (chỉ flutter
///    sdk + pub.dev) — tool grep chặn khi xuất.
/// 5. `lib/main.dart` là entry CHẠY THỬ standalone (`cd main_app && flutter
///    run`) — KHÔNG phải entry của app thật (entry thật nằm ở `app/lib/`,
///    dựng BootShell; engine patch load `app/lib/main_patch.dart`).
///
/// Chi tiết + checklist làm variant: xem `README.md`.
library;

export 'src/main_app_meta.dart';
export 'src/main_app_screen.dart';
