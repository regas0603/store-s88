import 'package:loading_kit/core/remote_texts.dart';
import 'package:loading_kit/flow/app_launch_coordinator.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:loading_kit/screens/boot_step_dots.dart';
import 'package:loading_kit/update/force_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Màn điều phối boot: splash → (gate) → live/demo.
///
/// Widget này chỉ lo UI + vòng đời (6 chấm, dialog, swap mode); mọi quyết định
/// (đọc config, gate module dynmod + quyết định force/soft theo manifest) nằm trong
/// [AppLaunchCoordinator] — bơm vào qua [launchCoordinator] để test thay được.
class SplashModeScreen extends StatefulWidget {
  const SplashModeScreen({
    super.key,
    required this.trueScreenBuilder,
    required this.appScreenBuilder,
    required this.launchCoordinator,
    this.splashScreenBuilder,
    this.onModeChanged,
    this.initialFlowDelay = const Duration(seconds: 2),
    this.showStepDots = true,
    this.animateStepDots = true,
    this.showStepDotsDebugLabel = false,
  });

  final Widget Function() trueScreenBuilder;
  final Widget Function() appScreenBuilder;

  /// Coordinator điều phối boot flow + gate (force update, module dynmod).
  final AppLaunchCoordinator launchCoordinator;

  /// Tuỳ chỉnh màn hình splash. Nếu null, mặc định dùng [SplashView].
  final Widget Function()? splashScreenBuilder;

  /// Được gọi mỗi khi [AppMode] thay đổi (splash → fake/betting).
  ///
  /// Host dùng callback này để SWAP cây widget ở root: khi vào
  /// [AppMode.live], host render thẳng màn hình betting (vốn tự dựng
  /// `MaterialApp.router` riêng) thay vì để nó nằm LỒNG bên trong `MaterialApp`
  /// của host. Hai `MaterialApp` lồng nhau (đặc biệt `MaterialApp.router` lồng
  /// trong `MaterialApp`) gây màn hình đen sau khi điều hướng
  /// (xem flutter/flutter#142585).
  final ValueChanged<AppMode>? onModeChanged;

  final Duration initialFlowDelay;

  /// Bật/tắt 6 chấm tiến độ boot ở góc trái dưới màn loading.
  /// Tắt = màn loading y hệt như trước khi có tính năng này. Bật thì chấm
  /// vẫn chỉ hiện khi cờ unlock đã mở ([BootStepTracker.isUnlocked]).
  final bool showStepDots;

  /// Tắt pulse (test widget tránh để lại Ticker/pending timer).
  final bool animateStepDots;

  /// Hiện nhãn debug ngắn cạnh dãy chấm — chỉ có tác dụng khi `kDebugMode`.
  final bool showStepDotsDebugLabel;

  @override
  State<SplashModeScreen> createState() => _SplashModeScreenState();
}

class _SplashModeScreenState extends State<SplashModeScreen> {
  AppMode currentMode = AppMode.splash;
  bool isExecutingFlow = false;
  late final AppLaunchCoordinator _launchCoordinator;

  /// 6 chấm tiến độ boot. [SplashModeScreen] sở hữu và dispose; [SplashView]
  /// chỉ nhận GIÁ TRỊ (không nhận Listenable) → dispose an toàn.
  final BootStepTracker _bootTracker = BootStepTracker();

