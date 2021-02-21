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

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sanmill/common/config.dart';

class Audios {
  //
  static AudioPlayer _fixedBgmPlayer, _fixedTonePlayer;
  static AudioCache _bgmPlayer, _tonePlayer;

  static loopBgm(String fileName) async {
    if (_bgmPlayer == null) {
      _fixedBgmPlayer = AudioPlayer();
      _bgmPlayer = AudioCache(prefix: 'audios/', fixedPlayer: _fixedBgmPlayer);

      //await _bgmPlayer.loadAll(['bg_music.mp3']);
    }

    _fixedBgmPlayer.stop();
    _bgmPlayer.loop(fileName);
  }

  static playTone(String fileName) async {
    if (!Config.toneEnabled) {
      return;
    }

    if (_tonePlayer == null) {
      //
      _fixedTonePlayer = AudioPlayer();
      _tonePlayer =
          AudioCache(prefix: 'assets/audios/', fixedPlayer: _fixedTonePlayer);

      await _tonePlayer.loadAll([
        'draw.mp3',
        'go.mp3',
        'illegal.mp3',
        'mill.mp3',
        'fly.mp3',
        'lose.mp3',
        'place.mp3',
        'remove.mp3',
        'select.mp3',
        'win.mp3',
      ]);
    }

    //await _fixedTonePlayer.stop();
    await _fixedTonePlayer.pause();
    await _fixedTonePlayer.seek(Duration.zero);
    //await release();
    await _tonePlayer.play(fileName);
  }

  static stopBgm() {
    if (_fixedBgmPlayer != null) _fixedBgmPlayer.stop();
  }

  static Future<void> release() async {
    if (_fixedBgmPlayer != null) {
      await _fixedBgmPlayer.release();
    }
    if (_fixedTonePlayer != null) {
      await _fixedTonePlayer.release();
    }
  }
}
