import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_dynmod_gate.dart';

/// Boot flow rút gọn: vào thẳng `AppMode.live` để test gate dynmod mà không phải
/// dựng lại HTTP/date gate. Nhánh demo thì gate KHÔNG chạy.
class _LiveModeBootFlowCoordinator extends BootFlowCoordinator {
  @override
  Future<void> executeFlow({
    required void Function(AppMode mode) onModeChanged,
    required Future<bool> Function() onConnectionErrorPrompt,
  }) async {
    onModeChanged(AppMode.live);
  }
}

class _DemoModeBootFlowCoordinator extends BootFlowCoordinator {
  @override
  Future<void> executeFlow({
    required void Function(AppMode mode) onModeChanged,
    required Future<bool> Function() onConnectionErrorPrompt,
  }) async {
    onModeChanged(AppMode.demo);
  }
}

/// Chạy [AppLaunchCoordinator.executeBootFlowWithUpdateGate] rồi đợi hết event
/// queue — nhánh live gọi gate bằng `unawaited(...)` nên phải drain.
Future<void> _run(
  AppLaunchCoordinator coordinator, {
  required List<AppMode> modes,
  required List<bool> syncEvents,
  Future<void> Function(UpdateDecision decision)? onForceUpdateRequired,
  bool Function()? isActive,
}) async {
  await coordinator.executeBootFlowWithUpdateGate(
    onAppModeSet: modes.add,
    onConnectionErrorPrompt: () async => false,
    isActive: isActive ?? () => true,
    onSyncVisibilityChanged: ({required bool isSyncing}) =>
        syncEvents.add(isSyncing),
    onForceUpdateRequired:
        onForceUpdateRequired ?? (UpdateDecision decision) async {},
  );
  await pumpEventQueue();
}

const UpdateDecision _force = UpdateDecision(
  action: UpdateAction.force,
  url: 'market://details?id=com.example.hostD',
  targetPatch: 7,
  latest: 14,
);

UpdateDecision _soft(int latest) => UpdateDecision(
      action: UpdateAction.soft,
      url: 'https://apps.apple.com/app/id1234567890',
      targetPatch: 7,
      latest: latest,
    );

