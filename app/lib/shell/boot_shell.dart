import 'dart:io';

import 'package:flutter/material.dart';
import 'package:loading_kit/core/remote_texts.dart';
import 'package:loading_kit/flow/app_launch_coordinator.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart' show AppMode;
import 'package:loading_kit/flow/update_policy.dart';
import 'package:loading_kit/screens/splash_mode_screen.dart';
import 'package:loading_kit/update/force_update_dialog.dart';
import 'package:restart_app/restart_app.dart';

/// Shell dùng CHUNG cho app:
///
/// * màn "chính" ([AppMode.live]) là module dynmod đã nạp ([DynmodLiveView]);
/// * màn [AppMode.demo] là app "sạch" hiển thị khi máy CHƯA có module nào.
///
/// Vì sao phải SWAP cây widget ở root:
/// module tự dựng `MaterialApp.router`. Nếu nó nằm LỒNG trong
/// `MaterialApp` của shell → sau khi điều hướng chỉ còn nền đen
/// (flutter/flutter#142585). Nên khi vào live, shell render màn chính
/// TRỰC TIẾP ở root ([ownRootMaterialApp] = false).
class BootShell extends StatefulWidget {
  const BootShell({
    super.key,
    required this.liveScreenBuilder,
    required this.appScreenBuilder,
    this.splashScreenBuilder,
    required this.launchCoordinator,
    this.title = '',
    this.theme,
    this.ownRootMaterialApp = false,
    this.initialFlowDelay = Duration.zero,
  });

  /// Màn hình chế độ CHÍNH ([AppMode.live]) — vế `trueScreenBuilder` của
  /// [SplashModeScreen] và cũng là widget được render ở root khi đã vào live.
  final Widget Function() liveScreenBuilder;

  /// Màn hình chế độ [AppMode.demo] — app "sạch" hiển thị khi máy CHƯA có
  /// module nào (bản mới lên store, hoặc server module lỗi).
  final Widget Function() appScreenBuilder;

  /// Splash tuỳ chỉnh; null = [SplashView] mặc định của loading_kit (kèm 6 chấm).
  final Widget Function()? splashScreenBuilder;

  /// Coordinator điều phối boot flow + gate (force update, module dynmod).
  /// Entry point (`main.dart`) bơm vào; widget test thay bằng fake.
  final AppLaunchCoordinator launchCoordinator;

  /// Title của `MaterialApp` (cả nhánh splash lẫn live) — entry point truyền
  /// từ package `main_app_package` (`mainAppMeta.appName`), KHÔNG hardcode ở
  /// shell.
  final String title;

  /// Theme tuỳ chỉnh; null = [_defaultTheme]. Entry point truyền từ
  /// `mainAppMeta.theme` (package main_app_package) — đổi theme app thì sửa
  /// meta bên package, shell không đụng vào.
  final ThemeData? theme;

  /// true = shell bọc màn chính trong `MaterialApp` của mình;
  /// false (mặc định) = màn chính tự dựng `MaterialApp` (module).
  final bool ownRootMaterialApp;

  final Duration initialFlowDelay;

  @override
  State<BootShell> createState() => _BootShellState();
}

class _BootShellState extends State<BootShell> {
  /// true = đã vào [AppMode.live] → render màn chính ở root.
  bool _isLive = false;

  /// Version module mới đã tải NỀN xong và ĐANG BỊ ÉP restart (ver hiện tại
  /// < `min_force_update` của manifest) — đọc từ
  /// [AppLaunchCoordinator.moduleUpdateReady] (`null` = không có popup nào).
  /// Bản mới không ép (đã đủ ngưỡng) thì gate không trả về → không popup,
  /// tự áp ở lần mở app sau. Đã persist state trước khi popup hiện → Cancel
  /// chỉ hoãn, bản mới tự áp ở lần mở sau.
  int? _pendingUpdateVersion;

