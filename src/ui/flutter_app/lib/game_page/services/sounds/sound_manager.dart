// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// sound_manager.dart

part of '../mill.dart';

/// Sounds the [SoundManager] can play through [SoundManager.playTone].
enum Sound { draw, illegal, lose, mill, place, remove, select, win }

class SoundManager {
  factory SoundManager() => instance;

  SoundManager._();

  @visibleForTesting
  static SoundManager instance = SoundManager._();

  String? soundThemeName = 'ball';

  // Use a shared audio context so BGM and SFX can mix instead of interrupting
  // each other (some platforms will stop the current audio when audio focus or
  // the audio session is reconfigured).
  static final AudioContext _mixWithOthersAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();
  static bool _isGlobalAudioContextConfigured = false;

  final Map<String, Map<Sound, String>> _soundFiles =
      <String, Map<Sound, String>>{
        'ball': <Sound, String>{
          Sound.draw: Assets.audios.draw,
          Sound.illegal: Assets.audios.ball.illegal,
          Sound.lose: Assets.audios.lose,
          Sound.mill: Assets.audios.ball.mill,
          Sound.place: Assets.audios.ball.place,
          Sound.remove: Assets.audios.ball.remove,
          Sound.select: Assets.audios.ball.select,
          Sound.win: Assets.audios.win,
        },
        'liquid': <Sound, String>{
          Sound.draw: Assets.audios.draw,
          Sound.illegal: Assets.audios.liquid.illegal,
          Sound.lose: Assets.audios.lose,
          Sound.mill: Assets.audios.liquid.mill,
          Sound.place: Assets.audios.liquid.place,
          Sound.remove: Assets.audios.liquid.remove,
          Sound.select: Assets.audios.liquid.select,
          Sound.win: Assets.audios.win,
        },
        'wood': <Sound, String>{
          Sound.draw: Assets.audios.draw,
          Sound.illegal: Assets.audios.wood.illegal,
          Sound.lose: Assets.audios.lose,
          Sound.mill: Assets.audios.wood.mill,
          Sound.place: Assets.audios.wood.place,
          Sound.remove: Assets.audios.wood.remove,
          Sound.select: Assets.audios.wood.select,
          Sound.win: Assets.audios.win,
        },
      };

  // Map of Sound to SoundPlayer instances, which include the player and fileName.
  final Map<Sound, SoundPlayer> _players = <Sound, SoundPlayer>{};

  AudioPlayer? _backgroundMusicPlayer;
  String? _backgroundMusicPath;

  bool _isTemporaryMute = false;

  bool _allSoundsLoaded = false;

  /// Serializes [loadSounds] so concurrent callers cannot leave a half-built
  /// player map or flip [_allSoundsLoaded] to false after a successful load.
  Future<void> _loadSoundsSerial = Future<void>.value();

  static const String _logTag = "[audio]";

  Future<void> _ensureGlobalAudioContextConfigured() async {
    if (_isGlobalAudioContextConfigured) {
      return;
    }

    try {
      await AudioPlayer.global.setAudioContext(_mixWithOthersAudioContext);
      _isGlobalAudioContextConfigured = true;
      logger.t("$_logTag Global audio context configured: mixWithOthers");
    } catch (e) {
      logger.e("$_logTag Failed to set global audio context: $e");
    }
  }

  Future<void> loadSounds() async {
    await (_loadSoundsSerial = _loadSoundsSerial.then((_) async {
      try {
        await _loadSoundsBody();
      } catch (e, s) {
        logger.e("$_logTag loadSounds: $e\n$s");
      }
    }));
  }

  Future<void> _loadSoundsBody() async {
    await _ensureGlobalAudioContextConfigured();
    soundThemeName = DB().generalSettings.soundTheme?.name ?? 'ball';

    final Map<Sound, String>? sounds = _soundFiles[soundThemeName];
    if (sounds == null) {
      logger.e("No sound files found for theme $soundThemeName.");
      return;
    }

    final Map<Sound, SoundPlayer> newPlayers = <Sound, SoundPlayer>{};
    try {
      for (final Sound sound in sounds.keys) {
        // Adjust the file path by replacing 'assets/' with ''.
        final String fileName = sounds[sound]!.replaceFirst('assets/', '');
        final AudioPlayer player = AudioPlayer();
        await player.setAudioContext(_mixWithOthersAudioContext);
        await player.setReleaseMode(ReleaseMode.stop);
        newPlayers[sound] = SoundPlayer(player, fileName);
      }
      for (final SoundPlayer soundPlayer in _players.values) {
        await soundPlayer.player.dispose();
      }
      _players
        ..clear()
        ..addAll(newPlayers);
      _allSoundsLoaded = true;
    } catch (e) {
      for (final SoundPlayer soundPlayer in newPlayers.values) {
        await soundPlayer.player.dispose();
      }
      logger.e("Failed to load sound: $e");
      if (_players.isEmpty) {
        _allSoundsLoaded = false;
      }
    }
  }

