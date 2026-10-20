// Lưu lần từ chối popup SOFT ("Để sau") vào SharedPreferences — quyết định
// hiện/ẩn nằm ở [shouldShowSoftPrompt] (thuần, update_policy.dart).
import 'package:loading_kit/flow/update_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoftPromptStore {
  SoftPromptStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const String kDismissedLatestKey = 'update_soft_dismissed_latest';
  static const String kDismissedAtKey = 'update_soft_dismissed_at_ms';

  final DateTime Function() _now;

  /// Lần từ chối gần nhất; null = chưa từng / đọc lỗi.
  Future<SoftPromptDismissal?> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? latest = prefs.getInt(kDismissedLatestKey);
      final int? atMs = prefs.getInt(kDismissedAtKey);
      if (latest == null || atMs == null) {
        return null;
      }
      return (
        dismissedLatest: latest,
        dismissedAt: DateTime.fromMillisecondsSinceEpoch(atMs),
      );
    } catch (e) {
      // print('[Boot] softPrompt: đọc prefs lỗi error=$e → coi như chưa từ chối');
      print(e);
      return null;
    }
  }

  /// Ghi "Để sau" cho [latest] tại thời điểm hiện tại. Lỗi → bỏ qua
  /// (lần sau hỏi lại — không hại gì).
  Future<void> recordDismissed(int latest) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kDismissedLatestKey, latest);
      await prefs.setInt(kDismissedAtKey, _now().millisecondsSinceEpoch);
    } catch (e) {
      // print('[Boot] softPrompt: ghi prefs lỗi error=$e');
      print(e);
    }
  }

  /// Đọc lần từ chối rồi hỏi [shouldShowSoftPrompt].
  Future<bool> shouldShow(UpdateDecision decision) async {
    if (!decision.isSoft) {
      return false;
    }
    return shouldShowSoftPrompt(
      decision: decision,
      dismissal: await read(),
      now: _now(),
    );
  }
}
