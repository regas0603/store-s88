import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/dynmod_gate.dart';
import 'package:loading_kit/flow/update_policy.dart';

/// Fake [DynmodGate] cho test: KHÔNG chạm mạng / engine, trả kết quả cố định.
///
/// Máy dev/CI không có engine `ddm` nên không thể chạy gate thật
/// (`loadModuleFromBytes` ném `UnsupportedError`).
class FakeDynmodGate implements DynmodGate {
  FakeDynmodGate({
    this.loaded = false,
    this.moduleVersion = 0,
    this.decision = UpdateDecision.none,
    this.backgroundResult,
    this.backgroundDecision,
    this.onExecute,
  });

  /// true = mô phỏng "module đã nạp + verify OK" → host vào live.
  final bool loaded;

  final int moduleVersion;

  /// Quyết định manifest lúc boot (force → coordinator chặn, không live).
  final UpdateDecision decision;

  /// Hook để test ghi nhận gate đã chạy.
  final void Function()? onExecute;

  /// Số lần [execute] được gọi.
  int calls = 0;

  /// Số lần [executeBackground] được gọi (check nền sau khi vào live).
  int backgroundCalls = 0;

  /// Version mà [executeBackground] trả về cho popup restart (null = không).
  final int? backgroundResult;

  /// Quyết định manifest đọc lại ở check nền (null = không có manifest mới).
  final UpdateDecision? backgroundDecision;

  /// Các giá trị `rsDomain` gate nhận được (thứ tự gọi).
  final List<String?> seenRsDomains = <String?>[];

  @override
  Future<DynmodGateResult> execute({
    required String? rsDomain,
    required bool Function() isActive,
    required void Function({required bool isSyncing}) onSyncVisibilityChanged,
    required BootStepTracker? tracker,
  }) async {
    calls++;
    seenRsDomains.add(rsDomain);
    onExecute?.call();

    if (decision.isForce) {
      // Gate thật trả ngay khi force — không nạp, không tải.
      return (loaded: false, moduleVersion: moduleVersion, decision: decision);
    }
    if (loaded) {
      tracker?.advanceTo(BootStep.download);
      tracker?.advanceTo(BootStep.apply);
    } else {
      tracker?.markSkipped(BootStep.download);
      tracker?.markSkipped(BootStep.apply);
    }

    return (loaded: loaded, moduleVersion: moduleVersion, decision: decision);
  }

  @override
  Future<DynmodBackgroundResult> executeBackground({
    required String? rsDomain,
    required bool Function() isActive,
  }) async {
    backgroundCalls++;
    return (restartVersion: backgroundResult, decision: backgroundDecision);
  }
}
