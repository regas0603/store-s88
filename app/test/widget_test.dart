import 'package:app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/app_launch_coordinator.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/dynmod_gate.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_texts.dart';

/// Fake [DynmodGate] — máy dev/test không có engine `ddm` nên không thể chạy
/// gate thật (`loadModuleFromBytes` ném `UnsupportedError`).
class _FakeDynmodGate implements DynmodGate {
  _FakeDynmodGate({
    required this.loaded,
    this.backgroundVersion,
    this.backgroundDecision,
    this.backgroundDelay,
  });

  /// true = mô phỏng "module nạp + verify OK" → vào live.
  final bool loaded;

  /// Version trả về từ executeBackground (null = không có bản mới) — mô phỏng
  /// check nền tải xong để BootShell hiện popup restart.
  final int? backgroundVersion;

  /// Quyết định manifest đọc lại ở check nền (soft/force → popup trên live).
  final UpdateDecision? backgroundDecision;

  /// Trì hoãn kết quả nền — mô phỏng tải mạng thật (vài trăm ms → xong SAU
  /// khi splash đã bị unmount, đúng timing app thật).
  final Duration? backgroundDelay;

  @override
  Future<DynmodGateResult> execute({
    required String? rsDomain,
    required bool Function() isActive,
    required void Function({required bool isSyncing}) onSyncVisibilityChanged,
    required BootStepTracker? tracker,
  }) async {
    if (loaded) {
      tracker?.advanceTo(BootStep.download);
      tracker?.advanceTo(BootStep.apply);
    } else {
      tracker?.markSkipped(BootStep.download);
      tracker?.markSkipped(BootStep.apply);
    }
    return (
      loaded: loaded,
      moduleVersion: loaded ? 1 : 0,
      decision: UpdateDecision.none,
    );
  }

  @override
  Future<DynmodBackgroundResult> executeBackground({
    required String? rsDomain,
    required bool Function() isActive,
  }) async {
    final Duration? delay = backgroundDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return (restartVersion: backgroundVersion, decision: backgroundDecision);
  }
}

void main() {
  setUp(useTestTexts);
  void mockPlatform({required bool bootFlag}) {
    // Bundle id runtime (Android applicationId / iOS CFBundleIdentifier)
    // cần mock channel cho môi trường test.
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'com.example.appA1',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (bootFlag) 'boot_flow_flag': true,
    });
  }

  /// Qua initial delay 2s + fast-path fetch fail.
  Future<void> pumpBootFlow(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2, milliseconds: 100));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets(
    'flag=true + module nạp OK → TrueScreen (live)',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: _FakeDynmodGate(loaded: true),
      );

      await tester.pumpWidget(TempApp(launchCoordinator: coordinator));
      expect(find.text('Loading...'), findsOneWidget);

      await pumpBootFlow(tester);

      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Weather'), findsNothing);
    },
  );

  testWidgets(
    'flag=true + KHÔNG có module (server module lỗi) → MainAppScreen, không live',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: _FakeDynmodGate(loaded: false),
      );

      await tester.pumpWidget(TempApp(launchCoordinator: coordinator));
      expect(find.text('Loading...'), findsOneWidget);

      await pumpBootFlow(tester);

      // Chưa nạp được module nào → KHÔNG mở app thật, hiện MainAppScreen.
      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
      expect(find.text('Loading...'), findsNothing);
    },
  );

  testWidgets(
    'check nền tải xong bản mới → popup OK/Cancel; Cancel → tắt popup, vẫn live',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: _FakeDynmodGate(
          loaded: true,
          backgroundVersion: 2,
          // Trì hoãn để kết quả về SAU khi splash đã bị unmount — đúng timing
          // app thật (tải vài trăm ms, splash sống sót qua 1 frame live).
          backgroundDelay: const Duration(milliseconds: 500),
        ),
      );

      await tester.pumpWidget(TempApp(launchCoordinator: coordinator));
      await pumpBootFlow(tester);
      // Check nền chạy unawaited sau khi vào live — pump thêm cho xong.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Popup hiện + copy đủ version + 2 lựa chọn.
      expect(find.text('Cập nhật thành công'), findsOneWidget);
      expect(find.textContaining('v2'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel → popup tắt, phiên vẫn chạy (không restart trong test).
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(find.text('Cập nhật thành công'), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
    },
  );

  testWidgets(
    'check nền ra FORCE → overlay chặn trên màn live, không có "Để sau"',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: _FakeDynmodGate(
          loaded: true,
          backgroundDecision: const UpdateDecision(
            action: UpdateAction.force,
            url: 'market://details?id=com.example.hostD',
            targetPatch: 7,
            latest: 14,
          ),
          backgroundDelay: const Duration(milliseconds: 500),
        ),
      );

      await tester.pumpWidget(TempApp(launchCoordinator: coordinator));
      await pumpBootFlow(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(kForceUpdateTitle), findsOneWidget);
      expect(find.text(kForceUpdateLiveMessage), findsOneWidget);
      expect(find.text(kSoftUpdateLaterLabel), findsNothing);
      // Màn live vẫn nằm dưới (sibling overlay), nhưng bị barrier chặn.
      expect(find.text('Ready'), findsOneWidget);
    },
  );

  testWidgets(
    'check nền ra SOFT → overlay "Cập nhật"/"Để sau"; Để sau → tắt + ghi prefs',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: _FakeDynmodGate(
          loaded: true,
          backgroundDecision: const UpdateDecision(
            action: UpdateAction.soft,
            url: 'https://apps.apple.com/app/id1234567890',
            targetPatch: 7,
            latest: 14,
          ),
          backgroundDelay: const Duration(milliseconds: 500),
        ),
      );

      await tester.pumpWidget(TempApp(launchCoordinator: coordinator));
      await pumpBootFlow(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(kSoftUpdateMessage), findsOneWidget);
      expect(find.text(kSoftUpdateNowLabel), findsOneWidget);
      expect(find.text(kSoftUpdateLaterLabel), findsOneWidget);

      await tester.tap(find.text(kSoftUpdateLaterLabel));
      await tester.pump();
      await tester.pump();

      expect(find.text(kSoftUpdateMessage), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('update_soft_dismissed_latest'), 14);
    },
  );

  testWidgets(
    'chưa boot + mạng lỗi → mở MainAppScreen (không kẹt splash, không retry)',
    (WidgetTester tester) async {
      mockPlatform(bootFlag: false);
      await tester.pumpWidget(const TempApp());
      expect(find.text('Loading...'), findsOneWidget);

      // Qua initial delay 2s để flow bắt đầu.
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));

      // Step 3 fail 1 lần (timeout 20s, KHÔNG retry, KHÔNG dialog) → demo.
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(find.text('Lỗi Internet'), findsNothing);

      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('Loading...'), findsNothing);
    },
  );
}
