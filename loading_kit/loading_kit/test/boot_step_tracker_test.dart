import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_step.dart';

/// Test THUẦN cho bộ đếm 6 chấm: state machine ([BootStepTracker]) + hàm suy
/// ra trạng thái hiển thị ([resolveBootDotVisual]). Không dựng cây widget → chạy
/// nhanh, bao hết ma trận case C1..C12.
void main() {
  group('BootStepTracker — markUnlocked', () {
    test('mặc định chưa unlock (ẩn chấm); markUnlocked → notify 1 lần, '
        'gọi lại không notify', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      int notifications = 0;
      t.addListener(() => notifications++);
      expect(t.isUnlocked, isFalse);

      t.markUnlocked();
      t.markUnlocked();

      expect(t.isUnlocked, isTrue);
      expect(notifications, 1);
    });
  });

  group('BootStepTracker — advanceTo', () {
    test('mặc định dừng ở mốc đầu, chưa skip, chưa finish', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      expect(t.step, BootStep.init);
      expect(t.state, BootStageState.running);
      expect(t.skipped, isEmpty);
      expect(t.isFinished, isFalse);
    });

    test('tiến tới mốc sau → notify 1 lần, state về running', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      int notifications = 0;
      t.addListener(() => notifications++);

      t.advanceTo(BootStep.config);

      expect(t.step, BootStep.config);
      expect(notifications, 1);
    });

    test('nhảy cóc (init → check) vẫn hợp lệ — mốc giữa coi như đã xong', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.advanceTo(BootStep.check);
      expect(t.step, BootStep.check);
    });

    test('gọi lùi hoặc gọi lại chính mốc → ignore (không giật lùi)', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.advanceTo(BootStep.version);
      int notifications = 0;
      t.addListener(() => notifications++);

      t.advanceTo(BootStep.config); // lùi
      t.advanceTo(BootStep.version); // ngang mốc

      expect(t.step, BootStep.version);
      expect(notifications, 0);
    });

    test('báo mốc sau khi finish → ignore (chấm không sáng lại)', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.finish();
      t.advanceTo(BootStep.apply);
      expect(t.step, BootStep.init);
    });

    test('advanceTo tới mốc đang bị skip → xoá cờ skip của mốc đó', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.markSkipped(BootStep.download);
      t.advanceTo(BootStep.download);
      expect(t.skipped, isNot(contains(BootStep.download)));
      expect(t.step, BootStep.download);
    });
  });

  group('BootStepTracker — markSkipped', () {
    test('đánh dấu mốc không chạy → notify, thêm vào skipped', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      int notifications = 0;
      t.addListener(() => notifications++);

      t
        ..markSkipped(BootStep.download)
        ..markSkipped(BootStep.apply);

      expect(t.skipped, <BootStep>{BootStep.download, BootStep.apply});
      expect(notifications, 2);
    });

    test('skip lặp lại cùng một mốc → ignore (không notify thừa)', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.markSkipped(BootStep.apply);
      int notifications = 0;
      t.addListener(() => notifications++);
      t.markSkipped(BootStep.apply);
      expect(notifications, 0);
    });

    test('skip sau khi finish → ignore', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.finish();
      t.markSkipped(BootStep.apply);
      expect(t.skipped, isEmpty);
    });
  });

  group('BootStepTracker — block / resume / finish', () {
    test('block → blocked, resume → running', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.block();
      expect(t.state, BootStageState.blocked);
      t.resume();
      expect(t.state, BootStageState.running);
    });

    test('block KHÔNG đổi mốc đang chạy', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.advanceTo(BootStep.version);
      t.block();
      expect(t.step, BootStep.version);
      expect(t.state, BootStageState.blocked);
    });

    test('block/resume lặp → chỉ notify đúng 1 lần mỗi chiều', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      int notifications = 0;
      t.addListener(() => notifications++);

      t
        ..block()
        ..block()
        ..resume()
        ..resume();

      expect(notifications, 2);
    });

    test('block rồi advanceTo → hết blocked (flow đã đi tiếp)', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.block();
      t.advanceTo(BootStep.config);
      expect(t.state, BootStageState.running);
    });

    test('block/resume sau finish → ignore, finish vẫn thắng', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t.finish();
      t
        ..block()
        ..resume();
      expect(t.state, BootStageState.running);
      expect(t.isFinished, isTrue);
    });

    test('finish → notify đúng 1 lần, gọi lại không notify', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      int notifications = 0;
      t.addListener(() => notifications++);

      t
        ..finish()
        ..finish();

      expect(t.isFinished, isTrue);
      expect(notifications, 1);
    });

    test('finish cắt luôn trạng thái blocked (không còn amber)', () {
      final BootStepTracker t = BootStepTracker();
      addTearDown(t.dispose);
      t
        ..block()
        ..finish();
      expect(t.state, BootStageState.running);
    });
  });

  test('toString đủ dữ liệu để đọc trong console log', () {
    final BootStepTracker t = BootStepTracker();
    addTearDown(t.dispose);
    t
      ..advanceTo(BootStep.version)
      ..block()
      ..markSkipped(BootStep.download);
    final String s = t.toString();
    expect(s, contains('step=version'));
    expect(s, contains('state=blocked'));
    expect(s, contains('download'));
    expect(s, contains('finished=false'));
  });

  group('debugLabel — KHÔNG lộ từ khoá nội bộ', () {
    test('6 mốc, đúng thứ tự hiển thị', () {
      expect(BootStep.dotCount, 6);
      expect(
        BootStep.ordered.map((BootStep s) => s.debugLabel).toList(),
        <String>['init', 'config', 'boot', 'check', 'sync', 'ready'],
      );
    });

    test('không label nào chứa từ khoá nhạy cảm (patch/module...)',
        () {
      final String all = BootStep.ordered
          .map((BootStep s) => s.debugLabel)
          .join(' ')
          .toLowerCase();
      for (final String keyword in <String>[
        'patch',
        'module',
        'download',
        'force',
        'store',
      ]) {
        expect(all, isNot(contains(keyword)), reason: 'lộ từ khoá "$keyword"');
      }
    });
  });

  group('resolveBootDotVisual — ma trận trạng thái 6 chấm', () {
    BootDotVisual resolve({
      required int index,
      BootStep step = BootStep.init,
      BootStageState state = BootStageState.running,
      Set<BootStep> skipped = const <BootStep>{},
      bool finished = false,
    }) => resolveBootDotVisual(
      index: index,
      step: step,
      state: state,
      skipped: skipped,
      finished: finished,
    );

    List<BootDotVisual> row({
      BootStep step = BootStep.init,
      BootStageState state = BootStageState.running,
      Set<BootStep> skipped = const <BootStep>{},
      bool finished = false,
    }) => <BootDotVisual>[
      for (int i = 0; i < BootStep.ordered.length; i++)
        resolve(
          index: i,
          step: step,
          state: state,
          skipped: skipped,
          finished: finished,
        ),
    ];

    const List<BootDotVisual> allFaded = <BootDotVisual>[
      BootDotVisual.faded,
      BootDotVisual.faded,
      BootDotVisual.faded,
      BootDotVisual.faded,
      BootDotVisual.faded,
      BootDotVisual.faded,
    ];

    test('mốc trước → done, mốc sau → pending', () {
      expect(resolve(index: 0, step: BootStep.check), BootDotVisual.done);
      expect(resolve(index: 3, step: BootStep.check), BootDotVisual.pending);
    });

    test('mốc hiện tại → active; state blocked → blocked', () {
      expect(resolve(index: 2, step: BootStep.check), BootDotVisual.active);
      expect(
        resolve(
          index: 2,
          step: BootStep.check,
          state: BootStageState.blocked,
        ),
        BootDotVisual.blocked,
      );
    });

    test('skipped (không phải mốc hiện tại) → vòng tròn rỗng', () {
      expect(
        resolve(index: 4, step: BootStep.version, skipped: {BootStep.download}),
        BootDotVisual.skipped,
      );
      expect(
        resolve(index: 0, step: BootStep.apply, skipped: {BootStep.init}),
        BootDotVisual.skipped,
        reason: 'kể cả mốc đã "đi qua": không chạy thật thì phải vẽ rỗng',
      );
    });

    test('skipped của CHÍNH mốc đang chạy → vòng rỗng THẮNG (không nháy láo)',
        () {
      // Không xảy ra trong flow thật (chỉ skip mốc TƯƠNG LAI), nhưng nếu có thì
      // "không chạy" phải được ưu tiên hơn "đang chạy".
      expect(
        resolve(index: 1, step: BootStep.config, skipped: {BootStep.config}),
        BootDotVisual.skipped,
      );
    });

    test('finished thắng mọi thứ → faded (không bao giờ còn nhấp nháy)', () {
      expect(
        resolve(
          index: 2,
          step: BootStep.check,
          state: BootStageState.blocked,
          skipped: <BootStep>{BootStep.check},
          finished: true,
        ),
        BootDotVisual.faded,
      );
      expect(row(step: BootStep.apply, finished: true), allFaded);
    });

    test('index ngoài phạm vi → không crash', () {
      expect(resolve(index: -1), BootDotVisual.pending);
      expect(resolve(index: BootStep.ordered.length), BootDotVisual.pending);
      expect(resolve(index: 99, finished: true), BootDotVisual.faded);
    });

    test('C1/C9 fast path: 3 mốc done, check active, sync+ready vòng rỗng', () {
      // Cờ boot đã set → init/config/check chạy nhanh, gate báo upToDate nên
      // download + apply không chạy → 2 vòng tròn rỗng.
      expect(
        row(step: BootStep.version, skipped: <BootStep>{
          BootStep.download,
          BootStep.apply,
        }),
        <BootDotVisual>[
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.active,
          BootDotVisual.skipped,
          BootDotVisual.skipped,
        ],
      );
    });

    test('C7 đang tải patch: 4 mốc done, download active, apply pending', () {
      expect(
        row(step: BootStep.download),
        <BootDotVisual>[
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.active,
          BootDotVisual.pending,
        ],
      );
    });

    test('C4 force update: 3 mốc done, check amber, còn lại pending', () {
      expect(
        row(step: BootStep.version, state: BootStageState.blocked),
        <BootDotVisual>[
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.done,
          BootDotVisual.blocked,
          BootDotVisual.pending,
          BootDotVisual.pending,
        ],
      );
    });

    test('C10/C11 hết luồng → 6 chấm faded dù trước đó blocked hay skip', () {
      expect(row(step: BootStep.apply, state: BootStageState.blocked), isNot(allFaded));
      expect(
        row(
          step: BootStep.apply,
          state: BootStageState.blocked,
          skipped: <BootStep>{BootStep.download},
          finished: true,
        ),
        allFaded,
      );
    });
  });
}
