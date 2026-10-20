import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/dynmod_gate.dart';
import 'package:loading_kit/flow/soft_prompt_store.dart';
import 'package:loading_kit/flow/update_policy.dart';

/// Runs [BootFlowCoordinator] then blocks entry to [AppMode.live] until the
/// dynmod [DynmodGate] finishes (loaded → live, fail-open → demo, force →
/// popup BLOCK).
final class AppLaunchCoordinator {
  AppLaunchCoordinator({
    BootFlowCoordinator? bootFlowCoordinator,
    SoftPromptStore? softPromptStore,
    required DynmodGate dynmodGate,
  }) : _bootFlowCoordinator = bootFlowCoordinator ?? BootFlowCoordinator(),
       _softPromptStore = softPromptStore ?? SoftPromptStore(),
       _dynmodGate = dynmodGate;

  final DynmodGate _dynmodGate;

  final BootFlowCoordinator _bootFlowCoordinator;
  final SoftPromptStore _softPromptStore;
  bool _isGateRunning = false;

  /// Bộ đếm bước cho 6 chấm màn loading (null = không có UI → no-op).
  BootStepTracker? _stepTracker;

  /// Version module mới đã tải + verify + lưu disk xong trong NỀN
  /// (`null` = chưa có / đã bị dismiss). Gate không có BuildContext nên
  /// [BootShell] (host) nghe notifier này để hiện popup
  /// "cập nhật thành công — khởi động lại?" với lựa chọn OK / Cancel.
  ///
  /// Đã persist state TRƯỚC khi popup hiện → Cancel chỉ hoãn, bản mới tự
  /// áp ở lần mở app sau (fast path đọc cache + verify hash).
  final ValueNotifier<int?> moduleUpdateReady = ValueNotifier<int?>(null);

  /// Popup cập nhật app (soft/force theo manifest) cần hiện TRÊN MÀN LIVE
  /// (`null` = không có). Đặt khi:
  /// * boot vào live với quyết định `soft` (đã qua lọc "Để sau" —
  ///   [shouldShowSoftPrompt]);
  /// * check nền đọc lại manifest ra `soft` / `force`.
  ///
  /// `force` lúc boot KHÔNG đi qua đây — [SplashModeScreen] chặn ngay ở gate.
  /// [BootShell] (root, luôn mounted) nghe notifier này để hiện overlay.
  final ValueNotifier<UpdateDecision?> updatePrompt =
      ValueNotifier<UpdateDecision?>(null);

  /// Gắn [tracker] để gate báo các mốc `version` (manifest), `download`
  /// (đang tải module) và `apply` (module đã sẵn sàng). Forward xuống
  /// [BootFlowCoordinator] để 2 mốc `config`/`check` do boot flow báo.
  ///
  /// Gọi MỘT lần từ UI (State.initState) trước khi chạy flow.
  void attachBootStepTracker(BootStepTracker tracker) {
    _stepTracker = tracker;
    _bootFlowCoordinator.attachBootStepTracker(tracker);
  }

  /// Endpoint check từ Git JSON (`api_domain`) — null = fail-open.
  String? get apiDomain => _bootFlowCoordinator.apiDomain;

  /// Host TĨNH (manifest `app/manifest/<bundleId>.json`) từ Git JSON (null =
  /// fail-open, không check OTA).
  String? get rsDomain => _bootFlowCoordinator.rsDomain;

  /// User bấm "Để sau" ở popup SOFT: ghi `dismissed_latest` + thời điểm (không
  /// hỏi lại trong `soft_prompt_interval_hours` của Git JSON trừ khi `latest`
  /// tăng) rồi tắt
  /// popup. Popup `force` KHÔNG tắt được → no-op.
  Future<void> dismissSoftUpdatePrompt() async {
    final UpdateDecision? current = updatePrompt.value;
    if (current == null || !current.isSoft) {
      return;
    }
    updatePrompt.value = null;
    await _softPromptStore.recordDismissed(current.latest);
  }

  /// User bấm "Cập nhật" ở popup SOFT và store đã mở: tắt popup, KHÔNG ghi
  /// từ chối (chưa cài thì lần mở sau hỏi lại).
  void clearSoftUpdatePrompt() {
    if (updatePrompt.value?.isSoft ?? false) {
      updatePrompt.value = null;
    }
  }

