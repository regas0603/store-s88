import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_dynmod_gate.dart';
import 'support/test_texts.dart';

/// Gate force update ở [SplashModeScreen] (force đến từ manifest qua gate):
/// - gate trả decision force → dialog BLOCK, KHÔNG vào app thật;
/// - gate không force → đi tiếp vào live;
/// - nhánh demo (status != 0 / lỗi mạng) → KHÔNG chạy gate.
/// Boot flow "đi thẳng vào demo" (fake step 2/3/4 fail) — dùng để test nhánh
/// demo KHÔNG chạy gate force update mà không cần dựng lại HTTP/date gate.
class _DemoModeBootFlowCoordinator extends BootFlowCoordinator {
  @override
  Future<void> executeFlow({
    required void Function(AppMode mode) onModeChanged,
    required Future<bool> Function() onConnectionErrorPrompt,
  }) async {
    onModeChanged(AppMode.demo);
  }
}

void main() {
  setUp(useTestTexts);
  void mockPlatform() {
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'com.example.appA1',
      version: '1.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
    // Flag đã set từ session trước → vào thẳng nhánh live rồi chạy gate.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boot_flow_flag': true,
    });
  }

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

  /// initial delay 2s + fast-path fetch fail.
  Future<void> pumpThroughBootFlow(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2, milliseconds: 100));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
  }

  const UpdateDecision force = UpdateDecision(
    action: UpdateAction.force,
    url: 'market://details?id=com.example.hostD',
    targetPatch: 7,
    latest: 14,
  );

  testWidgets('gate trả FORCE → dialog BLOCK, KHÔNG vào app thật', (
    WidgetTester tester,
  ) async {
    mockPlatform();
    final FakeDynmodGate gate = FakeDynmodGate(loaded: true, decision: force);
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: gate,
    );

    await pumpSplash(tester, coordinator: coordinator);
    await pumpThroughBootFlow(tester);

    expect(gate.calls, 1);
    expect(find.text(kForceUpdateTitle), findsOneWidget);
    expect(find.text(kForceUpdateLiveMessage), findsOneWidget);
    expect(find.text(kSoftUpdateLaterLabel), findsNothing);
    expect(find.text('LIVE SCREEN'), findsNothing);
    expect(find.text('APP SCREEN'), findsNothing);
  });

  testWidgets('gate không force → đi tiếp vào live (không popup)', (
    WidgetTester tester,
  ) async {
    mockPlatform();
    final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: gate,
    );

    await pumpSplash(tester, coordinator: coordinator);
    await pumpThroughBootFlow(tester);

    expect(gate.calls, 1);
    expect(find.text(kForceUpdateTitle), findsNothing);
    expect(find.text('LIVE SCREEN'), findsOneWidget);
  });

  test('nhánh demo (status != 0 / lỗi mạng) → KHÔNG chạy gate', () async {
    final FakeDynmodGate gate = FakeDynmodGate(loaded: true, decision: force);
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      bootFlowCoordinator: _DemoModeBootFlowCoordinator(),
      dynmodGate: gate,
    );
    final List<AppMode> modes = <AppMode>[];
    int forceGateCalls = 0;

    await coordinator.executeBootFlowWithUpdateGate(
      onAppModeSet: modes.add,
      onConnectionErrorPrompt: () async => false,
      isActive: () => true,
      onSyncVisibilityChanged: ({required bool isSyncing}) {},
      onForceUpdateRequired: (UpdateDecision d) async {
        forceGateCalls++;
      },
    );

    expect(modes, <AppMode>[AppMode.demo]);
    expect(forceGateCalls, 0);
    expect(gate.calls, 0);
  });
}
