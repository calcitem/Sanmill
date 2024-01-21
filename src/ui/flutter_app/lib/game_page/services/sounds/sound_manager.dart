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

  late Soundpool _soundpool;
  int _alarmSoundStreamId = 0;
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
  final Map<Sound, int> _soundIds = <Sound, int>{};
  bool _isTemporaryMute = false;

  static const String _logTag = "[audio]";

  Future<void> loadSounds() async {
    assert(!GameController().initialized);

    if (kIsWeb) {
      logger.w("$_logTag Audio Player does not support Web.");
      return;
    }

    _soundpool = Soundpool.fromOptions();

    for (final Sound sound in Sound.values) {
      _soundIds[sound] = await _soundpool.load(
        await rootBundle.load(_soundFiles[sound]!),
      );
    }
  }

  Future<void> _playSound(Sound sound) async {
    _alarmSoundStreamId = await _soundpool.play(_soundIds[sound]!);
  }

  Future<void> _stopSound() async {
    if (kIsWeb) {
      return;
    }

    if (_alarmSoundStreamId > 0) {
      await _soundpool.stop(_alarmSoundStreamId);
    }
  }

  void disposePool() {
    if (kIsWeb) {
      return;
    }

    _soundpool.dispose();
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
