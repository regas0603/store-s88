// File backup cho cờ boot (bản sao song song SharedPreferences).
//
// SharedPreferences sống sót qua store update BÌNH THƯỜNG, nhưng thực tế đã
// có case mất prefs (restore lệch, cài lại giữ dữ liệu, bug OEM...). Ghi thêm
//1 file JSON nhỏ trong app container để Step1 của BootFlowCoordinator OR 2
// nguồn: chỉ cần 1 trong 2 còn là "đã mở khoá" → không phải boot lại.
//
// Mọi thao tác best-effort: lỗi file → trả null / nuốt exception; prefs vẫn
// là nguồn chính, file chỉ là bản sao cứu hộ.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BootFlagStore {
  BootFlagStore({this.dirOverride});

  static const String kFileName = 'boot_flag.json';

  /// Test inject thư mục tạm; null = app support dir (platform).
  final Directory? dirOverride;

  /// true nếu file nói đã mở khoá; null nếu file thiếu/hỏng
  /// (caller fallback SharedPreferences — không tự quyết thay prefs).
  Future<bool?> readFlag() async {
    try {
      final Directory? dir = await _dir();
      if (dir == null) return null;
      final File file = File('${dir.path}/$kFileName');
      if (!await file.exists()) return null;
      final dynamic json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return json['flag'] == true;
    } catch (_) {
      return null;
    }
  }

  /// Ghi cờ=true atomic (tmp → rename). Lỗi → in log, bỏ qua (best-effort).
  Future<void> writeFlagTrue() async {
    try {
      final Directory? dir = await _dir();
      if (dir == null) return;
      final File tmp = File('${dir.path}/$kFileName.tmp');
      await tmp.writeAsString(
        jsonEncode({'flag': true, 'at': DateTime.now().toIso8601String()}),
        flush: true,
      );
      await tmp.rename('${dir.path}/$kFileName');
    } catch (e) {
      // print('[BootFlagStore] khong ghi duoc file backup: $e');
      print(e);
    }
  }

  Future<Directory?> _dir() async {
    if (dirOverride != null) return dirOverride;
    // flutter test KHÔNG có handler path_provider → future treo mãi (không
    // throw) → trong test tắt file layer, prefs vẫn là nguồn chính.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }
}