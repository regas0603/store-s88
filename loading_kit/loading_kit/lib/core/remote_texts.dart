// Text hiển thị của host (app/ + loading_kit) — CHỈ lấy từ khối `texts` của
// Git JSON per-app (`configs/apps/<bundleId>.json`), code KHÔNG chứa text
// LẪN tên key.
//
// Tên key trong Git JSON đã được TOKEN-HOÁ: token = fnv1a64("<bundleId>:<index>")
// (xem tools/cmd/gentexts.py — cùng thuật toán). Code tra text bằng SỐ (index
// trong [TK]), tự tính token lúc nạp → binary chỉ có số, không có chuỗi tên key.
// Mỗi app một bundleId → token khác nhau.
//
// Key thiếu / rỗng / sai kiểu → null: widget ẩn chữ, nút bấm hiện icon.
//
// Bản đã resolve (index → text) được cache vào SharedPreferences: màn hiện
// TRƯỚC khi có Git JSON (splash) hoặc KHI tải lỗi (dialog lỗi mạng) dùng bản
// lần trước. Cache là mảng theo index nên restore KHÔNG cần bundleId / hash.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:loading_kit/core/text_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteTexts {
  const RemoteTexts._(this._byIndex);

  /// Resolve khối `texts` (token → value) của app [bundleId] thành mảng theo
  /// index. Token nào khớp → lấy value; thiếu/rỗng/sai kiểu → null.
  factory RemoteTexts.fromTokenJson(Object? raw, String bundleId) {
    final List<String?> byIndex = List<String?>.filled(TK.count, null);
    if (raw is Map) {
      for (int i = 0; i < TK.count; i++) {
        final Object? v = raw[token(bundleId, i)];
        if (v is String && v.isNotEmpty) {
          byIndex[i] = v;
        }
      }
    }
    return RemoteTexts._(byIndex);
  }

  /// Dựng trực tiếp từ mảng index → text. Dùng cho cache + test.
  @visibleForTesting
  factory RemoteTexts.fromIndexed(List<String?> byIndex) {
    final List<String?> fixed = List<String?>.filled(TK.count, null);
    for (int i = 0; i < TK.count && i < byIndex.length; i++) {
      final String? v = byIndex[i];
      if (v != null && v.isNotEmpty) {
        fixed[i] = v;
      }
    }
    return RemoteTexts._(fixed);
  }

  static final RemoteTexts empty =
      RemoteTexts._(List<String?>.filled(TK.count, null));

  static const String kCacheKey = 'remote_texts';

  /// Bản đang dùng — widget đọc [current] lúc build; màn cần đổi ngay khi
  /// tải xong (splash) nghe [notifier].
  static final ValueNotifier<RemoteTexts> notifier =
      ValueNotifier<RemoteTexts>(empty);

  static RemoteTexts get current => notifier.value;

  final List<String?> _byIndex;

  String? get(int index) =>
      (index >= 0 && index < _byIndex.length) ? _byIndex[index] : null;

  String? get loading => get(TK.loading);
  String? get connectionErrorTitle => get(TK.connectionErrorTitle);
  String? get connectionErrorMessage => get(TK.connectionErrorMessage);
  String? get connectionErrorRetry => get(TK.connectionErrorRetry);
  String? get updateTitle => get(TK.updateTitle);
  String? get forceUpdateMessage => get(TK.forceUpdateMessage);
  String? get forceUpdateButton => get(TK.forceUpdateButton);
  String? get softUpdateMessage => get(TK.softUpdateMessage);
  String? get softUpdateButton => get(TK.softUpdateButton);
  String? get softUpdateLater => get(TK.softUpdateLater);
  String? get storeOpenError => get(TK.storeOpenError);
  String? get restartTitle => get(TK.restartTitle);
  String? get restartOk => get(TK.restartOk);
  String? get restartCancel => get(TK.restartCancel);
  String? get liveFallback => get(TK.liveFallback);

  /// `{version}` trong text được thay bằng [version].
  String? restartMessage({required bool isIOS, required int version}) =>
      get(isIOS ? TK.restartMessageIos : TK.restartMessageAndroid)
          ?.replaceAll('{version}', '$version');

  /// `{code}` trong text được thay bằng [code].
  String? restartError(Object? code) =>
      get(TK.restartError)?.replaceAll('{code}', '$code');

  /// FNV-1a 64-bit của `"<bundleId>:<index>"` → 12 hex đầu. PHẢI khớp
  /// `fnv1a_token` trong tools/cmd/gentexts.py.
  static String token(String bundleId, int index) {
    int h = 0xCBF29CE484222325;
    for (final int b in utf8.encode('$bundleId:$index')) {
      h = (h ^ b) * 0x100000001B3; // tràn → wrap mod 2^64 (int 64-bit native).
    }
    final StringBuffer sb = StringBuffer();
    for (int i = 7; i >= 0; i--) {
      sb.write(((h >> (i * 8)) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().substring(0, 12);
  }

  /// Nạp bản cache (gọi sớm nhất có thể — trước runApp). Lỗi → giữ nguyên.
  static Future<void> restoreCached() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(kCacheKey);
      if (raw == null) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        notifier.value = RemoteTexts.fromIndexed(
          decoded.map((Object? e) => e is String ? e : null).toList(),
        );
      }
    } catch (e) {
      // print('[Boot] remoteTexts: đọc cache lỗi error=$e');
      print(e);
    }
  }

  /// Áp bản vừa resolve từ Git JSON + ghi cache (mảng theo index).
  static Future<void> update(RemoteTexts texts) async {
    notifier.value = texts;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCacheKey, jsonEncode(texts._byIndex));
    } catch (e) {
      // print('[Boot] remoteTexts: ghi cache lỗi error=$e');
      print(e);
    }
  }
}
