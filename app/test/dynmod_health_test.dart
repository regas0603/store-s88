import 'package:app/shell/dynmod_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('module không báo khoẻ đủ ngưỡng lần mở → bị đánh dấu hỏng', () async {
    final health = DynmodHealth(prefs);
    for (var i = 0; i < DynmodHealth.kMaxUnhealthyBoots; i++) {
      expect(await health.beginBoot('AAA'), isTrue, reason: 'lần mở ${i + 1}');
    }
    expect(await health.beginBoot('AAA'), isFalse);
    expect(health.isBad('aaa'), isTrue, reason: 'so hash không phân biệt hoa/thường');
  });

  test('markHealthy reset bộ đếm → không bao giờ bị đánh dấu hỏng', () async {
    final health = DynmodHealth(prefs);
    for (var i = 0; i < DynmodHealth.kMaxUnhealthyBoots * 2; i++) {
      expect(await health.beginBoot('aaa'), isTrue);
      await health.markHealthy('aaa');
    }
    expect(health.isBad('aaa'), isFalse);
  });

  test('hash mới bắt đầu đếm lại, hash hỏng cũ không chặn hash mới', () async {
    final health = DynmodHealth(prefs);
    await health.markBad('aaa');
    expect(await health.beginBoot('aaa'), isFalse);
    expect(await health.beginBoot('bbb'), isTrue);
    expect(health.isBad('bbb'), isFalse);
  });
}
