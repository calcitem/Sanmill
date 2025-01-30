// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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

  bool _isTemporaryMute = false;

  bool _allSoundsLoaded = false;

  static const String _logTag = "[audio]";

  Future<void> loadSounds() async {
    soundThemeName = DB().generalSettings.soundTheme?.name ?? 'ball';

    final Map<Sound, String>? sounds = _soundFiles[soundThemeName];
    if (sounds == null) {
      logger.e("No sound files found for theme $soundThemeName.");
      return;
    }

    try {
      for (final Sound sound in sounds.keys) {
        // Adjust the file path by replacing 'assets/' with ''.
        final String fileName = sounds[sound]!.replaceFirst('assets/', '');
        final AudioPlayer player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        // No need to set the source here; we'll set it and play immediately in playTone.
        _players[sound] = SoundPlayer(player, fileName);
      }
      _allSoundsLoaded = true;
    } catch (e) {
      logger.e("Failed to load sound: $e");
      _allSoundsLoaded = false;
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
      // Set the source and play immediately to avoid delays on Linux.
      await soundPlayer.player.play(AssetSource(soundPlayer.fileName));
    } catch (e) {
      logger.e("$_logTag Error playing sound: $e");
    }
  }

  void mute() {
    _isTemporaryMute = true;
  }

  void unMute() {
    _isTemporaryMute = false;
  }

  void disposePool() {
    _players.forEach((_, SoundPlayer soundPlayer) {
      soundPlayer.player.dispose();
    });
    _players.clear();
  }
}

/// Helper class to store AudioPlayer and associated fileName.
class SoundPlayer {
  SoundPlayer(this.player, this.fileName);
  final AudioPlayer player;
  final String fileName;
}
