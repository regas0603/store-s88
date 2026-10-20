import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:loading_kit/flow/boot_step.dart';

/// 6 chấm mờ ở GÓC TRÁI DƯỚI màn loading, tương ứng 6 mốc của [BootStep].
///
/// Thiết kế (rút ra từ ma trận case C1..C12):
/// - **Nhỏ + mờ + không chữ**: màn splash không được lộ nội dung boot
///   (boot/store) — cùng chủ trương với việc đổi tên package thành
///   `loading_kit` để không lộ cơ chế boot.
/// - **Không bao giờ nhấp nháy mãi**: [finished] = true là mọi chấm mờ đều,
///   đứng im. Đây là ràng buộc sống còn — chấm sáng mãi = user force-kill app.
/// - `skipped` vẽ vòng tròn RỖNG để phân biệt "bước này không chạy" (fast path
///   đã mở khoá, không có module mới nên không tải gì) với "đã xong".
///
/// [animate] = false để test widget không rơi vào "Ticker còn sống / pending
/// timer"; khi tắt animation thì chấm active đứng ở mức sáng nhất.
class BootStepDots extends StatefulWidget {
  const BootStepDots({
    super.key,
    this.step = BootStep.init,
    this.state = BootStageState.running,
    this.skipped = const <BootStep>{},
    this.finished = false,
    this.animate = true,
    this.dotSize = 6,
    this.gap = 8,
    this.showDebugLabel = false,
  });

  /// Mốc đang chạy.
  final BootStep step;

  /// [BootStageState.blocked] → chấm active chuyển hổ phách + nhấp nháy chậm.
  final BootStageState state;

  /// Các mốc không chạy thật sự (vòng tròn rỗng).
  final Set<BootStep> skipped;

  /// Luồng đã kết thúc → tắt hết nhấp nháy, các chấm mờ đều.
  final bool finished;

  /// Bật/tắt pulse. Test set false.
  final bool animate;

  final double dotSize;
  final double gap;

  /// Hiện nhãn ngắn (init/config/boot/check/sync/ready) — CHỈ khi
  /// `showDebugLabel && kDebugMode`, release không có chữ nào.
  final bool showDebugLabel;

  /// Key của từng chấm — để widget test chỉ đích danh chấm cần kiểm tra.
  @visibleForTesting
  static Key dotKey(BootStep step) => Key('boot-dot-${step.name}');

  @override
  State<BootStepDots> createState() => _BootStepDotsState();
}

class _BootStepDotsState extends State<BootStepDots>
    with SingleTickerProviderStateMixin {
  static const Duration _runningPulse = Duration(milliseconds: 900);
  static const Duration _blockedPulse = Duration(milliseconds: 1500);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _pulseDuration);
    _syncTicker();
  }

  Duration get _pulseDuration => widget.state == BootStageState.blocked
      ? _blockedPulse
      : _runningPulse;

  /// Chỉ chạy Ticker khi THỰC SỰ cần pulse: đang sáng + được phép animate +
  /// luồng chưa kết thúc. Đảm bảo test không để lại timer treo.
  void _syncTicker() {
    final bool shouldPulse = widget.animate && !widget.finished;
    if (shouldPulse && !_controller.isAnimating) {
      _controller.duration = _pulseDuration;
      _controller.repeat(reverse: true);
    } else if (!shouldPulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(BootStepDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _pulseDuration;
    _syncTicker();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showLabel = widget.showDebugLabel && kDebugMode;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.step.debugLabel,
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 9,
                  height: 1.1,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? _) {
              final double pulse = widget.animate ? _controller.value : 1.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < BootStep.ordered.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == BootStep.ordered.length - 1 ? 0 : widget.gap,
                      ),
                      child: _buildDot(i, pulse),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index, double pulse) {
    final BootStep step = BootStep.ordered[index];
    final BootDotVisual visual = resolveBootDotVisual(
      index: index,
      step: widget.step,
      state: widget.state,
      skipped: widget.skipped,
      finished: widget.finished,
    );

    // Chỉ 2 trạng thái "đang chờ" được pulse — done/pending/faded đứng im,
    // nên mắt user chỉ bị hút vào đúng 1 điểm đang chạy.
    final bool pulsing =
        widget.animate &&
        (visual == BootDotVisual.active || visual == BootDotVisual.blocked);

    final Color color = switch (visual) {
      BootDotVisual.pending => Colors.white24,
      BootDotVisual.done => Colors.white54,
      BootDotVisual.faded => Colors.white12,
      BootDotVisual.skipped => Colors.transparent,
      BootDotVisual.active => Colors.white,
      BootDotVisual.blocked => kBootDotBlockedColor,
    };
    final bool hollow = visual == BootDotVisual.skipped;

    final Widget dot = Container(
      key: BootStepDots.dotKey(step),
      width: widget.dotSize,
      height: widget.dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: hollow ? Border.all(color: Colors.white24, width: 1) : null,
      ),
    );

    if (!pulsing) {
      return dot;
    }
    // Pulse = sáng dần + to dần nhẹ. Dùng Opacity/Transform thay vì tính alpha
    // thủ công (API withOpacity đã deprecated).
    return Transform.scale(
      scale: 1.0 + 0.45 * pulse,
      child: Opacity(opacity: 0.45 + 0.55 * pulse, child: dot),
    );
  }
}

/// Màu chấm khi flow ĐỨNG chờ user (dialog force update / dialog restart
/// BLOCK). Hổ phách — không phải đỏ, vì đây không phải lỗi.
const Color kBootDotBlockedColor = Color(0xFFFFB74D);
