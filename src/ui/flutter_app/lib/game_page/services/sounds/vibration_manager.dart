// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// vibration_manager.dart

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
      final bool hasVibrator = await Vibration.hasVibrator();

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
      final bool hasVibrator = await Vibration.hasVibrator();

      if (hasVibrator != null && hasVibrator) {
        Vibration.cancel();
        logger.i("$_logTag Vibration canceled.");
      }
    }
  }
}
