import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/screens/splash_mode_screen.dart';
import 'support/test_texts.dart';

void main() {
  setUp(useTestTexts);
  testWidgets(
    'SplashView: nền đen, spinner/text trắng, status bar icon sáng',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashView()));

      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);

      final CircularProgressIndicator spinner =
          tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, Colors.white);

      // Text giữ nguyên 'Loading...' (app widget test cũng dựa vào text này).
      final Text loadingText = tester.widget<Text>(find.text('Loading...'));
      expect(loadingText.style?.color, Colors.white70);

      // Nền đen → phải ép status bar icon sáng, nếu không icon sẽ vô hình.
      final AnnotatedRegion<SystemUiOverlayStyle> region =
          tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value.statusBarIconBrightness, Brightness.light);
    },
  );
}
