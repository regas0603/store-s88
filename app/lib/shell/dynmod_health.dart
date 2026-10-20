// Rollback tự động khi module crash liên tục (docs/dynmod_build_once_plan.md P6).
//
// Mỗi lần mở app, TRƯỚC khi nạp bytecode có hash H: [beginBoot] tăng bộ đếm
// lần mở chưa "khoẻ" của H. Module gọi `HostServices.markHealthy()` khi đã
// chạy ổn → [markHealthy] xoá bộ đếm. Bộ đếm chạm [kMaxUnhealthyBoots] (crash /
// treo / bị kill trước khi kịp báo khoẻ nhiều lần liên tiếp) → H bị đánh dấu
// HỎNG: gate không nạp, không tải lại đúng H — chờ server phát hash khác.
import 'package:shared_preferences/shared_preferences.dart';

class DynmodHealth {
  DynmodHealth(this._prefs);

  final SharedPreferences _prefs;

  /// Số lần mở liên tiếp chưa báo khoẻ thì coi bản module là hỏng. Để 3 (không
  /// phải 2) để user tự tắt app sớm 1 lần không làm hỏng oan bản tốt.
  static const int kMaxUnhealthyBoots = 3;

  static const String _kBootHash = 'dynmod_boot_hash';
  static const String _kBootAttempts = 'dynmod_boot_attempts';
  static const String _kBadHash = 'dynmod_bad_hash';

  /// Hash đã bị đánh dấu hỏng (không nạp / không tải lại).
  bool isBad(String hash) =>
      hash.isNotEmpty && _prefs.getString(_kBadHash) == hash.toLowerCase();

  /// Đánh dấu hỏng ngay (vd. module đòi hợp đồng mới hơn host).
  Future<void> markBad(String hash) async {
    await _prefs.setString(_kBadHash, hash.toLowerCase());
    await _prefs.remove(_kBootAttempts);
  }

  /// Gọi ngay trước khi nạp bytecode [hash]. false = hash hỏng (đã hoặc vừa
  /// chạm ngưỡng) → KHÔNG nạp.
  Future<bool> beginBoot(String hash) async {
    hash = hash.toLowerCase();
    if (isBad(hash)) return false;
    final int attempts =
        _prefs.getString(_kBootHash) == hash ? (_prefs.getInt(_kBootAttempts) ?? 0) : 0;
    if (attempts >= kMaxUnhealthyBoots) {
      await markBad(hash);
      return false;
    }
    await _prefs.setString(_kBootHash, hash);
    await _prefs.setInt(_kBootAttempts, attempts + 1);
    return true;
  }

  /// Module [hash] đã chạy ổn → reset bộ đếm.
  Future<void> markHealthy(String hash) async {
    if (_prefs.getString(_kBootHash) == hash.toLowerCase()) {
      await _prefs.setInt(_kBootAttempts, 0);
    }
  }
}