  /// Parameters use [isActive] (typically `mounted`) so no UI runs after dispose.
  ///
  /// Nhánh live: gate dynmod đọc manifest → `force` thì gọi
  /// [onForceUpdateRequired] (dialog BLOCK) và KHÔNG vào live; còn lại nạp
  /// module như cũ. Quyết định force do tool tính sẵn trong manifest
  /// (`block-below` / `force-vc`) — không còn `force_update.min_version_code`.
  Future<void> executeBootFlowWithUpdateGate({
    required void Function(AppMode mode) onAppModeSet,
    required Future<bool> Function() onConnectionErrorPrompt,
    required bool Function() isActive,
    required void Function({required bool isSyncing})
    onSyncVisibilityChanged,
    required Future<void> Function(UpdateDecision decision)
    onForceUpdateRequired,
  }) async {
    await _bootFlowCoordinator.executeFlow(
      onModeChanged: (AppMode mode) {
        if (mode == AppMode.live) {
          unawaited(
            _executeDynmodGateThenContinue(
              onAppModeSet: onAppModeSet,
              isActive: isActive,
              onSyncVisibilityChanged: onSyncVisibilityChanged,
              onForceUpdateRequired: onForceUpdateRequired,
            ),
          );
        } else {
          // demo/reviewer: KHÔNG chạy gate (không manifest, không popup).
          onAppModeSet(mode);
        }
      },
      onConnectionErrorPrompt: onConnectionErrorPrompt,
    );
  }

  Future<void> _executeDynmodGateThenContinue({
    required void Function(AppMode mode) onAppModeSet,
    required bool Function() isActive,
    required void Function({required bool isSyncing})
    onSyncVisibilityChanged,
    required Future<void> Function(UpdateDecision decision)
    onForceUpdateRequired,
  }) async {
    if (_isGateRunning || !isActive()) {
      return;
    }
    _isGateRunning = true;
    bool syncUiActive = false;
    try {
      // Chấm `version` = đọc manifest + tra dòng bản build ("máy này có
      // thiếu bản nào / bị ép cập nhật không").
      _stepTracker?.advanceTo(BootStep.version);

      // Gate dynmod (loading_kit/dyn_loader) — fail-open về demo khi bất kỳ
      // bước nào lỗi (mạng, verify, engine stock không hỗ trợ loadModuleFromBytes).
      // KHÔNG restart: swap màn chỉ là onAppModeSet(live) sau 1 setState.
      // print(
      //   '[Boot] gate start: dynmod (manifest.json) rsDomain='
      //   '${_bootFlowCoordinator.rsDomain ?? '(null - fail-open)'}',
      // );
      syncUiActive = true;
      onSyncVisibilityChanged(isSyncing: true);
      onAppModeSet(AppMode.splash);
      final DynmodGateResult result = await _dynmodGate.execute(
        rsDomain: _bootFlowCoordinator.rsDomain,
        isActive: isActive,
        onSyncVisibilityChanged: onSyncVisibilityChanged,
        tracker: _stepTracker,
      );
      if (!isActive()) {
        return;
      }
      onSyncVisibilityChanged(isSyncing: false);
      syncUiActive = false;

      if (result.decision.isForce) {
        // FORCE: dialog BLOCK (không dismiss được) → flow dừng tại đây,
        // KHÔNG vào live.
        // print('[Boot] gate dynmod: FORCE ${result.decision} → chặn, không live');
        await onForceUpdateRequired(result.decision);
        // Handler có thể trả về MÀ KHÔNG kill process (dialog bị gỡ — edge
        // case). Bỏ amber để chấm không nhấp nháy hổ phách mãi.
        _stepTracker?.resume();
        if (!isActive()) {
          return;
        }
        // Force = KHÔNG BAO GIỜ vào live → về app "sạch" thay vì kẹt splash.
        // print('[Boot] gate dynmod: dialog force đóng (edge case) → demo');
        _stepTracker?.markSkipped(BootStep.download);
        _stepTracker?.markSkipped(BootStep.apply);
        onAppModeSet(AppMode.demo);
        return;
      }

      if (result.loaded) {
        // print('[Boot] gate dynmod: module v${result.moduleVersion} loaded → live '
        //     '(${result.decision})');
        _stepTracker?.advanceTo(BootStep.apply);
        onAppModeSet(AppMode.live);
        // SOFT lúc boot → popup trên màn live (BootShell), không chặn.
        unawaited(_executeOfferSoftPrompt(result.decision));
        // Check bản mới NỀN: refresh manifest + tải về disk để lần mở sau tự
        // áp — KHÔNG block live, KHÔNG load chồng vào phiên này (VM
        // additive-only).
        unawaited(_executeDynmodBackground(isActive: isActive));
      } else {
        // print('[Boot] gate dynmod: khong co module / loi → demo (fail-open)');
        _stepTracker?.markSkipped(BootStep.download);
        _stepTracker?.markSkipped(BootStep.apply);
        onAppModeSet(AppMode.demo);
      }
      return;
    } finally {
      _isGateRunning = false;
      if (syncUiActive && isActive()) {
        onSyncVisibilityChanged(isSyncing: false);
      }
    }
  }

