import 'package:flutter/widgets.dart';

import '../data/settings_controller.dart';
import '../data/stats_repository.dart';
import '../services/sound_service.dart';

/// Cung cấp ba dependency toàn cục cho cả cây widget.
///
/// Ba đối tượng này được tạo một lần trong [runApp] và sống suốt vòng đời app,
/// nên [updateShouldNotify] luôn trả về false: widget nào cần rebuild theo dữ
/// liệu thì tự lắng nghe controller bằng [ListenableBuilder], chứ không rebuild
/// cả cây mỗi lần một tuỳ chọn nhỏ thay đổi.
class AppScope extends InheritedWidget {
  final SettingsController settings;
  final StatsRepository stats;
  final SoundService sound;

  const AppScope({
    required this.settings,
    required this.stats,
    required this.sound,
    required super.child,
    super.key,
  });

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'Không tìm thấy AppScope phía trên context này');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
