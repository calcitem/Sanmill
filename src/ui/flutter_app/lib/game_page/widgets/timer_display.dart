// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// timer_display.dart

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/player_timer.dart';

/// TimerDisplay
///
/// A widget that displays the remaining time for human player moves.
/// Only shown when a time limit is set for human players.
class TimerDisplay extends StatelessWidget {
  const TimerDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if human move time is enabled
    final int humanMoveTime = DB().generalSettings.humanMoveTime;
    if (humanMoveTime <= 0) {
      return const SizedBox.shrink(); // Don't show timer if no time limit
    }

    return ValueListenableBuilder<int>(
      valueListenable: PlayerTimer().remainingTimeNotifier,
      builder: (BuildContext context, int remainingTime, Widget? child) {
        // Format time as MM:SS
        final int minutes = remainingTime ~/ 60;
        final int seconds = remainingTime % 60;
        final String timeText =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        // Use red text when less than 10 seconds remaining
        final Color textColor = remainingTime < 10 ? Colors.red : Colors.black;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: remainingTime < 10 ? Colors.red : Colors.grey,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.timer,
                size: 16,
                color: textColor,
              ),
              const SizedBox(width: 4),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
