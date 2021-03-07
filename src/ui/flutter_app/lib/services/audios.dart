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

import 'package:just_audio/just_audio.dart';
import 'package:sanmill/common/config.dart';

class Audios {
  //
  static AudioPlayer? _player;

  static playTone(String fileName) async {
    if (!Config.toneEnabled) {
      return;
    }

    if (Platform.isWindows) {
      print(
          "audio players is not support Windows. See: https://pub.dev/packages/just_audio");
      return;
    }

    try {
      if (_player == null) {
        _player = AudioPlayer();
      }

      await _player!.stop();
      await _player!.setAsset("assets/audios/" + fileName);
      _player!.play();
    } on PlayerException catch (e) {
      // iOS/macOS: maps to NSError.code
      // Android: maps to ExoPlayerException.type
      // Web: maps to MediaError.code
      print("Error code: ${e.code}");
      // iOS/macOS: maps to NSError.localizedDescription
      // Android: maps to ExoPlaybackException.getMessage()
      // Web: a generic message
      print("Error message: ${e.message}");
    } on PlayerInterruptedException catch (e) {
      // This call was interrupted since another audio source was loaded or the
      // player was stopped or disposed before this audio source could complete
      // loading.
      print("Connection aborted: ${e.message}");
    } catch (e) {
      // Fallback for all errors
      print(e);
    }
  }

  static Future<void> release() async {
    if (_player != null) {
      await _player!.stop();
      await _player!.dispose();
    }
  }
}
