// Test file backup state dynmod (dynmod_state.json): round-trip atomic,
// file hỏng → null, và [DynmodStateStore.merge] 2 nguồn (file + prefs).
import 'dart:io';

import 'package:app/shell/dynmod_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dynmod_state_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DynmodStateStore read/write', () {
    test('round-trip: ghi rồi đọc lại đủ number/hash (atomic)', () async {
      final DynmodStateStore store = DynmodStateStore(dirOverride: tempDir);
      expect(await store.read(), isNull); // chưa có file

      const DynmodState state = (number: 7, hash: 'abc123');
      await store.write(state);
      expect(await store.read(), state);

      // Ghi atomic: file tmp không còn sau khi rename.
      expect(
        File('${tempDir.path}/${DynmodStateStore.kFileName}.tmp').existsSync(),
        isFalse,
      );
    });

    test('file cũ còn field sig (legacy) vẫn đọc được number/hash',
        () async {
      final String path = '${tempDir.path}/${DynmodStateStore.kFileName}';
      final DynmodStateStore store = DynmodStateStore(dirOverride: tempDir);
      File(path)
          .writeAsStringSync('{"number":1,"hash":"h","sig":"legacy-sig"}');

      final DynmodState? read = await store.read();
      expect(read, isNotNull);
      expect(read!.number, 1);
      expect(read.hash, 'h');
    });

    test('file hỏng / sai schema / thiếu field → null (fallback prefs)',
        () async {
      final String path = '${tempDir.path}/${DynmodStateStore.kFileName}';
      final DynmodStateStore store = DynmodStateStore(dirOverride: tempDir);

      File(path).writeAsStringSync('{oops');
      expect(await store.read(), isNull);

      File(path).writeAsStringSync('[1,2,3]');
      expect(await store.read(), isNull);

      File(path).writeAsStringSync('{"number":0,"hash":""}');
      expect(await store.read(), isNull);
    });
  });

  group('DynmodStateStore.merge (gộp file + prefs)', () {
    const DynmodState low = (number: 3, hash: 'old');
    const DynmodState high = (number: 5, hash: 'new');

    test('1 nguồn null → lấy nguồn còn lại; cả 2 null → null', () {
      expect(DynmodStateStore.merge(null, low), low);
      expect(DynmodStateStore.merge(high, null), high);
      expect(DynmodStateStore.merge(null, null), isNull);
    });

    test('file number lớn hơn (prefs bị update store wipe) → file', () {
      expect(DynmodStateStore.merge(high, low), high);
    });

    test('prefs number lớn hơn (file bị mất) → prefs', () {
      expect(DynmodStateStore.merge(low, high), high);
    });

    test('bằng nhau → ưu tiên file (atomic, ghi trước prefs)', () {
      const DynmodState fileV = (number: 5, hash: 'file');
      const DynmodState prefsV = (number: 5, hash: 'prefs');
      expect(DynmodStateStore.merge(fileV, prefsV), fileV);
    });
  });
}