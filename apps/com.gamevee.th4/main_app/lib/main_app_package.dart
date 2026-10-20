/// Main app UI của Flipmind — màn "sạch" của shell (contract: main_app/README.md
/// của repo). Shell (BootShell) đặt [MainAppScreen] trong MaterialApp của nó
/// khi app ở chế độ demo; nhận diện app lấy từ [mainAppMeta]. Boot flow /
/// dynamic module do shell lo.
library;

export 'src/main_app_meta.dart';
export 'src/main_app_screen.dart';