  /// Popup cập nhật app (soft/force theo manifest) cần hiện trên màn live —
  /// đọc từ [AppLaunchCoordinator.updatePrompt] (`null` = không có). Force
  /// lúc boot do [SplashModeScreen] chặn ngay ở gate, KHÔNG qua đây.
  UpdateDecision? _updatePrompt;

  late final VoidCallback _moduleUpdateListener;
  late final VoidCallback _updatePromptListener;

  @override
  void initState() {
    super.initState();
    _moduleUpdateListener = _syncPendingUpdate;
    _updatePromptListener = _syncUpdatePrompt;
    _attach(widget.launchCoordinator);
  }

  @override
  void didUpdateWidget(covariant BootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.launchCoordinator, widget.launchCoordinator)) {
      _detach(oldWidget.launchCoordinator);
      _attach(widget.launchCoordinator);
    }
  }

  @override
  void dispose() {
    _detach(widget.launchCoordinator);
    super.dispose();
  }

  void _attach(AppLaunchCoordinator coordinator) {
    coordinator.moduleUpdateReady.addListener(_moduleUpdateListener);
    coordinator.updatePrompt.addListener(_updatePromptListener);
    _pendingUpdateVersion = coordinator.moduleUpdateReady.value;
    _updatePrompt = coordinator.updatePrompt.value;
  }

  void _detach(AppLaunchCoordinator coordinator) {
    coordinator.moduleUpdateReady.removeListener(_moduleUpdateListener);
    coordinator.updatePrompt.removeListener(_updatePromptListener);
  }

  /// Notifier popup cập nhật app đổi → hiện/bỏ overlay soft/force.
  void _syncUpdatePrompt() {
    if (!mounted) {
      return;
    }
    final UpdateDecision? prompt = widget.launchCoordinator.updatePrompt.value;
    if (prompt == _updatePrompt) {
      return;
    }
    setState(() => _updatePrompt = prompt);
  }

  /// Notifier đổi → hiện/bỏ popup restart (setState ngoài phase build).
  void _syncPendingUpdate() {
    if (!mounted) {
      return;
    }
    final int? version = widget.launchCoordinator.moduleUpdateReady.value;
    if (version == _pendingUpdateVersion) {
      return;
    }
    setState(() => _pendingUpdateVersion = version);
  }

  /// Cancel ở popup: bỏ qua restart — phiên hiện tại giữ ver cũ, bản mới đã
  /// nằm trên disk + state đã persist → tự áp ở lần mở app sau.
  void _dismissModuleUpdatePrompt() {
    widget.launchCoordinator.moduleUpdateReady.value = null;
  }

  void _onModeChanged(AppMode mode) {
    if (!mounted) {
      return;
    }
    final bool isLive = mode == AppMode.live;
    if (isLive == _isLive) {
      return;
    }
    setState(() => _isLive = isLive);
  }

  @override
  Widget build(BuildContext context) {
    final Widget root = _buildRoot(context);
    final Widget? overlay = _buildOverlay();
    if (overlay == null) {
      return root;
    }
    // Overlay dạng SIBLING của root (Stack), KHÔNG lồng trong MaterialApp của
    // module → không vấp flutter/flutter#142585 (2 MaterialApp lồng nhau →
    // màn đen sau điều hướng). Popup tự dựng MaterialApp riêng nên có đủ
    // Material/Navigator/Localizations dù root đang là module (ownRoot=false).
    // Directionality bọc NGOÀI Stack vì BootShell ở đỉnh cây — TRÊN mọi
    // MaterialApp (MaterialApp chỉ cung cấp Directionality cho con bên trong).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: root),
          Positioned.fill(child: overlay),
        ],
      ),
    );
  }

  /// Chỉ 1 popup tại 1 thời điểm, ưu tiên: FORCE (chặn hẳn, không tắt được)
  /// > restart (bản module mới đã tải) > SOFT. Popup thấp hơn hiện sau khi
  /// popup trên được tắt (notifier giữ giá trị).
  Widget? _buildOverlay() {
    final ThemeData theme = widget.theme ?? _defaultTheme;
    final UpdateDecision? prompt = _updatePrompt;
    final ForceUpdateLink? link = prompt?.toLink();
    if (prompt != null && prompt.isForce && link != null) {
      return _UpdatePromptOverlay(link: link, theme: theme);
    }
    final int? pending = _pendingUpdateVersion;
    if (pending != null) {
      return _ModuleUpdateReadyDialog(
        version: pending,
        theme: theme,
        onLater: _dismissModuleUpdatePrompt,
      );
    }
    if (prompt != null && prompt.isSoft && link != null) {
      return _UpdatePromptOverlay(
        link: link,
        theme: theme,
        // "Để sau": ghi dismissed_latest + thời điểm, chơi tiếp.
        onLater: widget.launchCoordinator.dismissSoftUpdatePrompt,
        // Store đã mở: tắt popup, KHÔNG ghi từ chối (lần mở sau hỏi lại nếu
        // vẫn chưa cài).
        onOpened: widget.launchCoordinator.clearSoftUpdatePrompt,
      );
    }
    return null;
  }

  Widget _buildRoot(BuildContext context) {
    if (_isLive) {
      final Widget liveScreen = widget.liveScreenBuilder();
      if (!widget.ownRootMaterialApp) {
        return liveScreen;
      }
      return MaterialApp(
        title: widget.title,
        debugShowCheckedModeBanner: false,
        theme: widget.theme ?? _defaultTheme,
        home: liveScreen,
      );
    }

    return MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      theme: widget.theme ?? _defaultTheme,
      home: SplashModeScreen(
        trueScreenBuilder: widget.liveScreenBuilder,
        appScreenBuilder: widget.appScreenBuilder,
        splashScreenBuilder: widget.splashScreenBuilder,
        launchCoordinator: widget.launchCoordinator,
        initialFlowDelay: widget.initialFlowDelay,
        // Swap cây ở root khi mode đổi (xem doc [BootShell]).
        onModeChanged: _onModeChanged,
      ),
    );
  }
}

