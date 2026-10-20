// Gate module giữa loading_kit và host.
//
// loading_kit KHÔNG depend loading_kit/dyn_loader (nó kéo theo package
// `dynamic_modules` chỉ tồn tại trên checkout engine ddm). Thay vào đó,
// loading_kit định nghĩa interface này; host (app/) cung implementation
// dùng dyn_loader. Gate chạy TẠI VỊ TRÍ gate update, fail-open về demo khi lỗi.
import 'boot_step.dart';
import 'update_policy.dart';

/// Kết quả 1 lần gate dynmod.
/// `loaded = true`  → entry đã nạp + verify OK → host render nó ở live.
/// `loaded = false` → không có module / lỗi → host về demo (fail-open).
/// `decision` → quyết định cập nhật của bản build này theo manifest
/// ([UpdateDecision.none] khi không có manifest / không có dòng / lỗi).
/// `decision.isForce` → coordinator hiện popup BLOCK, KHÔNG vào live (kể cả
/// khi `loaded = true`).
typedef DynmodGateResult = ({
  bool loaded,
  int moduleVersion,
  UpdateDecision decision,
});

/// Kết quả check NỀN.
/// `restartVersion` → version mới đã tải + persist VÀ cần popup restart
/// (ver hiện tại < `min_force_update` của patch đích); null = không popup.
/// `decision` → quyết định đọc lại từ manifest mới; null = không có manifest
/// mới (lỗi / 404) → giữ nguyên, không popup.
typedef DynmodBackgroundResult = ({
  int? restartVersion,
  UpdateDecision? decision,
});

abstract interface class DynmodGate {
  /// Chạy 1 lần lúc boot: đọc manifest `{rs_domain}/app/manifest/<bundleId>.json`
  /// (bản đã cache nếu có, không thì GET) → tra dòng bản build
  /// (bundleId/platform/buildNumber) → nếu `force` thì trả ngay (không nạp)
  /// → nạp bytecode cache / tải `patches[patch]` → sha256 →
  /// loadModuleFromBytes → đăng ký entry. KHÔNG throw — mọi lỗi (mạng, verify,
  /// engine stock không hỗ trợ) trả về `(loaded: false, ...)` để host về demo.
  ///
  /// `rsDomain` = host TĨNH từ Git JSON per-app (`rs_domain`) chứa
  /// `app/manifest/<bundleId>.json` + file `.bytecode` — không có server API.
  Future<DynmodGateResult> execute({
    required String? rsDomain,
    required bool Function() isActive,
    required void Function({required bool isSyncing})
    onSyncVisibilityChanged,
    required BootStepTracker? tracker,
  });

  /// Giai đoạn 2 — CHẠY NỀN, gọi SAU khi [execute] đã trả `loaded=true` và
  /// host đã vào live: refresh manifest (ETag), tra lại dòng bản build, tải +
  /// verify + LƯU DISK patch đích nếu mới hơn, KHÔNG load vào phiên này (VM
  /// additive-only — bản mới tự áp ở lần mở sau).
  ///
  /// `restartVersion` chỉ khác null khi host cần hiện popup "cập nhật thành
  /// công — khởi động lại?" (ver hiện tại < `min_force_update` của patch
  /// đích). `decision` = quyết định mới (host hiện popup soft/force trên màn
  /// live). Mọi lỗi chỉ log, KHÔNG throw — không block UI, không hiện sync.
  ///
  /// Host gọi bằng `unawaited(...)`; nghe [AppLaunchCoordinator.moduleUpdateReady]
  /// và [AppLaunchCoordinator.updatePrompt].
  Future<DynmodBackgroundResult> executeBackground({
    required String? rsDomain,
    required bool Function() isActive,
  });
}
