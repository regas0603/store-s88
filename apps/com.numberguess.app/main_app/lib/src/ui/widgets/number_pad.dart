import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Bàn phím số tự vẽ, dùng cho cả ô đoán lẫn ô nhập số bí mật.
///
/// Cố ý KHÔNG dùng `TextField` với bàn phím hệ thống: bàn phím iOS che mất
/// lịch sử đoán và khoảng còn lại — đúng hai thứ người chơi cần nhìn trong lúc
/// bấm. Bàn phím riêng luôn nằm cố định dưới đáy, phím to, bấm nhanh được.
class NumberPad extends StatelessWidget {
  /// Số chữ số tối đa cho phép nhập.
  final int maxDigits;

  /// Nhãn của phím hành động chính.
  final String submitLabel;

  /// null = khoá phím xác nhận (chưa nhập gì, hoặc đang không được phép).
  final VoidCallback? onSubmit;

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Khoá toàn bộ bàn phím (đang tạm dừng, đang chuyền máy…).
  final bool enabled;

  const NumberPad({
    required this.maxDigits,
    required this.submitLabel,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.onSubmit,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final row in const <List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
          <int>[7, 8, 9],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                for (final digit in row) ...<Widget>[
                  if (digit != row.first) const SizedBox(width: 8),
                  Expanded(
                    child: _PadKey(
                      label: '$digit',
                      onTap: enabled ? () => onDigit(digit) : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: _PadKey(
                icon: Icons.backspace_outlined,
                semanticLabel: MaterialLocalizations.of(context)
                    .deleteButtonTooltip,
                onTap: enabled ? onBackspace : null,
                onLongPress: enabled ? onClear : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PadKey(
                label: '0',
                onTap: enabled ? () => onDigit(0) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PadKey(
                label: submitLabel,
                primary: true,
                onTap: enabled ? onSubmit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final bool primary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PadKey({
    this.label,
    this.icon,
    this.semanticLabel,
    this.primary = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabled = onTap == null;

    final background = primary
        ? scheme.primary
        : AppTheme.panelColor(scheme, theme.brightness);
    final foreground = primary
        ? scheme.onPrimary
        : scheme.onSurface;

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: primary
                    ? Colors.transparent
                    : AppTheme.panelBorder(scheme, theme.brightness),
              ),
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, color: foreground, semanticLabel: semanticLabel)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          label!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: foreground,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Khung hiển thị con số đang gõ dở.
class NumberDisplay extends StatelessWidget {
  final String value;
  final String placeholder;

  /// Che số bằng dấu chấm (người chơi nhập số bí mật).
  final bool obscured;

  /// Thông báo lỗi dưới ô số, hoặc null.
  final String? error;

  const NumberDisplay({
    required this.value,
    required this.placeholder,
    this.obscured = false,
    this.error,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmpty = value.isEmpty;
    final shown = isEmpty
        ? placeholder
        : (obscured ? '•' * value.length : value);

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.panelColor(scheme, theme.brightness),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: error != null
                  ? AppTheme.alpha(AppTheme.trapRed, 0.8)
                  : AppTheme.alpha(scheme.primary, isEmpty ? 0.25 : 0.7),
              width: isEmpty ? 1 : 2,
            ),
          ),
          // Ô cao cố định để bố cục không nhảy khi chuyển giữa placeholder và
          // con số thật — hai cỡ chữ rất khác nhau.
          height: 72,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              shown,
              style: (isEmpty
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.displaySmall)
                  ?.copyWith(
                fontWeight: isEmpty ? FontWeight.w600 : FontWeight.w900,
                letterSpacing: obscured ? 6 : 2,
                color: isEmpty
                    ? AppTheme.alpha(scheme.onSurface, 0.45)
                    : scheme.onSurface,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.trapRed,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
