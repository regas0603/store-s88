// Mô hình quyết định cập nhật THUẦN (không I/O, không Flutter) — đọc từ dòng
// của bản build trong `{rs_domain}/app/manifest/<bundleId>.json`
// (docs/release_registry_design.md §5, §5.2).
//
// loading_kit KHÔNG đọc manifest (dependency inversion — xem dynmod_gate.dart):
// host (app/) tra manifest bằng dyn_loader rồi dựng [UpdateDecision] trả qua
// [DynmodGate]. Tool đã tính sẵn `action` + `url` cho mọi bản build nên client
// chỉ áp, không tự suy luận theo `latest` / `min_allowed_patch`.

import 'package:loading_kit/core/remote_texts.dart';

/// `action` của dòng bản build.
enum UpdateAction {
  /// Không popup (mặc định khi manifest thiếu `action`).
  none,

  /// Popup "Cập nhật" / "Để sau" — từ chối thì chơi tiếp.
  soft,

  /// Popup KHÔNG đóng được — không vào live.
  force;

  /// Parse chuỗi manifest; thiếu / lạ → [none] (fail-open).
  static UpdateAction parse(String? raw) => switch (raw?.trim()) {
    'soft' => UpdateAction.soft,
    'force' => UpdateAction.force,
    _ => UpdateAction.none,
  };
}

/// Quyết định cập nhật cho bản build đang chạy.
class UpdateDecision {
  const UpdateDecision({
    this.action = UpdateAction.none,
    this.url,
    this.targetPatch = 0,
    this.latest = 0,
    this.softPromptIntervalHours = kDefaultSoftPromptIntervalHours,
  });

  /// Không có manifest / không có dòng / lỗi → không làm gì (fail-open).
  static const UpdateDecision none = UpdateDecision();

  /// Mặc định khi Git JSON per-app thiếu `soft_prompt_interval_hours`.
  static const int kDefaultSoftPromptIntervalHours = 24;

  /// Dựng từ field thô của manifest + chuẩn hoá: `soft`/`force` mà thiếu
  /// `url` → hạ về [UpdateAction.none] (thà để user chơi tiếp còn hơn kẹt
  /// popup không có nút nào bấm được — validator của tool vốn đã chặn).
  factory UpdateDecision.fromManifest({
    required String? action,
    required String? url,
    required int targetPatch,
    required int latest,
  }) {
    UpdateAction parsed = UpdateAction.parse(action);
    final String? trimmedUrl = url?.trim();
    final bool hasUrl = trimmedUrl != null && trimmedUrl.isNotEmpty;
    if (parsed != UpdateAction.none && !hasUrl) {
      // print(
      //   '[Boot] updatePolicy: action=${parsed.name} nhưng thiếu url '
      //   '→ hạ về none (fail-open)',
      // );
      parsed = UpdateAction.none;
    }
    return UpdateDecision(
      action: parsed,
      url: parsed == UpdateAction.none ? null : trimmedUrl,
      targetPatch: targetPatch,
      latest: latest,
    );
  }

  /// Bản sao với interval từ Git JSON per-app (manifest không còn mang
  /// `soft_prompt_interval_hours`).
  UpdateDecision withSoftPromptIntervalHours(int hours) => UpdateDecision(
    action: action,
    url: url,
    targetPatch: targetPatch,
    latest: latest,
    softPromptIntervalHours: hours,
  );

  final UpdateAction action;

  /// Link store đầy đủ (của chính app hoặc app thay thế) — chỉ có khi
  /// [action] != none.
  final String? url;

  /// Patch cao nhất bản build này chạy được (0 = không có).
  final int targetPatch;

  /// `latest` của manifest — SOFT đã bị từ chối được hỏi lại khi số này tăng.
  final int latest;

  /// Khoảng không hỏi lại SOFT sau khi bị từ chối (Git JSON per-app
  /// `soft_prompt_interval_hours`, thiếu → 24).
  final int softPromptIntervalHours;

