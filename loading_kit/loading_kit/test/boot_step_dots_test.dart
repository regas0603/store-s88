import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/screens/boot_step_dots.dart';

/// Widget test cho 6 chấm trên màn loading.
///
/// Nguyên tắc: kiểm tra qua KEY từng chấm ([BootStepDots.dotKey]) + thuộc tính
/// vẽ thật (màu / viền / có pulse hay không) thay vì so ảnh, và luôn cây test
/// tối giản (không [MaterialApp]) để `hasScheduledFrame` chỉ phản ánh Ticker
/// của chính bộ chấm.
void main() {
  Future<void> pumpDots(
    WidgetTester tester, {
    BootStep step = BootStep.init,
    BootStageState state = BootStageState.running,
    Set<BootStep> skipped = const <BootStep>{},
    bool finished = false,
    bool animate = false,
    double dotSize = 6,
    double gap = 8,
    bool showDebugLabel = false,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BootStepDots(
          step: step,
          state: state,
          skipped: skipped,
          finished: finished,
          animate: animate,
          dotSize: dotSize,
          gap: gap,
          showDebugLabel: showDebugLabel,
        ),
      ),
    );
    await tester.pump();
  }

  BoxDecoration deco(WidgetTester tester, BootStep step) =>
      (tester.widget<Container>(find.byKey(BootStepDots.dotKey(step)))
              .decoration!)
          as BoxDecoration;

  bool isPulsing(WidgetTester tester, BootStep step) => find
      .ancestor(
        of: find.byKey(BootStepDots.dotKey(step)),
        matching: find.byType(Transform),
      )
      .evaluate()
      .isNotEmpty;

  group('bố cục & stealth', () {
    testWidgets('đúng 6 chấm, mỗi chấm một key riêng, theo thứ tự enum', (WidgetTester tester) async {
      await pumpDots(tester);
      expect(find.byType(Container), findsNWidgets(BootStep.dotCount));
      for (final BootStep s in BootStep.ordered) {
        expect(find.byKey(BootStepDots.dotKey(s)), findsOneWidget);
      }
    });

    testWidgets('mặc định KHÔNG có chữ nào (release không lộ tên bước)', (WidgetTester tester) async {
      await pumpDots(tester);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('showDebugLabel = false → dù debug build cũng không in nhãn',
        (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version, showDebugLabel: false);
      expect(find.text('check'), findsNothing);
    });

    testWidgets('showDebugLabel = true (debug) → hiện nhãn ngắn của mốc đang chạy',
        (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version, showDebugLabel: true);
      expect(find.text('check'), findsOneWidget);
      expect(find.text('version'), findsNothing);
      expect(find.text('boot'), findsNothing);
    });

    testWidgets('dotSize/gap truyền vào được tôn trọng', (WidgetTester tester) async {
      await pumpDots(tester, dotSize: 10, gap: 3);
      expect(tester.getSize(find.byKey(BootStepDots.dotKey(BootStep.init))),
          const Size(10, 10));

      final Padding gapAfterFirst = tester.widget<Padding>(
        find.ancestor(
          of: find.byKey(BootStepDots.dotKey(BootStep.config)),
          matching: find.byType(Padding),
        ),
      );
      expect(gapAfterFirst.padding, const EdgeInsets.only(right: 3));

      final Padding gapAfterLast = tester.widget<Padding>(
        find.ancestor(
          of: find.byKey(BootStepDots.dotKey(BootStep.apply)),
          matching: find.byType(Padding),
        ),
      );
      expect(gapAfterLast.padding, EdgeInsets.zero);
    });
  });

  group('màu theo trạng thái', () {
    testWidgets('done trắng 54%, active trắng 100%, pending trắng 24%', (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version);
      expect(deco(tester, BootStep.init).color, Colors.white54);
      expect(deco(tester, BootStep.check).color, Colors.white54);
      expect(deco(tester, BootStep.version).color, Colors.white);
      expect(deco(tester, BootStep.download).color, Colors.white24);
      expect(deco(tester, BootStep.apply).color, Colors.white24);
    });

    testWidgets('blocked → chấm hiện tại hổ phách (không phải đỏ = không phải lỗi)',
        (WidgetTester tester) async {
      await pumpDots(
        tester,
        step: BootStep.version,
        state: BootStageState.blocked,
      );
      expect(deco(tester, BootStep.version).color, kBootDotBlockedColor);
      expect(deco(tester, BootStep.init).color, Colors.white54,
          reason: 'mốc đã xong không bị đổi màu theo');
    });

    testWidgets('skipped → vòng tròn RỖNG (fill trong suốt + viền mờ)', (WidgetTester tester) async {
      await pumpDots(
        tester,
        step: BootStep.version,
        skipped: <BootStep>{BootStep.download, BootStep.apply},
      );
      for (final BootStep s in <BootStep>[BootStep.download, BootStep.apply]) {
        final BoxDecoration d = deco(tester, s);
        expect(d.color, Colors.transparent, reason: '${s.name} phải rỗng ruột');
        expect(d.border, isNotNull, reason: '${s.name} phải có viền');
        expect(d.border!.top.color, Colors.white24);
      }
      expect(deco(tester, BootStep.init).border, isNull,
          reason: 'mốc thường không có viền');
    });

    testWidgets('finished → 6 chấm mờ đều white12 (không còn chấm sáng dở)', (WidgetTester tester) async {
      await pumpDots(
        tester,
        step: BootStep.apply,
        skipped: <BootStep>{BootStep.download},
        finished: true,
      );
      for (final BootStep s in BootStep.ordered) {
        expect(deco(tester, s).color, Colors.white12,
            reason: '${s.name} phải mờ đều');
      }
    });
  });

  group('Ticker — ràng buộc sống còn "không nhấp nháy mãi"', () {
    testWidgets('animate = false → đứng im, không hẹn frame (test không treo)',
        (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version, animate: false);
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (final BootStep s in BootStep.ordered) {
        expect(isPulsing(tester, s), isFalse);
      }
    });

    testWidgets('đang chạy → CHỈ chấm active pulse, Ticker hẹn frame', (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version, animate: true);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(
        BootStep.ordered.where((BootStep s) => isPulsing(tester, s)),
        <BootStep>[BootStep.version],
      );
    });

    testWidgets('blocked → chấm blocked pulse, các mốc kia vẫn đứng im', (WidgetTester tester) async {
      await pumpDots(
        tester,
        step: BootStep.version,
        state: BootStageState.blocked,
        animate: true,
      );
      expect(isPulsing(tester, BootStep.version), isTrue);
      expect(isPulsing(tester, BootStep.init), isFalse);
      expect(isPulsing(tester, BootStep.apply), isFalse);
    });

    testWidgets('finished → Ticker dừng hẳn dù animate = true', (WidgetTester tester) async {
      await pumpDots(
        tester,
        step: BootStep.version,
        animate: true,
        finished: true,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (final BootStep s in BootStep.ordered) {
        expect(isPulsing(tester, s), isFalse);
      }
    });

    testWidgets('finished bật giữa luồng → Ticker dừng NGAY, không cần rebuild tree',
        (WidgetTester tester) async {
      await pumpDots(tester, step: BootStep.version, animate: true);
      expect(isPulsing(tester, BootStep.version), isTrue);

      await pumpDots(
        tester,
        step: BootStep.version,
        animate: true,
        finished: true,
      );

      expect(isPulsing(tester, BootStep.version), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
