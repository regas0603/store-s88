import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_dynmod_gate.dart';
import 'support/test_texts.dart';

// Test NỐI MẠCH thật: [BootStepTracker] gắn vào [AppLaunchCoordinator] đang
// chạy, rồi ghi lại những gì coordinator báo về — đảm bảo chấm sáng ĐÚNG theo
// step đã chốt, không có step "tự sáng" và không có step bị bỏ sót.
//
// Cách gắn: `SplashModeScreen` tạo + attach tracker nội bộ ngay trong
// initState. Test attach tracker của mình NGAY SAU frame đầu (attach là
// last-write-wins) để theo dõi dòng thông báo mà vẫn đi hết flow thật.

/// Tracker giả để soi dòng thông báo. Chỉ ghi những lần state THỰC SỰ đổi
/// ([BootStepTracker] bỏ qua call thừa mà không notify), nên log phản ánh đúng
/// những gì màn loading vẽ lại.
class _RecordingTracker extends BootStepTracker {
  final List<String> log = <String>[];

  @override
  void advanceTo(BootStep next) {
    final BootStep before = step;
    super.advanceTo(next);
    if (step != before) {
      log.add('advance:${next.name}');
    }
  }

  @override
  void markSkipped(BootStep skippedStep) {
    final bool wasMarked = skipped.contains(skippedStep);
    super.markSkipped(skippedStep);
    if (!wasMarked && skipped.contains(skippedStep)) {
      log.add('skip:${skippedStep.name}');
    }
  }

  @override
  void block() {
    final BootStageState before = state;
    super.block();
    if (state != before) {
      log.add('block');
    }
  }

  @override
  void resume() {
    final BootStageState before = state;
    super.resume();
    if (state != before) {
      log.add('resume');
    }
  }

  @override
  void finish() {
    final bool before = isFinished;
    super.finish();
    if (isFinished != before) {
      log.add('finish');
    }
  }
}

/// Boot flow rút gọn: vào thẳng `AppMode.live` để test gate của coordinator
/// mà không phải dựng lại HTTP/date gate (nhánh demo thì gate không chạy).
class _LiveModeBootFlowCoordinator extends BootFlowCoordinator {
  @override
  Future<void> executeFlow({
    required void Function(AppMode mode) onModeChanged,
    required Future<bool> Function() onConnectionErrorPrompt,
  }) async {
    onModeChanged(AppMode.live);
  }
}

const UpdateDecision _force = UpdateDecision(
  action: UpdateAction.force,
  url: 'market://details?id=com.example.hostD',
  targetPatch: 7,
  latest: 14,
);

