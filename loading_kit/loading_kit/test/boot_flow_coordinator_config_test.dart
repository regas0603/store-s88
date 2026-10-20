import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/boot_flow_coordinator.dart';

void main() {
  group('BootFlowCoordinator (Phase 1)', () {
    test('getter api/rs mặc định null trước khi fetch (fail-open)', () {
      final BootFlowCoordinator coordinator = BootFlowCoordinator();
      expect(coordinator.apiDomain, isNull);
      expect(coordinator.rsDomain, isNull);
    });
  });
}
