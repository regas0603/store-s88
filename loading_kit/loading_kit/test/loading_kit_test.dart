import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

import 'fakes/fake_dynmod_gate.dart';

void main() {
  test('barrel export: AppLaunchCoordinator dựng được với DynmodGate', () {
    final AppLaunchCoordinator coordinator = AppLaunchCoordinator(
      dynmodGate: FakeDynmodGate(),
    );
    expect(coordinator.rsDomain, isNull);
    expect(coordinator.apiDomain, isNull);
  });
}
