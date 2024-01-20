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

  SoundManager._();

  @visibleForTesting
  static SoundManager instance = SoundManager._();

  bool _isTemporaryMute = false;

  static const String _logTag = "[audio]";

  Future<void> loadSounds() async {
    assert(!GameController().initialized);

    if (kIsWeb) {
      logger.w("$_logTag Audio Player does not support Web.");
      return;
    }
  }

  Future<void> _playSound(Sound sound) async {

  }

  Future<void> _stopSound() async {
    if (kIsWeb) {
      return;
    }
  }

  void disposePool() {
    if (kIsWeb) {
      return;
    }


  }

  Future<void> playTone(Sound sound) async {
    if (kIsWeb) {
      return;
    }

    assert(GameController().initialized);

    if (!DB().generalSettings.toneEnabled ||
        _isTemporaryMute ||
        DB().generalSettings.screenReaderSupport) {
      return;
    }

    await _stopSound();
    await _playSound(sound);
  }

  void mute() {
    _isTemporaryMute = true;
  }

  void unMute() {
    _isTemporaryMute = false;
  }
}
