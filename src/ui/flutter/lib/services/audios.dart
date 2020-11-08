/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';

class Audios {
  //
  static AudioPlayer _fixedBgmPlayer, _fixedTonePlayer;
  static AudioCache _bgmPlayer, _tonePlayer;

  static loopBgm(String fileName) async {
    //
    try {
      if (_bgmPlayer == null) {
        //
        _fixedBgmPlayer = AudioPlayer();
        _bgmPlayer =
            AudioCache(prefix: 'audios/', fixedPlayer: _fixedBgmPlayer);

        //await _bgmPlayer.loadAll(['bg_music.mp3']);
      }

      _fixedBgmPlayer.stop();
      _bgmPlayer.loop(fileName);
    } catch (e) {}
  }

  static playTone(String fileName) async {
    //
    try {
      if (_tonePlayer == null) {
        //
        _fixedTonePlayer = AudioPlayer();
        _tonePlayer =
            AudioCache(prefix: 'audios/', fixedPlayer: _fixedTonePlayer);
/*
        await _tonePlayer.loadAll([
          'capture.mp3',
          'check.mp3',
          'click.mp3',
          'regret.mp3',
          'draw.mp3',
          'tips.mp3',
          'invalid.mp3',
          'lose.mp3',
          'move.mp3',
          'win.mp3',
        ]);
*/
      }

      _fixedTonePlayer.stop();
      _tonePlayer.play(fileName);
    } catch (e) {}
  }

  static stopBgm() {
    try {
      if (_fixedBgmPlayer != null) _fixedBgmPlayer.stop();
    } catch (e) {}
  }

  static Future<void> release() async {
    try {
      if (_fixedBgmPlayer != null) {
        await _fixedBgmPlayer.release();
      }
      if (_fixedTonePlayer != null) {
        await _fixedTonePlayer.release();
      }
    } catch (e) {}
  }
}
