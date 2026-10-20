import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
import 'support/test_texts.dart';

/// Dialog force update: BLOCK (không dismiss), nút mở store, thử fallback URL
/// khi URL chính fail. Dialog soft: thêm "Để sau".
void main() {
  setUp(useTestTexts);
  const ForceUpdateLink liveLink = ForceUpdateLink(
    url: 'market://details?id=com.example.appA1',
    title: kForceUpdateTitle,
    message: kForceUpdateLiveMessage,
  );
  const ForceUpdateLink linkWithFallback = ForceUpdateLink(
    url: 'market://details?id=com.example.appA1',
    fallbackUrls: <String>['market://details?id=com.gamevee.backup'],
    title: kForceUpdateTitle,
    message: kForceUpdateLiveMessage,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required ForceUpdateLink link,
    required Future<bool> Function(String url) launch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () {
              executeShowForceUpdateDialog(
                context,
                link: link,
                launchUrlHandler: launch,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('hiện title + copy "có bản mới" cho app còn trên store', (
    WidgetTester tester,
  ) async {
    await pumpDialog(
      tester,
      link: liveLink,
      launch: (String url) async => true,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(kForceUpdateTitle), findsOneWidget);
    expect(find.text(kForceUpdateLiveMessage), findsOneWidget);
    expect(find.text('Cập nhật ngay'), findsOneWidget);
  });

  testWidgets('force KHÔNG có nút "Để sau"', (WidgetTester tester) async {
    await pumpDialog(
      tester,
      link: liveLink,
      launch: (String url) async => true,
    );
    expect(find.text(kSoftUpdateLaterLabel), findsNothing);
  });

  testWidgets('decision market:// → link có fallback Play https, mở được khi '
      'market fail', (WidgetTester tester) async {
    final ForceUpdateLink link = const UpdateDecision(
      action: UpdateAction.force,
      url: 'market://details?id=com.example.hostD',
    ).toLink()!;
    final List<String> launched = <String>[];
    await pumpDialog(
      tester,
      link: link,
      launch: (String url) async {
        launched.add(url);
        return url.startsWith('https://');
      },
    );
    await tester.tap(find.text(kUpdateNowLabel));
    await tester.pumpAndSettle();
    expect(launched, <String>[
      'market://details?id=com.example.hostD',
      'https://play.google.com/store/apps/details?id=com.example.hostD',
    ]);
    expect(find.textContaining('Không mở được'), findsNothing);
  });

  testWidgets('KHÔNG dismiss được: tap ngoài + back button đều không ăn', (
    WidgetTester tester,
  ) async {
    await pumpDialog(
      tester,
      link: liveLink,
      launch: (String url) async => true,
    );
    // Tap ngoài dialog (barrierDismissible: false).
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Back button Android (PopScope canPop: false).
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('bấm nút → launchUrl đúng URL store (dialog vẫn mở)', (
    WidgetTester tester,
  ) async {
    final List<String> launched = <String>[];
    await pumpDialog(
      tester,
      link: liveLink,
      launch: (String url) async {
        launched.add(url);
        return true;
      },
    );
    await tester.tap(find.text('Cập nhật ngay'));
    await tester.pumpAndSettle();
    expect(launched, <String>['market://details?id=com.example.appA1']);
    // Mở store xong user quay lại app → dialog vẫn blocking tới khi họ cập nhật.
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('URL chính fail → thử fallback (backup URL), không hiện lỗi', (
    WidgetTester tester,
  ) async {
    final List<String> launched = <String>[];
    await pumpDialog(
      tester,
      link: linkWithFallback,
      launch: (String url) async {
        launched.add(url);
        return url.contains('backup');
      },
    );
    await tester.tap(find.text('Cập nhật ngay'));
    await tester.pumpAndSettle();
    expect(launched, <String>[
      'market://details?id=com.example.appA1',
      'market://details?id=com.gamevee.backup',
    ]);
    expect(find.textContaining('Không mở được'), findsNothing);
  });

  testWidgets('tất cả URL fail → hiện dòng lỗi để user bấm lại', (
    WidgetTester tester,
  ) async {
    await pumpDialog(
      tester,
      link: linkWithFallback,
      launch: (String url) async => false,
    );
    await tester.tap(find.text('Cập nhật ngay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không mở được'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  group('soft dialog', () {
    const ForceUpdateLink softLink = ForceUpdateLink(
      url: 'https://apps.apple.com/app/id1234567890',
      title: kForceUpdateTitle,
      message: kSoftUpdateMessage,
    );

    Future<List<bool>> pumpSoft(
      WidgetTester tester, {
      required Future<bool> Function(String url) launch,
    }) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () async {
                results.add(await executeShowSoftUpdateDialog(
                  context,
                  link: softLink,
                  launchUrlHandler: launch,
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('có 2 nút "Cập nhật" + "Để sau"', (WidgetTester tester) async {
      await pumpSoft(tester, launch: (String url) async => true);
      expect(find.text(kSoftUpdateMessage), findsOneWidget);
      expect(find.text(kSoftUpdateNowLabel), findsOneWidget);
      expect(find.text(kSoftUpdateLaterLabel), findsOneWidget);
    });

    testWidgets('"Để sau" → đóng, trả false, không mở store', (
      WidgetTester tester,
    ) async {
      final List<String> launched = <String>[];
      final List<bool> results = await pumpSoft(
        tester,
        launch: (String url) async {
          launched.add(url);
          return true;
        },
      );
      await tester.tap(find.text(kSoftUpdateLaterLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(results, <bool>[false]);
      expect(launched, isEmpty);
    });

    testWidgets('"Cập nhật" mở được store → đóng, trả true', (
      WidgetTester tester,
    ) async {
      final List<bool> results = await pumpSoft(
        tester,
        launch: (String url) async => true,
      );
      await tester.tap(find.text(kSoftUpdateNowLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(results, <bool>[true]);
    });

    testWidgets('"Cập nhật" mở fail → dialog còn + dòng lỗi', (
      WidgetTester tester,
    ) async {
      await pumpSoft(tester, launch: (String url) async => false);
      await tester.tap(find.text(kSoftUpdateNowLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Không mở được'), findsOneWidget);
    });
  });
}
