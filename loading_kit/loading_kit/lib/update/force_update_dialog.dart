import 'package:flutter/material.dart';
import 'package:loading_kit/core/remote_texts.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog BLOCK ép user cập nhật (`action = force` của manifest).
///
/// **Đặc điểm:**
/// - `barrierDismissible: false` + `PopScope(canPop: false)` → KHÔNG dismiss
///   được (tap ngoài / back button đều không ăn). Force là force.
/// - 1 nút duy nhất mở store ([ForceUpdateLink.allUrls] thử lần lượt: `url`
///   của manifest → bản https Play khi `market://` mở fail). Hết cách → hiện
///   dòng lỗi để user bấm lại (không thoát dialog).
///
/// **Caller phải await** để chặn flow (không set [AppMode.live] khi dialog
/// còn mở):
/// ```dart
/// await executeShowForceUpdateDialog(context, link: link);
/// ```
///
/// [launchUrlHandler] chỉ dùng cho test (mặc định `url_launcher` thật).
Future<void> executeShowForceUpdateDialog(
  BuildContext context, {
  required ForceUpdateLink link,
  String? buttonLabel,
  Future<bool> Function(String url)? launchUrlHandler,
}) async {
  if (!context.mounted) {
    // ignore: avoid_print
    // print('[Boot] forceUpdate dialog: context.mounted=false → return early');
    return;
  }
  // ignore: avoid_print
  // print(
  //   '[Boot] forceUpdate dialog: show url=${link.url} '
  //   'fallback=${link.fallbackUrls}',
  // );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogCtx) {
      return PopScope(
        canPop: false,
        child: UpdatePromptDialog(
          link: link,
          updateLabel: buttonLabel,
          launchUrlHandler: launchUrlHandler,
        ),
      );
    },
  );
  // ignore: avoid_print
  // print('[Boot] forceUpdate dialog: closed (edge case)');
}

/// Dialog SOFT (`action = soft`): "Cập nhật" mở store, "Để sau" đóng để chơi
/// tiếp. Trả `true` khi user bấm "Cập nhật" và store đã mở, `false` khi
/// bấm "Để sau" (caller ghi lần từ chối — [SoftPromptStore]).
///
/// Tap ngoài / back KHÔNG đóng (bắt chọn rõ 1 trong 2 nút → biết chắc có ghi
/// "Để sau" hay không).
Future<bool> executeShowSoftUpdateDialog(
  BuildContext context, {
  required ForceUpdateLink link,
  Future<bool> Function(String url)? launchUrlHandler,
}) async {
  if (!context.mounted) {
    return false;
  }
  // ignore: avoid_print
  // print('[Boot] softUpdate dialog: show url=${link.url}');
  final bool? opened = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogCtx) {
      return PopScope(
        canPop: false,
        child: UpdatePromptDialog(
          link: link,
          updateLabel: RemoteTexts.current.softUpdateButton,
          launchUrlHandler: launchUrlHandler,
          onLater: () => Navigator.of(dialogCtx).pop(false),
          onOpened: () => Navigator.of(dialogCtx).pop(true),
        ),
      );
    },
  );
  return opened ?? false;
}

/// Nội dung dialog cập nhật dùng chung cho [showDialog] (splash) và overlay
/// tự dựng MaterialApp của host (BootShell — không lồng MaterialApp,
/// flutter/flutter#142585).
///
/// * [onLater] null → FORCE: chỉ 1 nút mở store, không có lối thoát.
/// * [onLater] khác null → SOFT: thêm nút "Để sau".
/// * [onOpened] gọi khi store đã mở được (SOFT dùng để đóng popup; FORCE
///   giữ nguyên — user quay lại app vẫn bị chặn).
class UpdatePromptDialog extends StatefulWidget {
  const UpdatePromptDialog({
    super.key,
    required this.link,
    this.updateLabel,
    this.laterLabel,
    this.onLater,
    this.onOpened,
    this.launchUrlHandler,
  });

  final ForceUpdateLink link;
  /// null = [RemoteTexts.forceUpdateButton]; không có text → icon.
  final String? updateLabel;

  /// null = [RemoteTexts.softUpdateLater]; không có text → icon.
  final String? laterLabel;
  final VoidCallback? onLater;
  final VoidCallback? onOpened;

  /// Chỉ dùng cho test (mặc định `url_launcher` thật).
  final Future<bool> Function(String url)? launchUrlHandler;

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  String? _errorText;
  bool _opening = false;

  Future<void> _executeOpen() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    final bool didOpen = await executeOpenFirstWorkingUrl(
      link: widget.link,
      launch: widget.launchUrlHandler ?? _executeLaunchStoreUrl,
    );
    // ignore: avoid_print
    // print('[Boot] update dialog: didOpen=$didOpen');
    if (!mounted) {
      return;
    }
    setState(() {
      _opening = false;
      // Không có text lỗi → chuỗi rỗng (không hiện gì, nút vẫn bấm lại được).
      _errorText = didOpen ? null : (RemoteTexts.current.storeOpenError ?? '');
    });
    if (didOpen) {
      widget.onOpened?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final RemoteTexts texts = RemoteTexts.current;
    final ButtonStyle primaryStyle = TextButton.styleFrom(
      foregroundColor: Colors.blue,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    final String? title = widget.link.title;
    final String? message = widget.link.message;
    final String? laterLabel = widget.laterLabel ?? texts.softUpdateLater;
    final String? updateLabel = widget.updateLabel ?? texts.forceUpdateButton;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: title == null
          ? null
          : Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (message != null)
            Text(
              message,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          if (_errorText != null && _errorText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        if (widget.onLater != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            onPressed: widget.onLater,
            child: laterLabel != null
                ? Text(laterLabel)
                : const Icon(Icons.close),
          ),
        TextButton(
          style: primaryStyle,
          onPressed: _executeOpen,
          child: updateLabel != null
              ? Text(updateLabel)
              : const Icon(Icons.system_update),
        ),
      ],
    );
  }
}

/// Mở lần lượt [ForceUpdateLink.allUrls] — dừng ở URL đầu tiên mở được.
/// Trả false khi tất cả đều fail (caller hiện dòng lỗi, KHÔNG đóng dialog).
Future<bool> executeOpenFirstWorkingUrl({
  required ForceUpdateLink link,
  required Future<bool> Function(String url) launch,
}) async {
  for (final String url in link.allUrls) {
    final bool didOpen = await launch(url);
    // ignore: avoid_print
    // print('[Boot] update dialog: launch $url → $didOpen');
    if (didOpen) {
      return true;
    }
  }
  return false;
}

/// `url_launcher` thật — `externalApplication` để mở Play/App Store app (không
/// nhúng in-app browser: user cần thấy nút "Cập nhật" của store).
Future<bool> _executeLaunchStoreUrl(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    // ignore: avoid_print
    // print('[Boot] update dialog: launchUrl lỗi error=$e');
    print(e);
    return false;
  }
}
