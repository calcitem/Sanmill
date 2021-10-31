/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/assets/assets.gen.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:soundpool/soundpool.dart';
import 'package:stack_trace/stack_trace.dart';

enum Sound {
  draw,
  fly,
  go,
  illegal,
  lose,
  mill,
  place,
  remove,
  select,
  win,
}

class Audios {
  const Audios._();
  //static AudioPlayer? _player;
  static final Soundpool _soundpool = Soundpool.fromOptions();
  static bool _initialized = false;
  static int _alarmSoundStreamId = 0;
  static late final int _drawSoundId;
  static late final int _flySoundId;
  static late final int _goSoundId;
  static late final int _illegalSoundId;
  static late final int _loseSoundId;
  static late final int _millSoundId;
  static late final int _placeSoundId;
  static late final int _removeSoundId;
  static late final int _selectSoundId;
  static late final int _winSoundId;
  static bool isTemporaryMute = false;

  static const _tag = '[audio]';

  static Future<void> loadSounds() async {
    if (Platform.isWindows) {
      debugPrint("$_tag Audio Player does not support Windows.");
      return;
    }

    if (_initialized) {
      debugPrint("$_tag Audio Player is already initialized.");
      return;
    }

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

    _initialized = true;
  }

  static Future<void> _playSound(Sound sound) async {
    assert(!Platform.isWindows);

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

  static Future<void> _stopSound() async {
    assert(!Platform.isWindows);

    if (_alarmSoundStreamId > 0) {
      await _soundpool.stop(_alarmSoundStreamId);
    }
  }

  static void disposePool() {
    assert(!Platform.isWindows);

    _soundpool.dispose();
  }

  static Future<void> playTone(Sound sound) async {
    await Chain.capture(() async {
      if (!LocalDatabaseService.preferences.toneEnabled ||
          isTemporaryMute ||
          LocalDatabaseService.preferences.screenReaderSupport ||
          !_initialized) {
        return;
      }

      // If the platform is Windows [_initialized] should be false thus this code shouldn't be executed
      if (Platform.isWindows) {
        assert(false);
      }

      // TODO: isn't debug chain meant to catch errors? so why catching them in here and not in onError??
      try {
        await _stopSound();

        await _playSound(sound);
      } catch (e) {
        // Fallback for all errors
        debugPrint(e.toString());
      }
    });
  }
}
