# App Flutter mẫu cho dynamic modules (sẵn sàng build khi engine xong)

> Template tối thiểu để test code-push trên app Flutter thật. Dựng sau khi có engine ddm.
> Ý tưởng: host hiển thị 1 giá trị; **nạp module qua mạng** thêm phép tính mới, cập nhật UI
> mà KHÔNG rebuild app. Cùng mô hình Registry/Operation như PoC CLI.

## Cấu trúc
```
sample_app/
  pubspec.yaml
  dynamic_interface.yaml
  lib/main.dart            # host (AOT, có interpreter)
  lib/calc_api.dart        # API surface (Operation/Registry) — lộ qua interface
  modules/power.dart       # dynamic module (compile bằng dart2bytecode)
```

## lib/calc_api.dart (API surface)
```dart
abstract interface class Operation { String get name; num apply(List<num> a); }
abstract interface class Registry { void addOperation(Operation op); }
```

## lib/main.dart (host)
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dynamic_modules/dynamic_modules.dart';
import 'package:http/http.dart' as http;
import 'calc_api.dart';

void main() => runApp(const MyApp());

class Reg implements Registry {
  final ops = <String, Operation>{};
  @override void addOperation(Operation o) => ops[o.name] = o;
}

class MyApp extends StatefulWidget { const MyApp({super.key}); @override State<MyApp> createState()=>_S(); }
class _S extends State<MyApp> {
  final reg = Reg();
  String status = 'Chỉ có +. Bấm "Nạp module" để thêm ^ qua mạng.';
  // TODO: trỏ về self-host server của bạn (server/ trong repo)
  static const base = 'http://10.0.2.2:8787/artifacts/patch/1'; // 10.0.2.2 = host từ Android emulator

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('$base/power.bytecode'));
      final ep = await loadModuleFromBytes(Uint8List.fromList(r.bodyBytes));
      (ep as void Function(Registry))(reg);
      setState(() => status = 'Đã nạp! 2^10 = ${reg.ops['^']!.apply([2,10])}');
    } catch (e) { setState(() => status = 'Lỗi: $e'); }
  }

  @override Widget build(BuildContext c) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Dyn Modules PoC')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(status, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _load, child: const Text('Nạp module qua mạng')),
        ]))),
    ));
}
```

## modules/power.dart (dynamic module)
```dart
import '../lib/calc_api.dart';
class PowerOp implements Operation {
  @override String get name => '^';
  @override num apply(List<num> a) { num r=1; for(var i=0;i<a[1];i++) r*=a[0]; return r; }
}
@pragma('dyn-module:entry-point')
Object? dynamicModuleEntrypoint() => (Registry r) => r.addOperation(PowerOp());
```

## dynamic_interface.yaml
```yaml
extendable:
  - {library: 'lib/calc_api.dart', class: 'Operation'}
can-be-overridden:
  - {library: 'lib/calc_api.dart', class: 'Operation'}
can-be-used-as-type:
  - {library: 'lib/calc_api.dart', class: 'Registry'}
  - {library: 'lib/calc_api.dart', class: 'Operation'}
callable:
  - {library: 'dart:core'}
  - {library: 'lib/calc_api.dart', class: 'Registry', member: 'addOperation'}
```

## Build (khi engine ddm sẵn sàng)
```bash
FF=../dart-sdk-build/flutter-framework
# 1. Build app host với engine ddm + interface (không cần vá flutter_tools — Cách A)
$FF/bin/flutter build apk --release \
  --local-engine-src-path $FF/engine/src \
  --local-engine=android_release_arm64_ddm \
  --local-engine-host=host_release \
  --extra-front-end-options=--dynamic-interface=dynamic_interface.yaml

# 2. Anchor dill (Cách A — gen_kernel no-aot trên chính main.dart) + dart2bytecode module
#    (dùng gen_kernel/dart2bytecode từ engine out; xem dyn_modules_poc_guide.md §2)

# 3. Upload power.bytecode lên self-host server → app bấm nút nạp qua mạng
```

## Ghi chú test
- Android emulator: server localhost truy cập qua `10.0.2.2`.
- Kỳ vọng: mở app thấy "chỉ có +"; bấm nút → tải power.bytecode → hiện "2^10=1024" =
  **code-push trên Flutter thật thành công**.
- iOS: cùng `power.bytecode` (arch-independent), build engine `ios_release_ddm`, thử máy thật
  → đối mặt câu hỏi code-signing (bước nghiên cứu).
