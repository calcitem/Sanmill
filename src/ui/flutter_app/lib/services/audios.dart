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

import 'package:kplayer/kplayer.dart';
import 'package:sanmill/generated/assets/assets.gen.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/storage/storage.dart';

enum Sound { draw, fly, go, illegal, lose, mill, place, remove, select, win }

class Audios {
  const Audios._();
  static bool isTemporaryMute = false;

  static Future<String> _playSound(Sound sound) async {
    final String media;

    switch (sound) {
      case Sound.draw:
        media = Assets.audios.draw;
        break;
      case Sound.fly:
        media = Assets.audios.fly;
        break;
      case Sound.go:
        media = Assets.audios.go;
        break;
      case Sound.illegal:
        media = Assets.audios.illegal;
        break;
      case Sound.lose:
        media = Assets.audios.lose;
        break;
      case Sound.mill:
        media = Assets.audios.mill;
        break;
      case Sound.place:
        media = Assets.audios.place;
        break;
      case Sound.remove:
        media = Assets.audios.remove;
        break;
      case Sound.select:
        media = Assets.audios.select;
        break;
      case Sound.win:
        media = Assets.audios.win;
        break;
    }

    Player.asset(media).play();

    return media;
  }

  static Future<void> _stopSound() async {
    // TODO: Implement stopping sound
  }

  static void disposePool() {
    // TODO: Implement disposing
  }

  static Future<void> playTone(Sound sound) async {
    if (!LocalDatabaseService.preferences.toneEnabled ||
        isTemporaryMute ||
        LocalDatabaseService.preferences.screenReaderSupport) {
      return;
    }

    try {
      await _stopSound();

      await _playSound(sound);
    } catch (e) {
      // Fallback for all errors
      logger.e(e.toString());
      rethrow;
    }
  }
}
