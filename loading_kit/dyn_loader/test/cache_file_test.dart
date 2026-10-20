// Test tên cache `content.bytecode` + migration từ file tên cũ `app_b.bytecode`.
import 'dart:io';
import 'dart:typed_data';

import 'package:dyn_loader/dyn_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late DynModuleLoader loader;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dyn_cache_test');
    loader = DynModuleLoader(
      baseUrl: 'http://localhost',
      cacheDirOverride: tempDir,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('tên cache là content.bytecode (không theo tên app/module)', () async {
    final File file = await loader.cacheFile();
    expect(file.path, endsWith('/content.bytecode'));
    expect(kDynModuleCacheFileName, 'content.bytecode');
    expect(kDynModuleCacheTmpName, 'content.bytecode.tmp');
  });

  test('file cũ app_b.bytecode → migrate sang content.bytecode, giữ bytes',
      () async {
    File('${tempDir.path}/app_b.bytecode').writeAsStringSync('OLD_BYTES');

    final File file = await loader.cacheFile();

    expect(await file.readAsString(), 'OLD_BYTES');
    expect(File('${tempDir.path}/app_b.bytecode').existsSync(), isFalse);
  });

  test('saveCache ghi content.bytecode + dọn file tên cũ', () async {
    File('${tempDir.path}/app_b.bytecode').writeAsStringSync('OLD');

    await loader.saveCache(Uint8List.fromList(<int>[1, 2, 3]));

    expect((await loader.readCache())!.length, 3);
    expect(File('${tempDir.path}/content.bytecode').existsSync(), isTrue);
    expect(File('${tempDir.path}/app_b.bytecode').existsSync(), isFalse);
  });

  test('clearCache xóa cả file tên cũ còn sót', () async {
    File('${tempDir.path}/app_b.bytecode').writeAsStringSync('OLD');

    await loader.clearCache();

    expect(File('${tempDir.path}/app_b.bytecode').existsSync(), isFalse);
    expect(File('${tempDir.path}/content.bytecode').existsSync(), isFalse);
  });

  test('chưa có file gì → trả về path content.bytecode, không lỗi', () async {
    final File file = await loader.cacheFile();
    expect(file.path, endsWith('/content.bytecode'));
    expect(await file.exists(), isFalse);
    expect(await loader.readCache(), isNull);
  });
}