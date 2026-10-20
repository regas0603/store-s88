import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_texts.dart';

/// Mô hình quyết định cập nhật (update_policy.dart) + lọc "Để sau" của SOFT.
void main() {
  setUp(useTestTexts);
  group('UpdateAction.parse', () {
    test('soft/force; thiếu / lạ → none', () {
      expect(UpdateAction.parse('soft'), UpdateAction.soft);
      expect(UpdateAction.parse('force'), UpdateAction.force);
      expect(UpdateAction.parse(null), UpdateAction.none);
      expect(UpdateAction.parse('none'), UpdateAction.none);
      expect(UpdateAction.parse('FORCE!'), UpdateAction.none);
    });
  });

  group('UpdateDecision.fromManifest', () {
    test('force + url → giữ nguyên', () {
      final UpdateDecision d = UpdateDecision.fromManifest(
        action: 'force',
        url: ' market://details?id=com.example.hostD ',
        targetPatch: 7,
        latest: 14,
      );
      expect(d.isForce, isTrue);
      expect(d.url, 'market://details?id=com.example.hostD');
      expect(d.targetPatch, 7);
      expect(d.latest, 14);
    });

    test('soft/force thiếu url → hạ về none (fail-open)', () {
      for (final String action in <String>['soft', 'force']) {
        final UpdateDecision d = UpdateDecision.fromManifest(
          action: action,
          url: null,
          targetPatch: 7,
          latest: 14,
        );
        expect(d.action, UpdateAction.none, reason: action);
        expect(d.toLink(), isNull);
      }
    });

    test('none → bỏ url', () {
      final UpdateDecision d = UpdateDecision.fromManifest(
        action: null,
        url: 'https://x',
        targetPatch: 14,
        latest: 14,
      );
      expect(d.action, UpdateAction.none);
      expect(d.url, isNull);
    });
  });

  group('toLink / playHttpsFallback', () {
    test('market:// → thêm fallback https Play', () {
      final ForceUpdateLink link = const UpdateDecision(
        action: UpdateAction.force,
        url: 'market://details?id=com.example.hostD',
      ).toLink()!;
      expect(link.allUrls, <String>[
        'market://details?id=com.example.hostD',
        'https://play.google.com/store/apps/details?id=com.example.hostD',
      ]);
      expect(link.message, kForceUpdateLiveMessage);
    });

    test('https App Store → không fallback; soft dùng copy soft', () {
      final ForceUpdateLink link = const UpdateDecision(
        action: UpdateAction.soft,
        url: 'https://apps.apple.com/app/id1234567890',
      ).toLink()!;
      expect(link.fallbackUrls, isEmpty);
      expect(link.message, kSoftUpdateMessage);
    });

    test('market:// thiếu id → không fallback', () {
      expect(playHttpsFallback('market://details'), isNull);
      expect(playHttpsFallback('https://play.google.com/x'), isNull);
    });

    test('none → null', () {
      expect(UpdateDecision.none.toLink(), isNull);
    });
  });

  group('shouldShowSoftPrompt', () {
    final DateTime t0 = DateTime(2026, 10, 1, 8);
    const UpdateDecision soft14 = UpdateDecision(
      action: UpdateAction.soft,
      url: 'https://x',
      latest: 14,
      softPromptIntervalHours: 24,
    );

    test('không phải soft → false', () {
      expect(
        shouldShowSoftPrompt(
          decision: UpdateDecision.none,
          dismissal: null,
          now: t0,
        ),
        isFalse,
      );
    });

    test('chưa từng từ chối → true', () {
      expect(
        shouldShowSoftPrompt(decision: soft14, dismissal: null, now: t0),
        isTrue,
      );
    });

    test('trong interval, latest không đổi → false; hết interval → true', () {
      final SoftPromptDismissal d = (dismissedLatest: 14, dismissedAt: t0);
      expect(
        shouldShowSoftPrompt(
          decision: soft14,
          dismissal: d,
          now: t0.add(const Duration(hours: 23, minutes: 59)),
        ),
        isFalse,
      );
      expect(
        shouldShowSoftPrompt(
          decision: soft14,
          dismissal: d,
          now: t0.add(const Duration(hours: 24)),
        ),
        isTrue,
      );
    });

    test('latest tăng → true dù còn trong interval', () {
      expect(
        shouldShowSoftPrompt(
          decision: const UpdateDecision(
            action: UpdateAction.soft,
            url: 'https://x',
            latest: 15,
          ),
          dismissal: (dismissedLatest: 14, dismissedAt: t0),
          now: t0.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('interval 0 → luôn hỏi', () {
      expect(
        shouldShowSoftPrompt(
          decision: const UpdateDecision(
            action: UpdateAction.soft,
            url: 'https://x',
            latest: 14,
            softPromptIntervalHours: 0,
          ),
          dismissal: (dismissedLatest: 14, dismissedAt: t0),
          now: t0,
        ),
        isTrue,
      );
    });
  });

  group('SoftPromptStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('recordDismissed → read trả latest + thời điểm (clock inject)',
        () async {
      final DateTime t0 = DateTime(2026, 10, 1, 8);
      DateTime now = t0;
      final SoftPromptStore store = SoftPromptStore(now: () => now);
      const UpdateDecision soft = UpdateDecision(
        action: UpdateAction.soft,
        url: 'https://x',
        latest: 14,
      );

      expect(await store.read(), isNull);
      expect(await store.shouldShow(soft), isTrue);

      await store.recordDismissed(14);
      final SoftPromptDismissal? d = await store.read();
      expect(d!.dismissedLatest, 14);
      expect(d.dismissedAt, t0);
      expect(await store.shouldShow(soft), isFalse);

      now = t0.add(const Duration(hours: 25));
      expect(await store.shouldShow(soft), isTrue);
    });
  });
}
