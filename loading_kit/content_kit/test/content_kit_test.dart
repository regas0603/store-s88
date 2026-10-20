import 'package:content_kit/content_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Entry implements ContentEntry {
  const _Entry(this.version);

  @override
  final String version;

  @override
  int get contractVersion => kContentContractVersion;

  @override
  Future<void> init(HostServices host) async {}

  @override
  Widget buildView(BuildContext context) => const SizedBox();

  @override
  Future<Object?> invoke(String method, Map<String, Object?> args) async => null;
}

// Đúng dạng entrypoint của templates/module/modules/home_content.dart.tmpl.
Object? _entrypoint() => (ContentRegistry r) => r.register(const _Entry('1.0.1'));

void main() {
  test('closure entrypoint của module khớp ContentEntrypoint (dyn_loader kiểm kiểu này)', () {
    final Object? ep = _entrypoint();
    expect(ep, isA<ContentEntrypoint>());
    // Bản check cũ (`ContentEntry Function(ContentRegistry)`) từ chối closure này.
    expect(ep is ContentEntry Function(ContentRegistry), isFalse);
    final registry = LocalContentRegistry();
    (ep! as ContentEntrypoint)(registry);
    expect(registry.latest?.version, '1.0.1');
  });

  test('LocalContentRegistry.latest chọn version cao nhất', () {
    final registry = LocalContentRegistry()
      ..register(const _Entry('1.2.0'))
      ..register(const _Entry('1.10.0'))
      ..register(const _Entry('1.9.9+3'));
    expect(registry.latest?.version, '1.10.0');
  });
}
