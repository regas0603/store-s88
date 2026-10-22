import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset nằm trong main_app_package → prefix riêng từng player (không đổi
/// AudioCache.instance — dùng chung với module).
final AudioCache _packageAudioCache =
    AudioCache(prefix: 'packages/main_app_package/assets/');

/// Các hiệu ứng âm thanh của game. Tên enum khớp tên file trong assets/sfx/.
enum Sfx { tap, flip, match, mismatch, win }

extension SfxX on Sfx {
  /// audioplayers tự thêm tiền tố `assets/`, nên chỉ ghi đường dẫn tương đối.
  String get assetPath => 'sfx/$name.wav';
}

/// Cổng duy nhất ra âm thanh và rung.
///
/// Mọi lời gọi đều "fire and forget" và nuốt lỗi: một file sfx hỏng, thiết bị
/// tắt tiếng, hay audio focus bị app khác chiếm đều KHÔNG được phép làm gián
/// đoạn ván chơi.
///
/// Mỗi [Sfx] giữ một [AudioPlayer] riêng, dựng sẵn từ lúc init. Dùng chung một
/// player sẽ khiến tiếng đập liên tiếp cắt đuôi nhau nghe rất gãy.
class SoundService {
  final Map<Sfx, AudioPlayer> _players = <Sfx, AudioPlayer>{};

  bool _sfxEnabled = true;
  bool _hapticsEnabled = true;
  double _volume = 0.7;
  bool _initialized = false;

  /// Đồng bộ với Cài đặt. Gọi mỗi khi SettingsController phát tín hiệu.
  Future<void> applySettings({
    required bool soundEnabled,
    required bool hapticsEnabled,
    required double volume,
  }) async {
    _sfxEnabled = soundEnabled;
    _hapticsEnabled = hapticsEnabled;
    _volume = volume.clamp(0.0, 1.0);

    for (final player in _players.values) {
      try {
        await player.setVolume(_volume);
      } catch (_) {
        // ignore
      }
    }
  }

  /// Dựng sẵn player cho từng hiệu ứng để lần phát đầu không bị trễ.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    for (final sfx in Sfx.values) {
      try {
        final player = AudioPlayer(playerId: 'sfx_${sfx.name}')
          ..audioCache = _packageAudioCache;
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(sfx.assetPath));
        await player.setVolume(_volume);
        _players[sfx] = player;
      } catch (error) {
        debugPrint('SoundService: bỏ qua ${sfx.name} ($error)');
      }
    }
  }

  /// Phát hiệu ứng. Không await ở phía gọi — âm thanh không được chặn gameplay.
  void play(Sfx sfx) {
    if (!_sfxEnabled) return;
    final player = _players[sfx];
    if (player == null) return;
    unawaited(() async {
      try {
        await player.stop();
        await player.resume();
      } catch (_) {
        // ignore
      }
    }());
  }

  /// Rung nhẹ khi chạm, dùng cho cú đập và bấm nút.
  void tapFeedback() {
    if (!_hapticsEnabled) return;
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
  }

  /// Rung mạnh hơn khi ăn cặp hoặc kết thúc ván.
  void successFeedback() {
    if (!_hapticsEnabled) return;
    unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  /// Rung mạnh, ngắn khi mắc lỗi bị phạt (đập nhầm bom).
  void errorFeedback() {
    if (!_hapticsEnabled) return;
    unawaited(HapticFeedback.heavyImpact().catchError((_) {}));
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {
        // ignore
      }
    }
    _players.clear();
    _initialized = false;
  }
}
