// Test file backup cờ boot: đọc/ghi atomic + self-heal 2 nguồn
// (file OR SharedPreferences) của BootFlowCoordinator.executeReadBootFlag.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_flag_store.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('boot_flag_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('BootFlagStore', () {
    test('chưa có file → null; ghi rồi đọc lại → true (atomic)', () async {
      final BootFlagStore store = BootFlagStore(dirOverride: tempDir);
      expect(await store.readFlag(), isNull);

      await store.writeFlagTrue();
      expect(await store.readFlag(), isTrue);
      // Ghi atomic: file tmp không còn sau khi rename.
      expect(
        File('${tempDir.path}/${BootFlagStore.kFileName}.tmp').existsSync(),
        isFalse,
      );
    });

    test('file JSON hỏng → null (caller fallback prefs)', () async {
      File('${tempDir.path}/${BootFlagStore.kFileName}')
          .writeAsStringSync('{not-json');
      expect(await BootFlagStore(dirOverride: tempDir).readFlag(), isNull);
    });

    test('file sai schema (flag không phải true) → false', () async {
      File('${tempDir.path}/${BootFlagStore.kFileName}')
          .writeAsStringSync('{"flag":"yes"}');
      expect(await BootFlagStore(dirOverride: tempDir).readFlag(), isFalse);
    });
  });

  group('BootFlowCoordinator.executeReadBootFlag (OR 2 nguồn)', () {
    test('prefs true → true', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        BootFlowCoordinator.bootFlagKey: true,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BootFlowCoordinator coordinator = BootFlowCoordinator()
        ..flagStore = BootFlagStore(dirOverride: tempDir);

      expect(await coordinator.executeReadBootFlag(prefs), isTrue);
    });

    test('prefs MẤT + file true → true và tự sửa prefs (self-heal)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await BootFlagStore(dirOverride: tempDir).writeFlagTrue();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BootFlowCoordinator coordinator = BootFlowCoordinator()
        ..flagStore = BootFlagStore(dirOverride: tempDir);

      expect(await coordinator.executeReadBootFlag(prefs), isTrue);
      expect(prefs.getBool(BootFlowCoordinator.bootFlagKey), isTrue);
    });

    test('cả 2 nguồn trống → false (phải chạy lại luồng boot như bình thường)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BootFlowCoordinator coordinator = BootFlowCoordinator()
        ..flagStore = BootFlagStore(dirOverride: tempDir);

      expect(await coordinator.executeReadBootFlag(prefs), isFalse);
    });
  });
}