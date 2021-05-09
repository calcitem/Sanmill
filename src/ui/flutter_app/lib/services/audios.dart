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

import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:soundpool/soundpool.dart';
import 'package:stack_trace/stack_trace.dart';

class Audios {
  //static AudioPlayer? _player;
  static Soundpool? _soundpool;
  static int? _alarmSoundStreamId;
  static var drawSoundId;
  static var flySoundId;
  static var goSoundId;
  static var illegalSoundId;
  static var loseSoundId;
  static var millSoundId;
  static var placeSoundId;
  static var removeSoundId;
  static var selectSoundId;
  static var winSoundId;

  static Future<void> loadSounds() async {
    if (Platform.isWindows) {
      return;
    }

    _soundpool ??= Soundpool();

    drawSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/draw.mp3"));
    flySoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/fly.mp3"));
    goSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/go.mp3"));
    illegalSoundId = await _soundpool!
        .load(await rootBundle.load("assets/audios/illegal.mp3"));
    loseSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/lose.mp3"));
    millSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/mill.mp3"));
    placeSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/place.mp3"));
    removeSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/remove.mp3"));
    selectSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/select.mp3"));
    winSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/win.mp3"));
  }

  static Future<void> _playSound(var soundId) async {
    if (Platform.isWindows) {
      return;
    }

    _alarmSoundStreamId = await _soundpool!.play(await soundId);
  }

  static Future<void> _stopSound() async {
    if (Platform.isWindows) {
      return;
    }

    if (_alarmSoundStreamId != null && _alarmSoundStreamId! > 0) {
      await _soundpool!.stop(_alarmSoundStreamId!);
    }
  }

  static Future<void> disposePool() async {
    if (Platform.isWindows) {
      return;
    }

    _soundpool!.dispose();
  }

  static playTone(var soundId) async {
    Chain.capture(() async {
      if (!Config.toneEnabled) {
        return;
      }

      if (Platform.isWindows) {
        print("audio players is not support Windows.");
        return;
      }

      try {
        if (_soundpool == null) {
          await loadSounds();
        }

        await _stopSound();

        _playSound(soundId);
      } catch (e) {
        // Fallback for all errors
        print(e);
      }
    });
  }
}
