import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'app_settings.dart';

/// Short game SFX + optional match ambience. Respects [AppSettings.soundEnabled],
/// uses iOS `ambient` session (honours silent switch), and stops playback when
/// the user turns sound off (App Store–friendly behaviour).
class AudioService {
  static final AudioService _i = AudioService._();
  factory AudioService() => _i;
  AudioService._();

  static final AudioContext _globalContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const {},
    ),
  );

  // Asset nằm trong main_app_package → prefix riêng từng player (không đổi
  // AudioCache.instance — dùng chung với module).
  final AudioPlayer _sfx = AudioPlayer()
    ..audioCache = AudioCache(prefix: 'packages/main_app_package/assets/');
  final AudioPlayer _ambience = AudioPlayer()
    ..audioCache = AudioCache(prefix: 'packages/main_app_package/assets/');

  bool _initialized = false;
  /// True while [GameScreen] (or similar) wants looped match ambience.
  bool _ambienceDesired = false;
  bool _ambiencePlaying = false;

  /// Call once after [WidgetsFlutterBinding.ensureInitialized].
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await AudioPlayer.global.setAudioContext(_globalContext);
    await _sfx.setReleaseMode(ReleaseMode.stop);
    await _ambience.setReleaseMode(ReleaseMode.loop);
    await _ambience.setVolume(0.2);

    AppSettings().addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  void _onSettingsChanged() {
    if (!AppSettings().soundEnabled) {
      unawaited(_mutePlayback());
    } else if (_ambienceDesired) {
      unawaited(_playAmbienceLoop());
    }
  }

  /// Stops SFX and ambience immediately when user turns sound off.
  Future<void> _mutePlayback() async {
    try {
      await _sfx.stop();
      await _ambience.stop();
    } catch (_) {}
    _ambiencePlaying = false;
  }

  Future<void> _playSfx(String assetRelativeToAssetsPrefix) async {
    if (!AppSettings().soundEnabled) return;
    try {
      await _sfx.stop();
      await _sfx.play(AssetSource(assetRelativeToAssetsPrefix), volume: 0.85);
    } catch (e, st) {
      debugPrint('AudioService SFX failed: $e\n$st');
    }
  }

  Future<void> playPlace() => _playSfx('sounds/sfx_place.wav');

  Future<void> playWin() => _playSfx('sounds/sfx_win.wav');

  Future<void> playTimeout() => _playSfx('sounds/sfx_timeout.wav');

  Future<void> playUndo() => _playSfx('sounds/sfx_undo.wav');

  Future<void> _playAmbienceLoop() async {
    if (!AppSettings().soundEnabled || !_ambienceDesired) return;
    if (_ambiencePlaying) return;
    _ambiencePlaying = true;
    try {
      await _ambience.stop();
      await _ambience.play(
        AssetSource('sounds/ambience_match.wav'),
        volume: 0.2,
      );
    } catch (e, st) {
      _ambiencePlaying = false;
      debugPrint('AudioService ambience failed: $e\n$st');
    }
  }

  /// Low-key loop while a match screen is visible.
  Future<void> startMatchAmbience() async {
    _ambienceDesired = true;
    await _playAmbienceLoop();
  }

  Future<void> stopMatchAmbience() async {
    _ambienceDesired = false;
    _ambiencePlaying = false;
    try {
      await _ambience.stop();
    } catch (_) {}
  }
}