  void _onBootStepsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _bootTracker.removeListener(_onBootStepsChanged);
    _bootTracker.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _launchCoordinator = widget.launchCoordinator;
    // Attach TRƯỚC khi flow bắt đầu: coordinator gọi `advanceTo` suốt flow,
    // thiếu bước attach thì 6 chấm nằm chết ở mốc đầu.
    _launchCoordinator.attachBootStepTracker(_bootTracker);
    _bootTracker.addListener(_onBootStepsChanged);
    executeStartFlowAfterDelay();
  }

  Future<void> executeStartFlowAfterDelay() async {
    await Future<void>.delayed(widget.initialFlowDelay);
    if (!mounted) {
      return;
    }
    if (isExecutingFlow) {
      return;
    }
    isExecutingFlow = true;
    try {
      await _launchCoordinator.executeBootFlowWithUpdateGate(
        onAppModeSet: executeSetMode,
        onConnectionErrorPrompt: executeShowRetryDialog,
        isActive: () => mounted,
        onSyncVisibilityChanged: ({required bool isSyncing}) {
          // Hook cho UI "đang đồng bộ module" (chưa có widget riêng).
          // print('[Boot] sync visible=$isSyncing');
        },
        onForceUpdateRequired: executeHandleForceUpdateRequired,
      );
    } finally {
      isExecutingFlow = false;
    }
  }

  void executeSetMode(AppMode mode) {
    if (!mounted) {
      return;
    }
    // Rời splash = luồng boot kết thúc → bắt buộc tắt mọi pulse. Nếu quên bước
    // này mà host còn vẽ lại SplashView (remount) thì user thấy chấm nhấp nháy
    // mãi và tưởng app treo.
    if (mode != AppMode.splash) {
      _bootTracker.finish();
    }
    setState(() {
      currentMode = mode;
    });
    // Báo host biết mode đã đổi để host có thể swap cây ở root (tránh lồng
    // MaterialApp khi vào main). Gọi SAU setState, ngoài phase build.
    widget.onModeChanged?.call(mode);
  }

  /// Gate force update: gate dynmod tra `manifest.json` ra `action = force`
  /// cho bản build này → show dialog BLOCK (barrier + back đều không dismiss
  /// được) cho tới khi user cập nhật. Coordinator KHÔNG vào live sau đó.
  ///
  /// Quyết định đã chuẩn hoá ở [UpdateDecision.fromManifest]: force thiếu
  /// `url` bị hạ về none (fail-open — tránh kẹt splash không lối thoát), nên
  /// [UpdateDecision.toLink] null chỉ là lưới an toàn.
  Future<void> executeHandleForceUpdateRequired(UpdateDecision decision) async {
    if (!mounted) {
      return;
    }
    final ForceUpdateLink? link = decision.toLink();
    if (link == null) {
      // print('[Boot] force update: không có link → không chặn');
      return;
    }
    // print('[Boot] force update: SHOW dialog (BLOCK) url=${link.url}');
    // Chấm "version" chuyển sang màu hổ phách: flow DỪNG lại chờ user bấm
    // cập nhật — không phải đang tải gì đó.
    _bootTracker.block();
    // BLOCK: await dialog. Dialog không dismiss được → code dưới chỉ chạy khi
    // dialog bị unmount (host remount / edge case); coordinator khi đó về
    // demo (force = không vào live).
    await executeShowForceUpdateDialog(context, link: link);
    if (!mounted) {
      return;
    }
    // print('[Boot] force update: dialog closed (edge case)');
  }

  Future<bool> executeShowRetryDialog() async {
    if (!mounted) {
      return false;
    }
    final bool? shouldRetry = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        // Chưa tải được Git JSON → bản cache lần trước; chưa từng có (lần
        // đầu mở app) → chỉ còn icon.
        final RemoteTexts texts = RemoteTexts.current;
        final String? title = texts.connectionErrorTitle;
        final String? message = texts.connectionErrorMessage;
        final String? retry = texts.connectionErrorRetry;
        return AlertDialog(
          icon: const Icon(Icons.wifi_off),
          title: title == null ? null : Text(title),
          content: message == null ? null : Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: retry != null ? Text(retry) : const Icon(Icons.refresh),
            ),
          ],
        );
      },
    );
    return shouldRetry ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (currentMode == AppMode.demo) {
      return widget.appScreenBuilder();
    }
    if (currentMode == AppMode.live) {
      return widget.trueScreenBuilder();
    }
    // Màn splash custom của host (splashScreenBuilder) KHÔNG kèm 6 chấm — host
    // tự dựng SplashView nếu muốn có chấm.
    return widget.splashScreenBuilder?.call() ??
        SplashView(
          step: _bootTracker.step,
          state: _bootTracker.state,
          skipped: _bootTracker.skipped,
          finished: _bootTracker.isFinished,
          showStepDots: widget.showStepDots && _bootTracker.isUnlocked,
          animate: widget.animateStepDots,
          showDebugLabel: widget.showStepDotsDebugLabel,
        );
  }
}

/// Màn loading hiển thị trong lúc boot flow đang chạy (delay khởi động, fetch
/// config, checkBoot, gate module dynmod).
///
/// Nền ĐEN (`Colors.black`) để lúc mở app không nháy trắng và splash không lộ
/// nội dung gì. Vì nền đen nên status bar phải dùng icon SÁNG
/// ([SystemUiOverlayStyle.light]) — nếu không sẽ vô hình.
///
/// Nhận GIÁ TRỊ tiến độ (không nhận `Listenable`) → widget không giữ tham chiếu
/// tới [BootStepTracker] đã dispose; parent truyền value qua `build`.
class SplashView extends StatelessWidget {
  const SplashView({
    super.key,
    this.step = BootStep.init,
    this.state = BootStageState.running,
    this.skipped = const <BootStep>{},
    this.finished = false,
    this.showStepDots = true,
    this.animate = true,
    this.showDebugLabel = false,
  });

  /// Mốc boot đang chạy → quyết định chấm nào sáng.
  final BootStep step;

  /// [BootStageState.blocked] khi flow đang chờ user (dialog BLOCK).
  final BootStageState state;

  /// Các mốc không chạy thật sự (vòng tròn rỗng).
  final Set<BootStep> skipped;

  /// Luồng đã kết thúc → cả 6 chấm mờ đều, đứng im.
  final bool finished;

  final bool showStepDots;
  final bool animate;
  final bool showDebugLabel;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(color: Colors.white),
                  // Nghe notifier: Git JSON tải xong giữa lúc splash đang
                  // hiện → đổi text ngay. Không có text → chỉ vòng xoay.
                  ValueListenableBuilder<RemoteTexts>(
                    valueListenable: RemoteTexts.notifier,
                    builder: (BuildContext context, RemoteTexts texts, _) {
                      final String? loading = texts.loading;
                      if (loading == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          loading,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (showStepDots)
              Align(
                alignment: Alignment.bottomLeft,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: BootStepDots(
                      step: step,
                      state: state,
                      skipped: skipped,
                      finished: finished,
                      animate: animate,
                      showDebugLabel: showDebugLabel,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
