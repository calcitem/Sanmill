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

class VibrationManager {
  factory VibrationManager() => instance;

  VibrationManager._();
  static bool booted = false;

  @visibleForTesting
  static VibrationManager instance = VibrationManager._();

  final Map<Sound, int> _vibrationDurations = <Sound, int>{
    Sound.draw: 200,
    Sound.illegal: 100,
    Sound.lose: 250,
    Sound.mill: 50,
    Sound.place: 10,
    Sound.remove: 20,
    Sound.select: 5,
    Sound.win: 300,
  };

  static const String _logTag = "[vibration]";

  Future<void> vibrate(Sound type) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final bool? hasVibrator = await Vibration.hasVibrator();

      if (hasVibrator != null && hasVibrator) {
        final int duration = _vibrationDurations[type] ?? 10;
        await Vibration.vibrate(duration: duration);
        logger.i(
            "$_logTag Vibration triggered for $type with duration $duration ms.");
      } else {
        logger.w("$_logTag Device does not support vibration.");
      }
    } else {
      logger.w("$_logTag Vibration is not supported on this platform.");
    }
  }

  Future<void> stopVibration() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final bool? hasVibrator = await Vibration.hasVibrator();

      if (hasVibrator != null && hasVibrator) {
        Vibration.cancel();
        logger.i("$_logTag Vibration canceled.");
      }
    }
  }
}