/// Popup hiện ra khi check NỀN đã tải + verify + lưu disk xong bản mới VÀ
/// ver hiện tại < `min_force_update` của manifest (ép restart) — chỉ còn
/// quyết định "chạy bản mới ngay hay để lần sau".
///
/// * **OK** → chạy bản mới ngay:
///   * **Android**: `Restart.restartApp()` — relaunch activity + engine mới.
///     Isolate mới → boot flow → fast path nạp bytecode mới từ disk → live
///     với version mới.
///   * **iOS**: `exit(0)` — TẮT app (KHÔNG dùng engine restart nên KHÔNG cần
///     cấu hình native trong AppDelegate nữa). User mở lại app → fast path
///     nạp bytecode mới từ disk.
/// * **Cancel** → đóng popup, giữ nguyên phiên đang chạy version cũ — bản
///   mới tự áp ở lần mở app sau.
///
/// Restart lỗi (MISSING_PLUGIN khi dev hot-reload…) → hiện dòng lỗi trong
/// popup, KHÔNG nuốt — user chọn lại được (chỉ nhánh Android).
class _ModuleUpdateReadyDialog extends StatefulWidget {
  const _ModuleUpdateReadyDialog({
    required this.version,
    required this.theme,
    required this.onLater,
  });

  /// Version mới đã tải xong (hiển thị trong copy).
  final int version;

  final ThemeData theme;

  /// Cancel — đóng popup, KHÔNG restart.
  final VoidCallback onLater;

  @override
  State<_ModuleUpdateReadyDialog> createState() =>
      _ModuleUpdateReadyDialogState();
}

class _ModuleUpdateReadyDialogState extends State<_ModuleUpdateReadyDialog> {
  bool _restarting = false;
  String? _error;

