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
enum Sound { draw, fly, go, illegal, lose, mill, place, remove, select, win }

/// Sound Manager
///
/// Service providing a unified abstraction to call different audio backend on our supported platforms.
class SoundManager {
  factory SoundManager() => instance;
  static bool booted = false;

  SoundManager._();

  @visibleForTesting
  static SoundManager instance = SoundManager._();

  final Map<Sound, String> _soundFiles = <Sound, String>{
    Sound.draw: Assets.audios.draw,
    Sound.fly: Assets.audios.fly,
    Sound.go: Assets.audios.go,
    Sound.illegal: Assets.audios.illegal,
    Sound.lose: Assets.audios.lose,
    Sound.mill: Assets.audios.mill,
    Sound.place: Assets.audios.place,
    Sound.remove: Assets.audios.remove,
    Sound.select: Assets.audios.select,
    Sound.win: Assets.audios.win,
  };

  kplayer.PlayerController? _currentTonePlayer;
  bool _isTemporaryMute = false;

  static const String _logTag = "[audio]";

  Future<void> loadSounds() async {
    // Initialization is done in the Player.boot() method, called once, typically in your main() function.
    // No need to load sounds in advance with kplayer, as they are loaded on demand.
    if (booted == true) {
      return;
    }

    kplayer.Player.boot();
    booted = true;
  }

  Future<void> playTone(Sound sound) async {
    if (_isTemporaryMute || !DB().generalSettings.toneEnabled || DB().generalSettings.screenReaderSupport) {
      return;
    }

    final String fileName = _soundFiles[sound]!;
    try {
      // Dispose of the current tone player before playing a new sound
      _currentTonePlayer?.dispose();

      // Play the sound
      _currentTonePlayer = kplayer.Player.asset(fileName);
    } catch (e) {
      if (kDebugMode) {
        print("$_logTag Error playing sound: $e");
      }
    }
  }

  void mute() {
    _isTemporaryMute = true;
  }

  void unMute() {
    _isTemporaryMute = false;
  }

  void disposePool() {
    _currentTonePlayer?.dispose();
    _currentTonePlayer = null;
  }
}
