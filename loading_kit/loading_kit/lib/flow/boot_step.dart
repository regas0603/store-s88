import 'package:flutter/foundation.dart';

/// 6 mốc THẬT của luồng boot — mỗi mốc ánh xạ đúng 1 chấm trên màn loading.
///
/// Không có mốc "trang trí": mỗi giá trị đều tương ứng 1 đoạn code chạy thật
/// (xem [AppLaunchCoordinator] / [BootFlowCoordinator]) để chấm sáng là bằng
/// chứng "app còn đang làm việc", không phải animation giả cho đẹp.
///
/// Thứ tự enum = thứ tự chấm trên màn hình (trái → phải). KHÔNG đổi thứ tự vì
/// [advanceTo] so sánh bằng `index`.
enum BootStep {
  /// Đọc cờ boot local + bundleId + ngày boot (không mạng, ~0ms).
  init,

  /// Fetch `apps/<bundleId>.json` (1 lần, không retry) — api/rs domain (fail-open).
  config,

  /// Check boot: `GET <apiDomain><bundleId>` — `status == 0` → live.
  check,

  /// Phiên bản: đọc `manifest.json` của dynmod + tra dòng bản build
  /// (bundleId/platform/buildNumber) → patch đích + `action` (none/soft/force).
  /// Trả lời "máy này có thiếu bản nào / bị ép cập nhật không".
  version,

  /// Tải module OTA (GET manifest → tải `.bytecode` → verify) — bước
  /// mạng dài nhất, 1s..vài phút.
  download,

  /// Module đã nạp + verify OK trong VM hiện tại (không cần restart).
  apply;

  /// Danh sách chấm theo đúng thứ tự hiển thị.
  static const List<BootStep> ordered = BootStep.values;

  /// Số chấm trên màn loading (= số phần tử enum — tránh magic number 6 rải
  /// khắp nơi; `BootStep.values.length` không dùng được trong const context).
  static int get dotCount => ordered.length;

  /// Nhãn NGỒI CHỪ cho debug. Không bao giờ hiển thị ở release: repo này chủ
  /// đích giấu từ khoá nhạy cảm ("patch"/"module") khỏi UI (key SharedPreferences
  /// đã đổi tên thành `boot_flow_flag`).
  String get debugLabel => switch (this) {
    BootStep.init => 'init',
    BootStep.config => 'config',
    BootStep.check => 'boot',
    BootStep.version => 'check',
    BootStep.download => 'sync',
    BootStep.apply => 'ready',
  };
}

/// Trạng thái của mốc đang chạy — phân biệt "đang làm" với "đứng lại chờ user".
enum BootStageState {
  /// Đang tiến hành → chấm sáng nhấp nháy nhanh.
  running,

  /// Bị chặn chờ hành động của user (dialog force update BLOCK)
  /// → chấm màu hổ phách, nhấp nháy chậm. KHÔNG phải lỗi, nhưng flow không tiến.
  blocked,
}

/// Bộ đếm bước cho màn loading: 1 đối tượng cho 1 lần launch.
///
/// [SplashModeScreen] tạo + listen; [BootFlowCoordinator] và
/// [AppLaunchCoordinator] được [attachBootStepTracker] gắn vào để báo progress.
/// (Gắn bằng method chứ KHÔNG truyền qua tham số `executeFlow` để giữ nguyên
/// chữ ký method đó — các test fake đang override đúng 2 tham số hiện có.)
class BootStepTracker extends ChangeNotifier {
  BootStep _step = BootStep.init;
  BootStageState _state = BootStageState.running;
  bool _finished = false;
  bool _unlocked = false;
  final Set<BootStep> _skipped = <BootStep>{};

  /// Cờ unlock đã mở (đọc được lúc khởi động hoặc vừa ghi sau check boot) —
  /// 6 chấm CHỈ hiện khi true: máy chưa unlock không lộ tiến trình boot.
  bool get isUnlocked => _unlocked;

  /// Báo cờ unlock đã mở → màn loading bắt đầu hiện 6 chấm.
  void markUnlocked() {
    if (_unlocked) {
      return;
    }
    _unlocked = true;
    notifyListeners();
  }

  /// Mốc đang chạy.
  BootStep get step => _step;

  /// [BootStageState.blocked] khi flow đang chờ user (dialog BLOCK).
  BootStageState get state => _state;