  /// Đặt [updatePrompt] cho quyết định SOFT nếu qua lọc "Để sau". Không đè
  /// popup `force` đang hiện.
  Future<void> _executeOfferSoftPrompt(UpdateDecision soft) async {
    if (!soft.isSoft) {
      return;
    }
    // Interval từ Git JSON per-app (manifest không mang).
    final UpdateDecision decision = soft.withSoftPromptIntervalHours(
      _bootFlowCoordinator.softPromptIntervalHours,
    );
    try {
      if (!await _softPromptStore.shouldShow(decision)) {
        // print('[Boot] softPrompt: đã "Để sau" gần đây (latest=${decision.latest}) '
        //     '→ không hỏi lại');
        return;
      }
      if (updatePrompt.value?.isForce ?? false) {
        return;
      }
      updatePrompt.value = decision;
    } catch (e) {
      // print('[Boot] softPrompt lỗi (bỏ qua): $e');
      print(e);
    }
  }

  /// Check + prefetch bản mới NỀN sau khi đã vào live — chỉ lưu disk, phiên
  /// sau tự áp. Chỉ chạy khi gate trả `loaded=true` (engine hỗ trợ load) —
  /// tránh tải phí khi fail-open. Mọi lỗi nuốt (log): lưới an toàn thứ 2,
  /// gate vốn đã không được throw.
  Future<void> _executeDynmodBackground({
    required bool Function() isActive,
  }) async {
    try {
      final DynmodBackgroundResult bg = await _dynmodGate.executeBackground(
        rsDomain: _bootFlowCoordinator.rsDomain,
        isActive: isActive,
      );
      // KHÔNG chặn bằng isActive(): vào live rồi thì SplashModeScreen đã bị
      // BootShell unmount → isActive() (mounted của splash) LUÔN false →
      // popup sẽ không bao giờ hiện ở app thật (tải nền mất vài giây). Việc
      // hiện/bỏ popup do BootShell (root, luôn mounted) tự lo qua notifier.
      final UpdateDecision? decision = bg.decision;
      if (decision != null && decision.isForce) {
        // Manifest mới chuyển sang FORCE → popup BLOCK trên màn live.
        // print('[Boot] gate dynmod background: FORCE $decision → popup trên live');
        updatePrompt.value = decision;
      } else if (decision != null && decision.isSoft) {
        await _executeOfferSoftPrompt(decision);
      }
      // Version > 0 = bản mới đã tải + verify + persist xong VÀ ver hiện tại
      // < min_force_update của patch đích (gate chỉ trả về khi ép restart) →
      // báo UI hiện popup khởi động lại. Ver đã đủ ngưỡng → gate trả null,
      // bản mới tự áp ở lần mở app sau (không popup).
      final int? newVersion = bg.restartVersion;
      if (newVersion != null && newVersion > 0) {
        moduleUpdateReady.value = newVersion;
      }
    } catch (e) {
      // print('[Boot] gate dynmod background lỗi (bỏ qua, không ảnh hưởng phiên): $e');
      print(e);
    }
  }
}
