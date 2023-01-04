// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

/// Sounds the [Audios] can play through [Audios.playTone].
enum Sound { draw, fly, go, illegal, lose, mill, place, remove, select, win }

/// Audio Service
///
/// Service providing a unified abstraction to call different audio backend on our supported platforms.
class Audios {
  factory Audios() => instance;

  Audios._();

  @visibleForTesting
  static Audios instance = Audios._();

  late Soundpool _soundpool;
  int _alarmSoundStreamId = 0;
  late int _drawSoundId;
  late int _flySoundId;
  late int _goSoundId;
  late int _illegalSoundId;
  late int _loseSoundId;
  late int _millSoundId;
  late int _placeSoundId;
  late int _removeSoundId;
  late int _selectSoundId;
  late int _winSoundId;
  bool _isTemporaryMute = false;

  static const String _tag = "[audio]";

  Future<void> loadSounds() async {
    assert(!MillController().initialized);

    if (kIsWeb) {
      logger.w("$_tag Audio Player does not support Web.");
      return;
    }

    _soundpool = Soundpool.fromOptions();

    _drawSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.draw),
    );

    _flySoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.fly),
    );

    _goSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.go),
    );

    _illegalSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.illegal),
    );

    _loseSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.lose),
    );

    _millSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.mill),
    );

    _placeSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.place),
    );

    _removeSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.remove),
    );

    _selectSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.select),
    );

    _winSoundId = await _soundpool.load(
      await rootBundle.load(Assets.audios.win),
    );
  }

  Future<void> _playSound(Sound sound) async {
    final int soundId;

    switch (sound) {
      case Sound.draw:
        soundId = _drawSoundId;
        break;
      case Sound.fly:
        soundId = _flySoundId;
        break;
      case Sound.go:
        soundId = _goSoundId;
        break;
      case Sound.illegal:
        soundId = _illegalSoundId;
        break;
      case Sound.lose:
        soundId = _loseSoundId;
        break;
      case Sound.mill:
        soundId = _millSoundId;
        break;
      case Sound.place:
        soundId = _placeSoundId;
        break;
      case Sound.remove:
        soundId = _removeSoundId;
        break;
      case Sound.select:
        soundId = _selectSoundId;
        break;
      case Sound.win:
        soundId = _winSoundId;
        break;
    }

    _alarmSoundStreamId = await _soundpool.play(soundId);
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

    assert(MillController().initialized);

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
