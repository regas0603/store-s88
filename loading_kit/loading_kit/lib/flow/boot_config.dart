import 'package:package_info_plus/package_info_plus.dart';

/// Central place for boot-flow remote config. Update values here only.
abstract final class BootConfig {
  BootConfig._();

  /// Base URL của thư mục config trên GitHub.
  static const String kConfigBaseUrl =
      'https://raw.githubusercontent.com/Vulcan-dev-25/configs/main/apps';

  /// Bundle identifier đọc RUNTIME qua package_info_plus:
  /// Android = `applicationId`, iOS = `CFBundleIdentifier`.
  /// Có sẵn ngay khi app khởi động (không cần network).
  static Future<String> loadAppBundleId() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return info.packageName;
  }

  /// URL config per-app: `apps/<bundleId>.json` (trong thư mục `apps/` của
  /// repo configs — KHÔNG còn tiền tố `config_`). File này cung cấp
  /// `api_domain` (endpoint check, nối thẳng bundle id) và `rs_domain`
  /// (host tĩnh chứa `app/manifest/<bundleId>.json` + file `.bytecode`)
  /// (bundleId KHÔNG còn nằm trong JSON — đã encode trong tên file).
  ///
  /// NOTE: api_domain phải TỰ mang dấu phân cách (`?command=` / `/`),
  /// app nối thẳng `'$apiDomain$bundleId'`.
  static String bootConfigUrlFor(String bundleId) =>
      '$kConfigBaseUrl/$bundleId.json';

  /// Ngày phát hành: trước ngày này (máy chưa có cờ boot) → demo.
  ///
  /// Do `tools/dynpub.sh` ghi mỗi lần build host — giữ đúng dạng
  /// `DateTime(y, m, d)` trên 1 dòng.
  static final DateTime appReleaseDate = DateTime(2026, 10, 27);

  /// Non-empty string from [json], else null.
  static String? readString(Map<String, dynamic> json, String key) {
    final dynamic value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  /// Như [readString] nhưng trim và coi chuỗi chỉ có khoảng trắng là null.
  static String? readTrimmedString(Map<String, dynamic> json, String key) {
    final String? value = readString(json, key);
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Int from [json] when value is [int] or [num], else null.
  static int? readOptionalInt(Map<String, dynamic> json, String key) {
    final dynamic value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  /// Parsed `api_domain` từ Git JSON per-app — endpoint check, app nối thẳng
  /// `'$apiDomain$bundleId'`.
  ///
  /// Schema duy nhất: `api_domain`.
  /// KHÔNG check scheme: nhận cả `http://` (test nội bộ) — pass-through.
  /// Thiếu/rỗng/sai kiểu → null (caller mở app demo, fail-open).
  static String? readApiDomain(Map<String, dynamic> json) =>
      readTrimmedString(json, 'api_domain');

  /// Parsed `rs_domain` từ Git JSON per-app — host TĨNH chứa
  /// `app/manifest/<bundleId>.json` + file `.bytecode` (thay server self-host +
  /// `POST /api/v1/modules/check` cũ).
  ///
  /// Fallback schema cũ (config đã deploy chưa kịp đổi):
  /// `update.rs_domain` → `update.api_base_url`.
  ///
  /// KHÔNG check scheme: config có thể là `http://` (test nội bộ) —
  /// giá trị được pass-through nguyên văn, tầng dùng tự quyết định.
  ///
  /// Chỉ nhận giá trị **non-empty sau khi trim**: rỗng / toàn khoảng trắng →
  /// null (không có rs_domain → fail-open vào demo, không crash).
  static String? readRsDomain(Map<String, dynamic> json) {
    final String? direct = readTrimmedString(json, 'rs_domain');
    if (direct != null) {
      return direct;
    }
    final dynamic block = json['update'];
    if (block is! Map<String, dynamic>) {
      return null;
    }
    return readTrimmedString(block, 'rs_domain') ??
        readTrimmedString(block, 'api_base_url');
  }
}