void main() {
  setUp(useTestTexts);
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'com.example.appA1',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pumpSplash(
    WidgetTester tester, {
    required AppLaunchCoordinator coordinator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashModeScreen(
          trueScreenBuilder: () =>
              const Scaffold(body: Center(child: Text('LIVE SCREEN'))),
          appScreenBuilder: () =>
              const Scaffold(body: Center(child: Text('APP SCREEN'))),
          launchCoordinator: coordinator,
        ),
      ),
    );
  }

  /// initial delay 2s + fast-path fetch + gate.
  Future<void> pumpThroughBootFlow(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2, milliseconds: 100));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
  }

  BoxDecoration deco(WidgetTester tester, BootStep step) =>
      (tester.widget<Container>(find.byKey(BootStepDots.dotKey(step)))
              .decoration!)
          as BoxDecoration;

  testWidgets(
    'C9 fast path (không có module): config → check → version, '
    'download/apply được SKIP chứ không sáng giả',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'boot_flow_flag': true,
      });
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        dynmodGate: FakeDynmodGate(loaded: false),
      );
      final _RecordingTracker tracker = _RecordingTracker();

      await pumpSplash(tester, coordinator: coordinator);
      coordinator.attachBootStepTracker(tracker);

      await pumpThroughBootFlow(tester);

      expect(tracker.log, <String>[
        'advance:config',
        'advance:check',
        'advance:version',
        'skip:download',
        'skip:apply',
      ]);
      expect(tracker.step, BootStep.version);
      expect(tracker.skipped, <BootStep>{BootStep.download, BootStep.apply});
      // Điều kiện bắt buộc: case này không được báo "đang chờ user".
      expect(tracker.log, isNot(contains('block')));
      // Không có module → fail-open về app "sạch".
      expect(find.text('APP SCREEN'), findsOneWidget);

      tracker.dispose();
    },
  );

  testWidgets('C7/C8 có module mới: thứ tự chấm bắt buộc check → sync → ready', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boot_flow_flag': true,
    });
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: FakeDynmodGate(loaded: true, moduleVersion: 4),
    );
    final _RecordingTracker tracker = _RecordingTracker();

    await pumpSplash(tester, coordinator: coordinator);
    coordinator.attachBootStepTracker(tracker);

    await pumpThroughBootFlow(tester);

    expect(tracker.log, <String>[
      'advance:config',
      'advance:check',
      'advance:version',
      'advance:download',
      'advance:apply',
    ]);
    // Có module mới → vào live, không kẹt splash.
    expect(find.text('LIVE SCREEN'), findsOneWidget);

    tracker.dispose();
  });

  testWidgets('Ràng buộc sống còn: vào live rồi thì 6 chấm BIẾN MẤT và không '
      'còn animation nào hẹn frame (kể cả animate = true mặc định)', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boot_flow_flag': true,
    });
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: FakeDynmodGate(loaded: true),
    );

    await pumpSplash(tester, coordinator: coordinator);
    // Trong lúc boot, pulse còn chạy → còn frame được hẹn.
    await tester.pump(const Duration(seconds: 2, milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('LIVE SCREEN'), findsOneWidget);
    for (final BootStep s in BootStep.ordered) {
      expect(find.byKey(BootStepDots.dotKey(s)), findsNothing,
          reason: '${s.name}: chấm còn sống sau khi rời splash');
    }
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'còn animation chạy = user tưởng app treo');
  });

  testWidgets('force update: dialog chặn → chấm "version" HỔ PHÁCH (block) và '
      'đóng dialog xong thì không còn chấm nào kẹt màu',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boot_flow_flag': true,
    });
    final FakeDynmodGate gate = FakeDynmodGate(loaded: true, decision: _force);
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: gate,
    );

    await pumpSplash(tester, coordinator: coordinator);
    await pumpThroughBootFlow(tester);

    // Dialog force update đang mở và flow đứng yên ở mốc "check".
    expect(gate.calls, 1);
    expect(find.text(kForceUpdateTitle), findsOneWidget);
    expect(find.text('LIVE SCREEN'), findsNothing);
    expect(deco(tester, BootStep.version).color, kBootDotBlockedColor,
        reason: 'app đang chờ user cập nhật mà chấm không hổ phách → user '
            'không biết phải làm gì');
    // Các chấm khác không bị ám hổ phách theo (chỉ mốc đang chạy mới đổi màu).
    expect(deco(tester, BootStep.config).color, isNot(kBootDotBlockedColor));
    expect(deco(tester, BootStep.download).color, isNot(kBootDotBlockedColor));

    // Edge case host tự xử lý: dialog bị gỡ khỏi cây → handler trả về →
    // coordinator gọi `resume()`, chấm hết ám rồi về demo (force = KHÔNG BAO
    // GIỜ vào live).
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('LIVE SCREEN'), findsNothing);
    expect(find.text('APP SCREEN'), findsOneWidget);
    for (final BootStep s in BootStep.ordered) {
      expect(find.byKey(BootStepDots.dotKey(s)), findsNothing);
    }
  });

  test('coordinator: handler force-update block() → sau đó BẮT BUỘC resume() '
      'để chấm không kẹt hổ phách suốt phần gate còn lại', () async {
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
      dynmodGate: FakeDynmodGate(loaded: true, decision: _force),
    );
    final _RecordingTracker tracker = _RecordingTracker();
    coordinator.attachBootStepTracker(tracker);
    final Completer<void> forceGateEntered = Completer<void>();

    await coordinator.executeBootFlowWithUpdateGate(
      onAppModeSet: (AppMode mode) {},
      onConnectionErrorPrompt: () async => false,
      isActive: () => true,
      onSyncVisibilityChanged: ({required bool isSyncing}) {},
      // Mô phỏng đúng [SplashModeScreen]: block() rồi mới trả về.
      onForceUpdateRequired: (UpdateDecision d) async {
        tracker.block();
        forceGateEntered.complete();
      },
    );
    await forceGateEntered.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(tracker.log, contains('block'));
    expect(
      tracker.log.indexOf('resume'),
      greaterThan(tracker.log.indexOf('block')),
      reason: 'thiếu `resume()` → chấm "check" nháy hổ phách tới cuối gate',
    );
    expect(tracker.state, BootStageState.running);

    tracker.dispose();
  });
}

