import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'main_app_meta.dart';

/// Màn hình "sạch" (main app) — hiển thị khi boot flow KHÔNG mở được chế độ
/// chính: máy CHƯA có patch nào (bản release mới lên store), `status != 0`,
/// hoặc lỗi mạng. Shell render qua `appScreenBuilder` (BootShell).
///
/// Đây là TOÀN BỘ UI của main app. Đổi diện mạo cho white-label khác = sửa
/// UI + `mainAppMeta` rồi chạy lại `tools/cmd/build_main_app.sh` (xem README.md).
class MainAppScreen extends StatelessWidget {
  const MainAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(mainAppMeta.appTitle),
        actions: <Widget>[
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dữ liệu mẫu — chưa nối API')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          const _CurrentWeatherCard(),
          const SizedBox(height: 12),
          const Row(
            children: <Widget>[
              Expanded(
                child: _StatTile(
                  label: 'Độ ẩm',
                  value: '74%',
                  icon: Icons.water_drop_outlined,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Gió',
                  value: '12 km/h',
                  icon: Icons.air,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Cảm giác',
                  value: '30°',
                  icon: Icons.thermostat,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('3 ngày tới'),
          const _ForecastTile(
            day: 'Thứ 2',
            icon: Icons.wb_sunny_outlined,
            condition: 'Nắng',
            range: '24° / 32°',
          ),
          const _ForecastTile(
            day: 'Thứ 3',
            icon: Icons.cloud_outlined,
            condition: 'Nhiều mây',
            range: '23° / 30°',
          ),
          const _ForecastTile(
            day: 'Thứ 4',
            icon: Icons.grain,
            condition: 'Mưa rào',
            range: '22° / 28°',
          ),
          const SizedBox(height: 16),
          if (kDebugMode) const _DebugModeBadge(),
        ],
      ),
    );
  }
}

// ⬆️ hết MainAppScreen

/// Khối thời tiết hiện tại (dữ liệu tĩnh — placeholder).
class _CurrentWeatherCard extends StatelessWidget {
  const _CurrentWeatherCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text('Hà Nội', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '28°',
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text('Nhiều mây', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// 1 ô số liệu nhỏ (độ ẩm / gió / cảm giác).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.titleMedium),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Tiêu đề 1 nhóm trong trang.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// 1 dòng dự báo theo ngày.
class _ForecastTile extends StatelessWidget {
  const _ForecastTile({
    required this.day,
    required this.icon,
    required this.condition,
    required this.range,
  });

  final String day;
  final IconData icon;
  final String condition;
  final String range;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(day),
      subtitle: Text(condition),
      trailing: Text(range),
    );
  }
}

/// Nhắc "layout tạm" — CHỈ hiện ở debug build, release không thấy.
class _DebugModeBadge extends StatelessWidget {
  const _DebugModeBadge();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.build_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Layout tạm (debug) — thay bằng UI thật sau',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
