import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/core/text_keys.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_texts.dart';

/// Text TOKEN-HOÁ theo bundleId + `soft_prompt_interval_hours`, CHỈ từ Git JSON.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RemoteTexts.notifier.value = RemoteTexts.empty;
  });

  /// Dựng khối `texts` token-hoá cho [bundleId] từ các cặp index→value.
  Map<String, String> tokenised(String bundleId, Map<int, String> byIndex) {
    return byIndex.map(
      (int i, String v) => MapEntry<String, String>(
        RemoteTexts.token(bundleId, i),
        v,
      ),
    );
  }

  group('fromTokenJson', () {
    const String bundle = 'com.example.app';

    test('token khớp → lấy value; index khác → null', () {
      final RemoteTexts t = RemoteTexts.fromTokenJson(
        tokenised(bundle, <int, String>{TK.softUpdateLater: 'Later'}),
        bundle,
      );
      expect(t.softUpdateLater, 'Later');
      expect(t.loading, isNull);
    });

    test('sai bundleId → token không khớp → tất cả null', () {
      final Map<String, String> json =
          tokenised(bundle, <int, String>{TK.loading: 'X'});
      expect(RemoteTexts.fromTokenJson(json, 'other.bundle').loading, isNull);
    });

    test('value rỗng / sai kiểu → null', () {
      final RemoteTexts t = RemoteTexts.fromTokenJson(
        <String, dynamic>{
          RemoteTexts.token(bundle, TK.loading): '',
          RemoteTexts.token(bundle, TK.restartOk): 123,
        },
        bundle,
      );
      expect(t.loading, isNull);
      expect(t.restartOk, isNull);
    });

    test('thay {version} / {code}', () {
      final RemoteTexts t = RemoteTexts.fromTokenJson(
        tokenised(bundle, <int, String>{
          TK.restartMessageIos: 'v{version} iOS',
          TK.restartError: 'err {code}',
        }),
        bundle,
      );
      expect(t.restartMessage(isIOS: true, version: 7), 'v7 iOS');
      expect(t.restartError('X'), 'err X');
    });
  });

  test('token: trùng thuật toán Python (vector cố định)', () {
    // Khớp fnv1a_token("com.example.app:0") của tools/cmd/gentexts.py.
    expect(RemoteTexts.token('com.example.app', 0), _pyToken0);
  });

  test('update → cache (theo index); restoreCached nạp lại không cần bundleId',
      () async {
    await RemoteTexts.update(useTestTextsValue());
    RemoteTexts.notifier.value = RemoteTexts.empty;
    await RemoteTexts.restoreCached();
    expect(RemoteTexts.current.loading, 'Loading...');
  });

  testWidgets('không có text: dialog soft vẫn có 2 nút (icon)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdatePromptDialog(
          link: const ForceUpdateLink(url: 'https://x'),
          onLater: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.system_update), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('không có text: splash chỉ có vòng xoay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashView(showStepDots: false)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  group('executeParseBootConfig', () {
    const String bundle = 'com.example.app';

    test('soft_prompt_interval_hours + texts (token-hoá)', () {
      final BootConfigResult r = BootFlowCoordinator().executeParseBootConfig(
        <String, dynamic>{
          'api_domain': 'https://a/?c=',
          'soft_prompt_interval_hours': 6,
          'texts': tokenised(bundle, <int, String>{TK.softUpdateLater: 'Later'}),
        },
        bundleId: bundle,
      );
      expect(r.softPromptIntervalHours, 6);
      expect(r.texts?.softUpdateLater, 'Later');
    });

    test('thiếu soft_prompt_interval_hours → 24', () {
      final BootConfigResult r = BootFlowCoordinator().executeParseBootConfig(
        <String, dynamic>{},
        bundleId: bundle,
      );
      expect(r.softPromptIntervalHours, 24);
      expect(r.texts?.softUpdateLater, isNull);
    });
  });
}

RemoteTexts useTestTextsValue() => RemoteTexts.fromIndexed(testTextValues());

/// fnv1a_token("com.example.app:0") tính bằng tools/cmd/gentexts.py.
const String _pyToken0 = 'a7ca540c8aee';