  Future<void> _executeRestart() async {
    if (_restarting) {
      return;
    }
    setState(() {
      _restarting = true;
      _error = null;
    });
    // State đã persist + file cache đã ghi xong TRƯỚC khi gọi → tắt app /
    // restart lỗi giữa chừng không mất gì (lần mở sau vẫn nạp được bản mới
    // từ disk).
    if (Platform.isIOS) {
      // iOS: KHÔNG dùng engine restart (đã bỏ cấu hình native trong
      // AppDelegate) → tắt app luôn; user mở lại app là fast path nạp
      // bytecode mới từ disk.
      // ignore: avoid_print
      // print('[BootShell] iOS: tat app de ap module v${widget.version}');
      exit(0); // Never returns → không cần return phía sau.
    }
    final RestartResult result = await Restart.restartApp();
    if (!mounted) {
      return;
    }
    if (!result.success) {
      // ignore: avoid_print
      // print('[BootShell] restart loi (${result.code}): ${result.message}');
      setState(() {
        _restarting = false;
        _error = result.message ??
            RemoteTexts.current.restartError(result.code) ??
            '${result.code}';
      });
    }
    // Thành công → isolate cũ dừng, không cần setState tiếp.
  }

  @override
  Widget build(BuildContext context) {
    final RemoteTexts texts = RemoteTexts.current;
    final String? title = texts.restartTitle;
    final String? message = texts.restartMessage(
      isIOS: Platform.isIOS,
      version: widget.version,
    );
    final String? cancel = texts.restartCancel;
    final String? ok = texts.restartOk;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: widget.theme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            // Chặn tap xuyên qua root; KHÔNG dismiss (tránh lỡ tay khi
            // restart đang chạy) — chọn rõ bằng 2 nút.
            const ModalBarrier(dismissible: false, color: Colors.black54),
            Center(
              child: AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: title == null
                    ? null
                    : Text(
                        title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (message != null)
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: _restarting ? null : widget.onLater,
                    child: cancel != null
                        ? Text(cancel)
                        : const Icon(Icons.close),
                  ),
                  TextButton(
                    onPressed: _restarting ? null : _executeRestart,
                    child: _restarting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ok != null
                        ? Text(ok)
                        : const Icon(Icons.restart_alt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popup cập nhật APP (manifest `action` soft/force) xuất hiện SAU khi đã vào
/// live (check nền đọc lại manifest, hoặc soft lúc boot). Cùng kiểu overlay
/// SIBLING với [_ModuleUpdateReadyDialog]: tự dựng MaterialApp riêng, KHÔNG
/// lồng vào MaterialApp của module (flutter/flutter#142585).
///
/// * [onLater] null → FORCE: barrier không dismiss, không có nút đóng, back
///   không pop — user chỉ còn cách mở store.
/// * [onLater] khác null → SOFT: thêm nút "Để sau".
class _UpdatePromptOverlay extends StatelessWidget {
  const _UpdatePromptOverlay({
    required this.link,
    required this.theme,
    this.onLater,
    this.onOpened,
  });

  final ForceUpdateLink link;
  final ThemeData theme;
  final VoidCallback? onLater;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final bool isSoft = onLater != null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: <Widget>[
              // Chặn tap xuyên qua màn live; KHÔNG dismiss bằng tap ngoài —
              // soft chọn rõ bằng nút, force không có lối thoát.
              const ModalBarrier(dismissible: false, color: Colors.black54),
              Center(
                child: UpdatePromptDialog(
                  link: link,
                  updateLabel: isSoft
                      ? RemoteTexts.current.softUpdateButton
                      : null,
                  onLater: onLater,
                  onOpened: onOpened,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme mặc định của shell — chỉ dùng khi main app KHÔNG truyền theme
/// (`mainAppMeta.theme` = null).
final ThemeData _defaultTheme = ThemeData(
  colorSchemeSeed: Colors.indigo,
  useMaterial3: true,
);
