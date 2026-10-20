/// Thông tin build hiển thị ở màn Giới thiệu.
///
/// Cố ý hardcode thay vì dùng `package_info_plus`: chỉ để hiện một dòng chữ mà
/// thêm một plugin native là không đáng. Nhớ sửa cùng lúc với `version` trong
/// pubspec.yaml khi phát hành.
class AppInfo {
  AppInfo._();

  static const String version = '1.0.0';
  static const String buildNumber = '1';

  static String get displayVersion => '$version ($buildNumber)';
}