  bool get isForce => action == UpdateAction.force;
  bool get isSoft => action == UpdateAction.soft;

  /// Link cho dialog (kèm fallback Play https cho `market://`); null khi
  /// không có popup.
  ForceUpdateLink? toLink() {
    final String? u = url;
    if (action == UpdateAction.none || u == null || u.isEmpty) {
      return null;
    }
    final RemoteTexts texts = RemoteTexts.current;
    return buildUpdateLink(
      u,
      title: texts.updateTitle,
      message: isForce ? texts.forceUpdateMessage : texts.softUpdateMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UpdateDecision &&
      other.action == action &&
      other.url == url &&
      other.targetPatch == targetPatch &&
      other.latest == latest &&
      other.softPromptIntervalHours == softPromptIntervalHours;

  @override
  int get hashCode =>
      Object.hash(action, url, targetPatch, latest, softPromptIntervalHours);

  @override
  String toString() =>
      'UpdateDecision(${action.name}, url=$url, target=$targetPatch, '
      'latest=$latest, interval=${softPromptIntervalHours}h)';
}

/// Link + copy cho dialog cập nhật (force / soft).
class ForceUpdateLink {
  const ForceUpdateLink({
    required this.url,
    this.fallbackUrls = const <String>[],
    this.title,
    this.message,
  });

  /// URL chính của nút bấm.
  final String url;

  /// URL thử tiếp khi [url] không mở được (vd `market://` trên máy không có
  /// Play Store → bản https của Play).
  final List<String> fallbackUrls;

  /// Text từ Git JSON (`texts`); null = không có → dialog bỏ trống phần đó.
  final String? title;
  final String? message;

  /// Thứ tự thử khi user bấm nút.
  List<String> get allUrls => <String>[url, ...fallbackUrls];

  @override
  String toString() => 'ForceUpdateLink(url=$url, fallback=$fallbackUrls)';
}

/// `market://details?id=<id>` → `https://play.google.com/store/apps/details?id=<id>`
/// (máy không có Play app vẫn mở được qua trình duyệt). URL khác → null.
String? playHttpsFallback(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'market') {
    return null;
  }
  final String? id = uri.queryParameters['id'];
  if (id == null || id.isEmpty) {
    return null;
  }
  return 'https://play.google.com/store/apps/details?id=$id';
}

/// [ForceUpdateLink] cho [url] của manifest (+ fallback Play https nếu là
/// `market://`).
ForceUpdateLink buildUpdateLink(
  String url, {
  String? title,
  String? message,
}) {
  final String? fallback = playHttpsFallback(url);
  return ForceUpdateLink(
    url: url,
    fallbackUrls: <String>[?fallback],
    title: title,
    message: message,
  );
}

/// Lần gần nhất user bấm "Để sau" ở popup SOFT.
typedef SoftPromptDismissal = ({int dismissedLatest, DateTime dismissedAt});

/// Có hiện popup SOFT không (thuần — caller bơm [now]).
///
/// * Không phải SOFT → false.
/// * Chưa từng từ chối → true.
/// * `latest` tăng so với lần từ chối → true (có bản mới hơn nữa).
/// * Còn trong `soft_prompt_interval_hours` kể từ lần từ chối → false.
/// * Interval <= 0 → luôn hỏi.
bool shouldShowSoftPrompt({
  required UpdateDecision decision,
  required SoftPromptDismissal? dismissal,
  required DateTime now,
}) {
  if (!decision.isSoft) {
    return false;
  }
  if (dismissal == null) {
    return true;
  }
  if (decision.latest > dismissal.dismissedLatest) {
    return true;
  }
  final int hours = decision.softPromptIntervalHours;
  if (hours <= 0) {
    return true;
  }
  return now.difference(dismissal.dismissedAt) >= Duration(hours: hours);
}
