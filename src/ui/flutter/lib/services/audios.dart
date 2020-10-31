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
