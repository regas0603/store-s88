// Implementation phía host cho [HostServices] (content_kit v2 — hợp đồng
// đóng băng cùng host, docs/dynmod_build_once_plan.md P3).
//
// Chỉ chứa thứ CHỈ host biết: version host, version module, cấu hình per-app,
// danh sách package host có, báo khoẻ (rollback P6). Module chạy chung isolate
// nên lifecycle / Navigator / package host đã tự dùng trực tiếp.
import 'package:content_kit/content_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'dynmod_health.dart';
import 'host_packages.g.dart';

class AppHostServices implements HostServices {
  AppHostServices._(
    this._health,
    this._moduleHash, {
    required this.hostVersion,
    required this.moduleVersion,
    required this.appConfig,
  });

  /// Tạo khi gate đã nạp module [moduleHash] (đọc version host từ platform).
  static Future<AppHostServices> create({
    required int moduleVersion,
    required String moduleHash,
    required Map<String, Object?> appConfig,
    required DynmodHealth health,
  }) async {
    String hostVersion = '';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      hostVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Không đọc được (test/platform lạ) → để rỗng, module tự xử lý.
    }
    return AppHostServices._(
      health,
      moduleHash,
      hostVersion: hostVersion,
      moduleVersion: moduleVersion,
      appConfig: Map.unmodifiable(appConfig),
    );
  }

  final DynmodHealth _health;
  final String _moduleHash;

  @override
  int get contractVersion => kContentContractVersion;

  @override
  final String hostVersion;

  @override
  final int moduleVersion;

  @override
  final Map<String, Object?> appConfig;

  @override
  Set<String> get capabilities => kHostPackages;

  /// Host v1 chưa có method nào — kênh để dành cho host release sau.
  @override
  Future<Object?> invoke(String method, Map<String, Object?> args) =>
      Future.error(UnsupportedError('host contract v$kContentContractVersion '
          'không hỗ trợ invoke("$method")'));

  @override
  void markHealthy() {
    // print('[DynmodHost] module v$moduleVersion báo khoẻ');
    _health.markHealthy(_moduleHash);
  }

  @override
  void reportError(Object error, StackTrace stack) {
    // print('[DynmodHost] module v$moduleVersion báo lỗi: $error\n$stack');
    print(error);
  }
}
