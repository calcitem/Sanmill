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
  static var isTemporaryMute = false;

  static Future<void> loadSounds() async {
    if (Platform.isWindows) {
      return;
    }

    _soundpool ??= Soundpool.fromOptions();

    if (_soundpool == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: _soundpool is null.");
      return;
    }

    drawSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/draw.mp3"));
    if (drawSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: drawSoundId is null.");
      return;
    }

    flySoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/fly.mp3"));
    if (flySoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: flySoundId is null.");
      return;
    }

    goSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/go.mp3"));
    if (goSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: goSoundId is null.");
      return;
    }

    illegalSoundId = await _soundpool!
        .load(await rootBundle.load("assets/audios/illegal.mp3"));
    if (illegalSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: illegalSoundId is null.");
      return;
    }

    loseSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/lose.mp3"));
    if (loseSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: loseSoundId is null.");
      return;
    }

    millSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/mill.mp3"));
    if (millSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: millSoundId is null.");
      return;
    }

    placeSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/place.mp3"));
    if (placeSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: placeSoundId is null.");
      return;
    }

    removeSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/remove.mp3"));
    if (removeSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: removeSoundId is null.");
      return;
    }

    selectSoundId ??= await _soundpool!
        .load(await rootBundle.load("assets/audios/select.mp3"));
    if (selectSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: selectSoundId is null.");
      return;
    }

    winSoundId ??=
        await _soundpool!.load(await rootBundle.load("assets/audios/win.mp3"));
    if (winSoundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: winSoundId is null.");
      return;
    }
  }

  static Future<void> _playSound(var soundId) async {
    if (Platform.isWindows) {
      return;
    }

    if (soundId == null) {
      if (Config.developerMode) {
        assert(false);
      }
     debugPrint("[audio] Error: soundId is null.");
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
      if (!Config.toneEnabled ||
          isTemporaryMute ||
          Config.screenReaderSupport) {
        return;
      }

      if (Platform.isWindows) {
       debugPrint("audio players is not support Windows.");
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
       debugPrint(e.toString());
      }
    });
  }
}
