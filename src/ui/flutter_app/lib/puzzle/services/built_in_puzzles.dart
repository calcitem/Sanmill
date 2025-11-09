// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// built_in_puzzles.dart
//
// Collection of built-in puzzles

import '../models/puzzle_models.dart';

/// Get the collection of built-in puzzles
///
/// FEN Format: [Ring1]/[Ring2]/[Ring3] [Side] [Phase] [Action]
///   [WhiteOnBoard] [WhiteInHand] [BlackOnBoard] [BlackInHand]
///   [WhiteToRemove] [BlackToRemove]
///   [WhiteLastMillFrom] [WhiteLastMillTo] [BlackLastMillFrom] [BlackLastMillTo]
///   [MillsBitmask] [Rule50] [Ply]
///
/// Where:
/// - Ring: @ = Black, O = White, * = Empty, X = Marked
/// - Side: w = White, b = Black
/// - Phase: r = Ready, p = Placing, m = Moving, o = GameOver
/// - Action: p = Place, s = Select, r = Remove
List<PuzzleInfo> getBuiltInPuzzles() {
  return <PuzzleInfo>[
    // Beginner Puzzles - Form Mill
    PuzzleInfo(
      id: 'beginner_001',
      title: 'First Mill',
      description: 'Form your first mill in 1 move',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.beginner,
      // White has two pieces in a row, needs one more to form a mill
      initialPosition:
          'OO*****/*******/******* w p p 2 7 0 9 0 0 0 0 0 0 0 0 1',
      solutionMoves: <List<String>>[
        <String>['c1'], // Complete the mill
      ],
      optimalMoveCount: 1,
      hint:
          'Look for two pieces in a row. Place your piece to complete the line.',
      tags: <String>['beginner', 'mill', 'placement'],
    ),
    PuzzleInfo(
      id: 'beginner_002',
      title: 'Corner Mill',
      description: 'Form a mill using corner positions',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.beginner,
      // White needs to complete a vertical mill
      initialPosition:
          'O******/*******/O****** w p p 2 7 0 9 0 0 0 0 0 0 0 0 1',
      solutionMoves: <List<String>>[
        <String>['a4'], // Complete vertical mill
      ],
      optimalMoveCount: 1,
      hint: 'Complete the mill in the corner positions.',
      tags: <String>['beginner', 'mill', 'corners'],
    ),

    // Easy Puzzles - Multiple Mills
    PuzzleInfo(
      id: 'easy_001',
      title: 'Double Threat',
      description: 'Create a double mill threat in 2 moves',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.easy,
      // Position allowing double mill setup
      initialPosition:
          'O*O**@@/O*O**@@/******* w p p 4 5 4 5 0 0 0 0 0 0 0 0 1',
      solutionMoves: <List<String>>[
        <String>['b1', 'd2'], // Create two mill threats
      ],
      optimalMoveCount: 2,
      hint: 'Place pieces to create two potential mills at once.',
      tags: <String>['easy', 'double-mill', 'tactics'],
    ),
    PuzzleInfo(
      id: 'easy_002',
      title: 'Capture and Win',
      description: 'Form a mill and capture an opponent piece',
      category: PuzzleCategory.capturePieces,
      difficulty: PuzzleDifficulty.easy,
      // Position where forming a mill leads to capture
      initialPosition:
          'OO***@@/*******/@****** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1',
      solutionMoves: <List<String>>[
        <String>['c1', 'xf1'], // Form mill then remove
      ],
      optimalMoveCount: 2,
      hint: 'Form a mill to remove an opponent piece.',
      tags: <String>['easy', 'capture', 'mill'],
    ),

    // Medium Puzzles - Moving Phase
    PuzzleInfo(
      id: 'medium_001',
      title: 'Tactical Movement',
      description: 'Win by moving pieces strategically',
      category: PuzzleCategory.winGame,
      difficulty: PuzzleDifficulty.medium,
      // Moving phase with winning combination
      initialPosition:
          'O@O****/O@O****/******* w m s 3 0 3 0 0 0 0 0 0 0 0 0 5',
      solutionMoves: <List<String>>[
        <String>['a1-d1', 'd1-d2'], // Winning moves
      ],
      optimalMoveCount: 2,
      hint: 'Position your pieces to form a mill by moving.',
      tags: <String>['medium', 'moving', 'tactics'],
    ),
    PuzzleInfo(
      id: 'medium_002',
      title: 'Forcing Move',
      description: 'Force opponent into a losing position',
      category: PuzzleCategory.winGame,
      difficulty: PuzzleDifficulty.medium,
      // Complex mid-game position
      initialPosition:
          '*O@**O@/*O@**O@/******* w m s 4 0 4 0 0 0 0 0 0 0 0 0 6',
      solutionMoves: <List<String>>[
        <String>['b1-a1', 'b2-b1'], // Force winning position
      ],
      optimalMoveCount: 2,
      hint: 'Control key positions to limit opponent moves.',
      tags: <String>['medium', 'tactics', 'control'],
    ),

    // Hard Puzzles - Defense and Complex Tactics
    PuzzleInfo(
      id: 'hard_001',
      title: 'Defensive Play',
      description: 'Defend against opponent threats',
      category: PuzzleCategory.defend,
      difficulty: PuzzleDifficulty.hard,
      // Defensive scenario
      initialPosition:
          'O@O*@*@/O@O*@*@/******* w m s 4 0 5 0 0 0 0 0 0 0 0 0 7',
      solutionMoves: <List<String>>[
        <String>['a1-d1'], // Block opponent's threat
      ],
      optimalMoveCount: 1,
      hint: "Block the opponent's mill formation path.",
      tags: <String>['hard', 'defense', 'tactics'],
    ),
    PuzzleInfo(
      id: 'hard_002',
      title: 'Endgame Mastery',
      description: 'Win in a complex endgame',
      category: PuzzleCategory.endgame,
      difficulty: PuzzleDifficulty.hard,
      // Three pieces each - flying phase
      initialPosition:
          'O**@***/O**@***/O**@*** w m s 3 0 3 0 0 0 0 0 0 0 0 0 10',
      solutionMoves: <List<String>>[
        <String>['a1-c1', 'c1-c2'], // Flying to win
      ],
      optimalMoveCount: 2,
      hint: 'Use flying moves strategically when you have 3 pieces.',
      tags: <String>['hard', 'endgame', 'flying'],
    ),

    // Expert Puzzles - Advanced Strategy
    PuzzleInfo(
      id: 'expert_001',
      title: 'Triple Threat',
      description: 'Create multiple mill threats simultaneously',
      category: PuzzleCategory.opening,
      difficulty: PuzzleDifficulty.expert,
      // Opening position with strategic potential
      initialPosition:
          'O*O*@@*/O******/******* w p p 3 6 3 6 0 0 0 0 0 0 0 0 3',
      solutionMoves: <List<String>>[
        <String>['b1', 'd1'], // Create multiple threats
      ],
      optimalMoveCount: 2,
      hint: 'Control central positions for maximum flexibility.',
      tags: <String>['expert', 'opening', 'strategy'],
    ),
    PuzzleInfo(
      id: 'expert_002',
      title: 'Precision Play',
      description: 'Find the only winning sequence',
      category: PuzzleCategory.findBestMove,
      difficulty: PuzzleDifficulty.expert,
      // Critical position with one correct solution
      initialPosition:
          'OO@@**@/*O@@**@/******* w m s 4 0 5 0 0 0 0 0 0 0 0 0 8',
      solutionMoves: <List<String>>[
        <String>['a1-a4', 'b2-b1'], // Precise sequence
      ],
      optimalMoveCount: 2,
      hint: 'Only one sequence leads to victory. Think carefully.',
      tags: <String>['expert', 'precision', 'tactics'],
    ),

    // Master Puzzles - Highest Difficulty
    PuzzleInfo(
      id: 'master_001',
      title: 'Master Tactician',
      description: 'Find the winning combination in a complex position',
      category: PuzzleCategory.mixed,
      difficulty: PuzzleDifficulty.master,
      // Extremely complex position
      initialPosition:
          'O@O@*@@/OO@@*@@/@****** w m s 5 0 6 0 0 0 0 0 0 0 0 0 12',
      solutionMoves: <List<String>>[
        <String>['a1-a7'], // Complex winning move
      ],
      optimalMoveCount: 1,
      hint: 'Look for the move that forces opponent into zugzwang.',
      tags: <String>['master', 'complex', 'zugzwang'],
    ),
    PuzzleInfo(
      id: 'master_002',
      title: 'Perfect Endgame',
      description: 'Demonstrate perfect endgame technique',
      category: PuzzleCategory.endgame,
      difficulty: PuzzleDifficulty.master,
      // Perfect play required
      initialPosition:
          'O**@***/O**@***/***@*** w m s 2 0 3 0 0 0 0 0 0 0 0 0 15',
      solutionMoves: <List<String>>[
        <String>['a1-c1', 'a2-c2'], // Perfect technique
      ],
      optimalMoveCount: 2,
      hint: 'Each move must restrict opponent options progressively.',
      tags: <String>['master', 'endgame', 'perfect-play'],
    ),
  ];
}