  /// Luồng đã kết thúc (vào live/demo/fail-open) → mọi chấm tắt nhấp nháy.
  /// Đây là điều kiện BẮT BUỘC: chấm sáng mãi = user nghĩ app treo.
  bool get isFinished => _finished;

  /// Những mốc KHÔNG chạy thật sự — hiển thị bằng vòng tròn rỗng.
  Set<BootStep> get skipped => _skipped;

  /// Tiến tới mốc [next]. Monotonic: gọi lùi hoặc gọi sau khi [finish] → bỏ qua,
  /// nên code báo progress tha hồ gọi lại nhiều lần mà không giật lùi.
  void advanceTo(BootStep next) {
    if (_finished || next.index <= _step.index) {
      return;
    }
    _skipped.remove(next);
    _step = next;
    _state = BootStageState.running;
    notifyListeners();
  }

  /// Đánh dấu mốc [step] KHÔNG chạy (vd không có module mới nên bỏ luôn bước
  /// download). Dùng cho case C9/C12 — tránh báo "đang tải" giả.
  void markSkipped(BootStep step) {
    if (_finished || _skipped.contains(step)) {
      return;
    }
    _skipped.add(step);
    notifyListeners();
  }

  /// Flow đang chờ user (dialog BLOCK) → chấm đổi màu, nhấp nháy chậm.
  void block() {
    if (_finished || _state == BootStageState.blocked) {
      return;
    }
    _state = BootStageState.blocked;
    notifyListeners();
  }

  /// Bỏ trạng thái chặn (hiếm — dialog đóng mà process còn sống).
  void resume() {
    if (_finished || _state == BootStageState.running) {
      return;
    }
    _state = BootStageState.running;
    notifyListeners();
  }

  /// Luồng kết thúc: KHÔNG giữ chấm nào nhấp nháy nữa, kể cả mốc đang sáng dở.
  void finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    _state = BootStageState.running;
    notifyListeners();
  }

  @override
  String toString() =>
      'BootStepTracker(step=${_step.name}, state=${_state.name}, '
      'skipped=[${_skipped.map((BootStep s) => s.name).join(',')}], '
      'finished=$_finished)';
}

/// Trạng thái hiển thị cuối cùng của 1 chấm, đã suy ra từ [BootStepTracker].
enum BootDotVisual {
  /// Chưa tới (mờ).
  pending,

  /// Đã xong (sáng vừa).
  done,

  /// Bỏ qua thật sự (vòng tròn rỗng, mờ).
  skipped,

  /// Đang chạy (sáng nhất + nhấp nháy).
  active,

  /// Đang chờ user (hổ phách + nhấp nháy chậm).
  blocked,

  /// Luồng đã kết thúc (mờ đều, không nhấp nháy).
  faded,
}

/// Suy ra trạng thái hiển thị cho chấm thứ [index] — tách khỏi widget để test
/// được ma trận trạng thái (C1..C12) mà không cần dựng cây widget.
BootDotVisual resolveBootDotVisual({
  required int index,
  required BootStep step,
  required BootStageState state,
  required Set<BootStep> skipped,
  required bool finished,
}) {
  final BootStep? dotStep = index >= 0 && index < BootStep.ordered.length
      ? BootStep.ordered[index]
      : null;

  // Finish thắng mọi trạng thái khác — đảm bảo không bao giờ còn chấm nhấp nháy
  // sau khi flow đã kết thúc (kể cả nhánh fail-open giữa chừng).
  if (finished) {
    return BootDotVisual.faded;
  }
  // Index ngoài phạm vi 6 chấm (widget thật không bao giờ truyền ra ngoài,
  // giữ cho an toàn nếu gọi tay/test): coi như mốc chưa tới.
  if (dotStep == null) {
    return BootDotVisual.pending;
  }
  // `skipped` kiểm tra TRƯỚC cả mốc hiện tại: đã đánh dấu "không chạy thật"
  // thì vẽ vòng tròn rỗng, không được nhấp nháy như đang chạy.
  if (skipped.contains(dotStep)) {
    return BootDotVisual.skipped;
  }
  if (index < step.index) {
    return BootDotVisual.done;
  }
  if (index == step.index) {
    return state == BootStageState.blocked
        ? BootDotVisual.blocked
        : BootDotVisual.active;
  }
  return BootDotVisual.pending;
}
