import 'package:app/shell/boot_shell.dart';
import 'package:app/shell/dynmod_gate_impl.dart';
import 'package:flutter/material.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:main_app_package/main_app_package.dart';

/// Entrypoint (bản nộp store).
///
/// KHÔNG import `app_package` (package game). Bản lên store chỉ có: boot flow
/// (loading_kit) + splash + màn "sạch" [MainAppScreen] + màn live do module
/// dynmod cung cấp ([DynmodLiveView]).
///
/// Chạy dev: `bash tools/cmd/run.sh ios-sim` (dùng file này).
Future<void> main() async {
  // Text (Git JSON `texts`) đã cache từ lần chạy trước — nạp TRƯỚC runApp
  // để splash có chữ ngay từ frame đầu.
  WidgetsFlutterBinding.ensureInitialized();
  await RemoteTexts.restoreCached();
  // Package host (configs/abi/host_packages.yaml) được ghim vào kernel host +
  // anchor qua shell/host_packages.g.dart — nằm trên cây import của
  // dynmod_gate_impl.dart, không cần gọi gì ở đây.
  runApp(const TempApp());
}

class TempApp extends StatelessWidget {
  const TempApp({super.key, this.launchCoordinator});

  /// Inject [AppLaunchCoordinator] (chỉ dùng cho test). Không truyền = tạo
  /// mới với [AppDynmodGate].
  final AppLaunchCoordinator? launchCoordinator;

  @override
  Widget build(BuildContext context) {
    // Boot flow / splash / gate nằm trong [BootShell] — DÙNG CHUNG.
    return BootShell(
      launchCoordinator:
          launchCoordinator ?? AppLaunchCoordinator(dynmodGate: AppDynmodGate()),
      // Nhận diện app (title/tên app/theme) từ package main_app_package —
      // shell KHÔNG hardcode gì.
      title: mainAppMeta.appName,
      theme: mainAppMeta.theme,
      // Màn live do module (game) tự dựng MaterialApp.router → shell
      // KHÔNG bọc MaterialApp (flutter/flutter#142585).
      ownRootMaterialApp: false,
      liveScreenBuilder: () =>
          DynmodLiveView(fallback: (context) => const TrueScreen()),
      appScreenBuilder: MainAppScreen.new,
    );
  }
}

/// Màn hình chế độ chính (`AppMode.live`).
///
/// Gate chỉ mở live khi module đã nạp + verify OK. Widget này là fallback
/// khi chưa có module nào (hiển thị lúc dev/verify).
class TrueScreen extends StatelessWidget {
  const TrueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? text = RemoteTexts.current.liveFallback;
    return Scaffold(
      body: Center(child: text == null ? null : Text(text)),
    );
  }
}