  Future<void> startBackgroundMusic() async {
    await _ensureGlobalAudioContextConfigured();
    if (_isTemporaryMute || DB().generalSettings.screenReaderSupport) {
      return;
    }

    // Treat background music as part of the overall in-game audio setting.
    if (!DB().generalSettings.toneEnabled) {
      await stopBackgroundMusic();
      return;
    }

    if (!DB().generalSettings.backgroundMusicEnabled) {
      await stopBackgroundMusic();
      return;
    }

    final String filePath = DB().generalSettings.backgroundMusicFilePath;
    if (filePath.isEmpty) {
      await stopBackgroundMusic();
      return;
    }

    assert(
      filePath.isNotEmpty,
      'backgroundMusicFilePath must not be empty when enabled',
    );

    // Avoid restarting if already playing the same file.
    if (_backgroundMusicPlayer != null &&
        _backgroundMusicPath == filePath &&
        _backgroundMusicPlayer!.state == PlayerState.playing) {
      return;
    }

    try {
      _backgroundMusicPlayer ??= AudioPlayer();
      await _backgroundMusicPlayer!.setAudioContext(_mixWithOthersAudioContext);
      _backgroundMusicPath = filePath;
      await _backgroundMusicPlayer!.setReleaseMode(ReleaseMode.loop);
      await _backgroundMusicPlayer!.stop();
      await _backgroundMusicPlayer!.play(DeviceFileSource(filePath));
      logger.t("$_logTag Background music started: $filePath");
    } catch (e) {
      logger.e("$_logTag Error starting background music: $e");
    }
  }

  Future<void> stopBackgroundMusic() async {
    try {
      if (_backgroundMusicPlayer == null) {
        return;
      }
      await _backgroundMusicPlayer!.stop();
      logger.t("$_logTag Background music stopped");
    } catch (e) {
      logger.e("$_logTag Error stopping background music: $e");
    }
  }

  /// Play the given sound.
  Future<void> playTone(Sound sound) async {
    if (_isTemporaryMute || DB().generalSettings.screenReaderSupport) {
      return;
    }

    if (DB().generalSettings.vibrationEnabled) {
      await VibrationManager().vibrate(sound);
    }

    if (!DB().generalSettings.toneEnabled) {
      return;
    }

    if (!_allSoundsLoaded) {
      logger.w("Attempt to play sound before all sounds were loaded.");
      return;
    }

    // Get the SoundPlayer instance for the sound.
    final SoundPlayer? soundPlayer = _players[sound];
    if (soundPlayer == null) {
      logger.e("No player found for sound $sound in theme $soundThemeName.");
      return;
    }
    try {
      // Stop first so rapid repeats on the same player still emit audio on
      // platforms where play() is a no-op while the clip is playing.
      await soundPlayer.player.stop();
      await soundPlayer.player.play(AssetSource(soundPlayer.fileName));
    } catch (e) {
      logger.e("$_logTag Error playing sound: $e");
    }
  }

  /// Play the given sound and wait until playback completes.
  ///
  /// This is intended for sequencing (e.g. ensure a "mill" sound finishes
  /// before starting a subsequent capture animation/sound).
  ///
  /// Note: This waits for the underlying player's completion event and uses a
  /// conservative timeout to avoid deadlocks on platforms where completion
  /// callbacks may be unreliable.
  Future<void> playToneAndWait(
    Sound sound, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isTemporaryMute || DB().generalSettings.screenReaderSupport) {
      return;
    }

    if (DB().generalSettings.vibrationEnabled) {
      await VibrationManager().vibrate(sound);
    }

    if (!DB().generalSettings.toneEnabled) {
      return;
    }

    if (!_allSoundsLoaded) {
      logger.w("Attempt to play sound before all sounds were loaded.");
      return;
    }

    final SoundPlayer? soundPlayer = _players[sound];
    if (soundPlayer == null) {
      logger.e("No player found for sound $sound in theme $soundThemeName.");
      return;
    }

    StreamSubscription<void>? sub;
    final Completer<void> done = Completer<void>();
    bool didTimeout = false;

    try {
      sub = soundPlayer.player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) {
          done.complete();
        }
      });

      await soundPlayer.player.stop();
      await soundPlayer.player.play(AssetSource(soundPlayer.fileName));
      await done.future.timeout(
        timeout,
        onTimeout: () {
          didTimeout = true;
        },
      );
    } catch (e) {
      logger.e("$_logTag Error playing sound: $e");
    } finally {
      await sub?.cancel();
      if (didTimeout) {
        logger.w("$_logTag Timeout waiting for sound completion: $sound");
      }
    }
  }

  void mute() {
    _isTemporaryMute = true;
  }

  void unMute() {
    _isTemporaryMute = false;
  }

  Future<void> disposePool() async {
    for (final SoundPlayer soundPlayer in _players.values) {
      await soundPlayer.player.dispose();
    }
    _players.clear();

    await _backgroundMusicPlayer?.dispose();
    _backgroundMusicPlayer = null;
    _backgroundMusicPath = null;
  }
}

/// Helper class to store AudioPlayer and associated fileName.
class SoundPlayer {
  SoundPlayer(this.player, this.fileName);
  final AudioPlayer player;
  final String fileName;
}
