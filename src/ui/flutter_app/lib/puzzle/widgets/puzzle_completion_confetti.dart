// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/widgets/challenge_confetti.dart';
import '../models/puzzle_models.dart';

/// Confetti shown only after a puzzle has been solved successfully.
class PuzzleCompletionConfetti extends StatelessWidget {
  const PuzzleCompletionConfetti({required this.difficulty, super.key});

  static const Duration displayDuration = Duration(seconds: 8);

  final PuzzleDifficulty difficulty;

  /// Harder puzzles launch progressively more confetti per wave.
  static int particlesPerWaveFor(PuzzleDifficulty difficulty) {
    return switch (difficulty) {
      PuzzleDifficulty.beginner => 8,
      PuzzleDifficulty.easy => 12,
      PuzzleDifficulty.medium => 16,
      PuzzleDifficulty.hard => 20,
      PuzzleDifficulty.expert => 26,
      PuzzleDifficulty.master => 34,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ChallengeConfetti(
      key: const Key('puzzle_success_confetti'),
      particlesPerWave: particlesPerWaveFor(difficulty),
      numberOfWaves: 3,
    );
  }
}
