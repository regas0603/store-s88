// File backup cho trạng thái module dynmod — bản sao song song của 2 key
// SharedPreferences `dynmod_module_version|hash` (cùng nội dung, 2 nguồn).
// Update bản mới từ store từng làm mất prefs → app không còn biết máy đang
// chạy version mấy → verify hash sai. Đọc 2 nguồn rồi [DynmodStateStore.merge]
// (lấy number lớn nhất — state mới nhất, ghi sau khi saveCache xong).
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Trạng thái module đã cài: số version + sha256 hex (chống file hỏng —
/// không còn chữ ký).
typedef DynmodState = ({int number, String hash});

class DynmodStateStore {
  DynmodStateStore({this.dirOverride});

  static const String kFileName = 'dynmod_state.json';

  /// Test inject thư mục tạm; null = app support dir (platform).
  final Directory? dirOverride;

  /// Đọc file; null nếu thiếu/hỏng/thiếu field bắt buộc
  /// (caller fallback SharedPreferences).
  Future<DynmodState?> read() async {
    try {
      final Directory? dir = await _dir();
      if (dir == null) return null;
      final File file = File('${dir.path}/$kFileName');
      if (!await file.exists()) return null;
      final dynamic json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final int number = (json['number'] as num?)?.toInt() ?? 0;
      final String hash = (json['hash'] as String?) ?? '';
      if (number <= 0 || hash.isEmpty) return null;
      return (number: number, hash: hash);
    } catch (_) {
      return null;
    }
  }

  /// Ghi atomic (tmp → rename). Lỗi → in log, bỏ qua (best-effort — prefs vẫn
  /// được ghi nên không mất trạng thái nếu file layer hỏng).
  Future<void> write(DynmodState state) async {
    try {
      final Directory? dir = await _dir();
      if (dir == null) return;
      final File tmp = File('${dir.path}/$kFileName.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'number': state.number,
          'hash': state.hash,
        }),
        flush: true,
      );
      await tmp.rename('${dir.path}/$kFileName');
    } catch (e) {
      // print('[DynmodStateStore] khong ghi duoc file backup: $e');
      print(e);
    }
  }

  /// Gộp 2 nguồn: lấy number lớn nhất (mới nhất). Lý do số lớn nhất an toàn:
  /// `_writeState` ghi file TRƯỚC prefs ngay sau khi `saveCache` xong → khi 2
  /// nguồn lệch nhau thì nguồn number cao hơn luôn là bản đã khớp bytecode
  /// trên đĩa (crash giữa 2 lần ghi → nguồn file đã kịp lưu; prefs bị wipe
  /// bởi update store → file còn). Bằng nhau → ưu tiên file. Cả 2 null → null
  /// (chưa từng cài module).
  static DynmodState? merge(DynmodState? fromFile, DynmodState? fromPrefs) {
    if (fromFile == null) return fromPrefs;
    if (fromPrefs == null) return fromFile;
    return fromFile.number >= fromPrefs.number ? fromFile : fromPrefs;
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