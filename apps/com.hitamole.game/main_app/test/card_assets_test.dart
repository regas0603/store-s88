import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/game/models/card_icon.dart';

/// Icon nhân vật nạp qua `Image.asset(icon.asset)` — đường dẫn sai hoặc thiếu
/// file chỉ lộ ra lúc con đó trồi lên giữa ván, dưới dạng ô xám. Những test này
/// bắt lỗi đó ngay khi chạy CI.
void main() {
  test('Mỗi CardIcon đều có file PNG thật trong assets/cards/', () {
    final missing = <String>[
      for (final icon in CardIcons.all)
        if (!File(icon.asset).existsSync()) '${icon.id} → ${icon.asset}',
    ];
    expect(missing, isEmpty, reason: 'Thiếu file asset:\n${missing.join('\n')}');
  });

  test('Không có id trùng nhau', () {
    final ids = CardIcons.all.map((icon) => icon.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Mọi chủ đề đều có ít nhất một icon', () {
    for (final category in CardCategory.values) {
      expect(
        CardIcons.byCategory(category),
        isNotEmpty,
        reason: 'Chủ đề $category rỗng — mục Nhân vật sẽ hiện lựa chọn trống',
      );
    }
  });

  test('Không có file thừa trong assets/cards/', () {
    final declared = CardIcons.all.map((icon) => icon.asset).toSet();
    final onDisk = Directory('assets/cards')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => !p.endsWith('.DS_Store'))
        .toSet();
    expect(onDisk.difference(declared), isEmpty,
        reason: 'File không được CardIcons.all khai báo → ship thừa dung lượng');
  });

  testWidgets('Image.asset giải mã được PNG thật', (tester) async {
    final icon = CardIcons.all.first;
    await tester.pumpWidget(
      MaterialApp(home: Image.asset(icon.asset)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
