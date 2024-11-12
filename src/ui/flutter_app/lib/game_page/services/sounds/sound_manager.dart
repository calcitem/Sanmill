// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../mill.dart';

/// Sounds the [SoundManager] can play through [SoundManager.playTone].
enum Sound { draw, illegal, lose, mill, place, remove, select, win }

class SoundManager {
  factory SoundManager() => instance;

  SoundManager._();
  static bool booted = false;

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

  // Change to maintain a map of PlayerController instances for each sound.
  final Map<Sound, kplayer.PlayerController> _players =
      <Sound, kplayer.PlayerController>{};

  bool _isTemporaryMute = false;

  bool _allSoundsLoaded = false;

  static const String _logTag = "[audio]";

  Future<void> loadSounds() async {
    // assert(!GameController().initialized);

    if (kIsWeb) {
      logger.w("$_logTag Audio Player does not support Web.");
      return;
    }

    soundThemeName = DB().generalSettings.soundTheme?.name ?? 'ball';

    final Map<Sound, String>? sounds = _soundFiles[soundThemeName];
    if (sounds == null) {
      logger.e("No sound files found for theme $soundThemeName.");
      return;
    }

    if (Platform.isIOS || Platform.isLinux) {
      if (booted == true) {
        return;
      }

      kplayer.Player.boot();
      kplayer.PlayerController.enableLog = false;

      sounds.forEach((Sound sound, String fileName) {
        _players[sound] = kplayer.Player.asset(fileName, autoPlay: false);
      });

      booted = true;
      _allSoundsLoaded = true;
    }
  }

  Future<void> playTone(Sound sound) async {
    if (kIsWeb) {
      return;
    }

    assert(GameController().initialized);

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

    if (Platform.isIOS || Platform.isLinux) {
      await _stopAllSounds();

      final kplayer.PlayerController? player = _players[sound];
      if (player == null) {
        logger.e("No player found for sound $sound in theme $soundThemeName.");
        return;
      }
      try {
        await player.play();
      } catch (e) {
        logger.e("$_logTag Error playing sound: $e");
      }
    }
  }

  Future<void> _stopAllSounds() async {
    if (Platform.isIOS || Platform.isLinux) {
      final List<Future<void>> stopFutures = <Future<void>>[];
      _players.forEach((_, kplayer.PlayerController player) {
        stopFutures.add(player.stop());
      });
      await Future.wait(stopFutures);
    }
  }

  void mute() {
    _isTemporaryMute = true;
  }

  void unMute() {
    _isTemporaryMute = false;
  }

  void disposePool() {
    if (kIsWeb) {
      return;
    }

    if (Platform.isIOS || Platform.isLinux) {
      _players
          .forEach((_, kplayer.PlayerController player) => player.dispose());
      _players.clear();
    }
  }
}