void main() {
  group('gate dynmod — luật "module nạp OK thì live, lỗi thì fail-open demo"', () {
    test('gate loaded=true → onAppModeSet(live)', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true, moduleVersion: 7);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<AppMode> modes = <AppMode>[];
      final List<bool> syncEvents = <bool>[];

      await _run(coordinator, modes: modes, syncEvents: syncEvents);

      expect(modes, <AppMode>[AppMode.splash, AppMode.live]);
      expect(gate.calls, 1);
    });

    test('gate loaded=false (fail-open) → onAppModeSet(demo)', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: false);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<AppMode> modes = <AppMode>[];
      final List<bool> syncEvents = <bool>[];

      await _run(coordinator, modes: modes, syncEvents: syncEvents);

      expect(modes, <AppMode>[AppMode.splash, AppMode.demo]);
      expect(gate.calls, 1);
    });

    test('đồng bộ hiện rồi tắt quanh gate (true → false)', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<bool> syncEvents = <bool>[];

      await _run(
        coordinator,
        modes: <AppMode>[],
        syncEvents: syncEvents,
      );

      expect(syncEvents.first, isTrue);
      expect(syncEvents.last, isFalse);
    });

    test('nhánh demo (status != 0 / lỗi mạng) → KHÔNG chạy gate dynmod',
        () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _DemoModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<AppMode> modes = <AppMode>[];
      int forceGateCalls = 0;

      await _run(
        coordinator,
        modes: modes,
        syncEvents: <bool>[],
        onForceUpdateRequired: (UpdateDecision decision) async {
          forceGateCalls++;
        },
      );

      expect(modes, <AppMode>[AppMode.demo]);
      expect(gate.calls, 0);
      expect(forceGateCalls, 0);
    });

    test('gate trả FORCE → gọi handler force, KHÔNG vào live, không check nền',
        () async {
      final List<UpdateDecision> forced = <UpdateDecision>[];
      final FakeDynmodGate gate = FakeDynmodGate(
        loaded: true,
        decision: _force,
      );
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<AppMode> modes = <AppMode>[];

      await _run(
        coordinator,
        modes: modes,
        syncEvents: <bool>[],
        onForceUpdateRequired: (UpdateDecision d) async => forced.add(d),
      );

      expect(forced, <UpdateDecision>[_force]);
      expect(modes, isNot(contains(AppMode.live)));
      // Handler trả về (dialog bị gỡ — edge case) → về demo, không kẹt splash.
      expect(modes.last, AppMode.demo);
      expect(gate.backgroundCalls, 0);
    });

    test('gate không force → KHÔNG gọi handler force', () async {
      int forceCalls = 0;
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(loaded: true, decision: _soft(14)),
      );

      await _run(
        coordinator,
        modes: <AppMode>[],
        syncEvents: <bool>[],
        onForceUpdateRequired: (UpdateDecision d) async => forceCalls++,
      );

      expect(forceCalls, 0);
    });

    test('isActive()=false (widget đã dispose) → KHÔNG chạy gate', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );

      await _run(
        coordinator,
        modes: <AppMode>[],
        syncEvents: <bool>[],
        isActive: () => false,
      );

      expect(gate.calls, 0);
    });

    test('gate loaded=true → executeBackground chạy nền sau live', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );
      final List<AppMode> modes = <AppMode>[];

      await _run(coordinator, modes: modes, syncEvents: <bool>[]);

      // Check bản mới NỀN chỉ chạy khi đã vào live (gate trả loaded=true).
      expect(modes, contains(AppMode.live));
      expect(gate.backgroundCalls, 1);
    });

    test('gate loaded=false (fail-open) → KHÔNG chạy check nền', () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: false);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(gate.backgroundCalls, 0);
    });

    test('check nền tải xong version mới (restartVersion) → '
        'moduleUpdateReady.value = version',
        () async {
      final FakeDynmodGate gate =
          FakeDynmodGate(loaded: true, backgroundResult: 9);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(gate.backgroundCalls, 1);
      // BootShell nghe notifier này để hiện popup "khởi động lại?".
      expect(coordinator.moduleUpdateReady.value, 9);
    });

    test('check nền không có bản mới (null) → moduleUpdateReady giữ null',
        () async {
      final FakeDynmodGate gate = FakeDynmodGate(loaded: true);
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: gate,
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(coordinator.moduleUpdateReady.value, isNull);
    });
  });

  group('popup soft/force trên màn live (updatePrompt)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('boot loaded + SOFT (chưa từng "Để sau") → updatePrompt = soft',
        () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(loaded: true, decision: _soft(14)),
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(coordinator.updatePrompt.value, _soft(14));
    });

    test('boot loaded=false (demo) + SOFT → KHÔNG popup', () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(loaded: false, decision: _soft(14)),
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(coordinator.updatePrompt.value, isNull);
    });

    test('"Để sau" → tắt popup + ghi prefs; boot sau trong interval → không '
        'hỏi lại; latest tăng → hỏi lại', () async {
      DateTime now = DateTime(2026, 10, 1, 8);
      final SoftPromptStore store = SoftPromptStore(now: () => now);
      AppLaunchCoordinator build(UpdateDecision d) => AppLaunchCoordinator(
            bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
            softPromptStore: store,
            dynmodGate: FakeDynmodGate(loaded: true, decision: d),
          );

      final AppLaunchCoordinator first = build(_soft(14));
      await _run(first, modes: <AppMode>[], syncEvents: <bool>[]);
      expect(first.updatePrompt.value, isNotNull);
      await first.dismissSoftUpdatePrompt();
      expect(first.updatePrompt.value, isNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SoftPromptStore.kDismissedLatestKey), 14);

      now = now.add(const Duration(hours: 2));
      final AppLaunchCoordinator second = build(_soft(14));
      await _run(second, modes: <AppMode>[], syncEvents: <bool>[]);
      expect(second.updatePrompt.value, isNull);

      final AppLaunchCoordinator third = build(_soft(15));
      await _run(third, modes: <AppMode>[], syncEvents: <bool>[]);
      expect(third.updatePrompt.value, _soft(15));

      now = now.add(const Duration(hours: 23));
      final AppLaunchCoordinator fourth = build(_soft(14));
      await _run(fourth, modes: <AppMode>[], syncEvents: <bool>[]);
      expect(fourth.updatePrompt.value, _soft(14));
    });

    test('clearSoftUpdatePrompt (đã mở store) → tắt popup, KHÔNG ghi từ chối',
        () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(loaded: true, decision: _soft(14)),
      );
      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      coordinator.clearSoftUpdatePrompt();

      expect(coordinator.updatePrompt.value, isNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SoftPromptStore.kDismissedLatestKey), isNull);
    });

    test('check nền chuyển sang FORCE → updatePrompt = force (không tắt được)',
        () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(
          loaded: true,
          backgroundDecision: _force,
        ),
      );
      final List<AppMode> modes = <AppMode>[];

      await _run(coordinator, modes: modes, syncEvents: <bool>[]);

      expect(modes.last, AppMode.live);
      expect(coordinator.updatePrompt.value, _force);
      await coordinator.dismissSoftUpdatePrompt();
      coordinator.clearSoftUpdatePrompt();
      expect(coordinator.updatePrompt.value, _force);
    });

    test('check nền ra SOFT → updatePrompt = soft', () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(
          loaded: true,
          backgroundDecision: _soft(14),
        ),
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(coordinator.updatePrompt.value, _soft(14));
    });

    test('check nền không có manifest mới (decision null) → giữ nguyên',
        () async {
      final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
        bootFlowCoordinator: _LiveModeBootFlowCoordinator(),
        dynmodGate: FakeDynmodGate(loaded: true),
      );

      await _run(coordinator, modes: <AppMode>[], syncEvents: <bool>[]);

      expect(coordinator.updatePrompt.value, isNull);
    });
  });
}
