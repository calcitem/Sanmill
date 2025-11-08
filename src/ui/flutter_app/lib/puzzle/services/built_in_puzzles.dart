// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// built_in_puzzles.dart
//
// Collection of built-in puzzles

import '../models/puzzle_models.dart';

/// Get the collection of built-in puzzles
List<PuzzleInfo> getBuiltInPuzzles() {
  return <PuzzleInfo>[
    // Beginner Puzzles - Form Mill
    PuzzleInfo(
      id: 'beginner_001',
      title: 'First Mill',
      description: 'Form your first mill in 1 move',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.beginner,
      // Position with 2 pieces on a line, empty spot ready for mill
      initialPosition: 'p1/p1/3/3/3/3/3/3 w p 9 9 0',
      solutionMoves: <List<String>>[
        <String>['a1'],
      ],
      optimalMoveCount: 1,
      hint: 'Look for two pieces in a row. Place your piece to complete the line.',
      tags: <String>['beginner', 'mill', 'placement'],
    ),
    PuzzleInfo(
      id: 'beginner_002',
      title: 'Corner Mill',
      description: 'Form a mill using corner positions',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.beginner,
      initialPosition: 'p1/2p/3/3/3/3/3/3 w p 8 9 0',
      solutionMoves: <List<String>>[
        <String>['g1'],
      ],
      optimalMoveCount: 1,
      hint: 'Complete the mill in the corner positions.',
      tags: <String>['beginner', 'mill', 'corners'],
    ),

    // Easy Puzzles - Capture Pieces
    PuzzleInfo(
      id: 'easy_001',
      title: 'Double Mill Setup',
      description: 'Set up a double mill threat in 2 moves',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.easy,
      initialPosition: 'p1p/3/3/p2/3/3/3/p2 w p 7 7 0',
      solutionMoves: <List<String>>[
        <String>['d1', 'd4'],
      ],
      optimalMoveCount: 2,
      hint: 'Place pieces to create two potential mills at once.',
      tags: <String>['easy', 'double-mill', 'tactics'],
    ),
    PuzzleInfo(
      id: 'easy_002',
      title: 'Capture Two',
      description: 'Capture two opponent pieces in 3 moves',
      category: PuzzleCategory.capturePieces,
      difficulty: PuzzleDifficulty.easy,
      initialPosition: 'p1p/2p/3/p1p/3/2p/3/3 w p 6 5 0',
      solutionMoves: <List<String>>[
        <String>['d2', 'x-f2', 'd4', 'x-f4'],
      ],
      optimalMoveCount: 4,
      hint: 'Form mills to remove opponent pieces strategically.',
      tags: <String>['easy', 'capture', 'mill'],
    ),

    // Medium Puzzles - Win Game
    PuzzleInfo(
      id: 'medium_001',
      title: 'Endgame Victory',
      description: 'Win the game in 4 moves',
      category: PuzzleCategory.winGame,
      difficulty: PuzzleDifficulty.medium,
      initialPosition: 'p1p/3/3/3/p2/2p/3/3 w m 3 3 0',
      solutionMoves: <List<String>>[
        <String>['a1-d1', 'd1-d2', 'd2-f2'],
      ],
      optimalMoveCount: 3,
      hint: 'Position your pieces to trap the opponent.',
      tags: <String>['medium', 'endgame', 'win'],
    ),
    PuzzleInfo(
      id: 'medium_002',
      title: 'Forced Capture',
      description: 'Force opponent into a losing position',
      category: PuzzleCategory.winGame,
      difficulty: PuzzleDifficulty.medium,
      initialPosition: 'p2/p1p/3/3/3/p2/3/p1p w m 3 4 0',
      solutionMoves: <List<String>>[
        <String>['a1-a4', 'a4-d4', 'd4-d1'],
      ],
      optimalMoveCount: 3,
      hint: 'Control key positions to limit opponent moves.',
      tags: <String>['medium', 'tactics', 'control'],
    ),

    // Hard Puzzles - Defense
    PuzzleInfo(
      id: 'hard_001',
      title: 'Defensive Mastery',
      description: 'Defend against a double mill threat',
      category: PuzzleCategory.defend,
      difficulty: PuzzleDifficulty.hard,
      initialPosition: 'p1p/p2/3/3/p1p/3/3/p2 w m 3 5 0',
      solutionMoves: <List<String>>[
        <String>['d1-d2', 'd2-f2'],
      ],
      optimalMoveCount: 2,
      hint: 'Block the opponent\'s mill formation path.',
      tags: <String>['hard', 'defense', 'tactics'],
    ),
    PuzzleInfo(
      id: 'hard_002',
      title: 'Complex Endgame',
      description: 'Navigate a complex endgame to victory',
      category: PuzzleCategory.endgame,
      difficulty: PuzzleDifficulty.hard,
      initialPosition: 'p2/3/p1p/3/3/p1p/3/3 w m 3 4 0',
      solutionMoves: <List<String>>[
        <String>['a1-a4', 'c3-c6', 'a4-d4'],
      ],
      optimalMoveCount: 3,
      hint: 'Use flying moves strategically when you have 3 pieces.',
      tags: <String>['hard', 'endgame', 'flying'],
    ),

    // Expert Puzzles
    PuzzleInfo(
      id: 'expert_001',
      title: 'Triple Mill Threat',
      description: 'Create a triple mill threat in the opening',
      category: PuzzleCategory.opening,
      difficulty: PuzzleDifficulty.expert,
      initialPosition: 'p1p/3/3/p2/3/3/3/3 w p 7 8 0',
      solutionMoves: <List<String>>[
        <String>['d1', 'd2', 'd3'],
      ],
      optimalMoveCount: 3,
      hint: 'Control the central positions for maximum flexibility.',
      tags: <String>['expert', 'opening', 'strategy'],
    ),
    PuzzleInfo(
      id: 'expert_002',
      title: 'Sacrifice and Win',
      description: 'Sacrifice a piece to create a winning position',
      category: PuzzleCategory.findBestMove,
      difficulty: PuzzleDifficulty.expert,
      initialPosition: 'p1p/p2/3/p1p/3/3/p2/3 w m 4 4 0',
      solutionMoves: <List<String>>[
        <String>['a1-d1', 'd1-d4', 'd4-a4'],
      ],
      optimalMoveCount: 3,
      hint: 'Sometimes giving up a piece leads to a stronger position.',
      tags: <String>['expert', 'sacrifice', 'tactics'],
    ),

    // Master Puzzles
    PuzzleInfo(
      id: 'master_001',
      title: 'Master Tactician',
      description: 'Find the winning combination in a complex position',
      category: PuzzleCategory.mixed,
      difficulty: PuzzleDifficulty.master,
      initialPosition: 'p1p/p1p/3/p1p/3/p2/3/p1p w m 4 6 0',
      solutionMoves: <List<String>>[
        <String>['a1-a7', 'a7-g7', 'g7-g1'],
      ],
      optimalMoveCount: 3,
      hint: 'Look for the sequence that forces opponent into zugzwang.',
      tags: <String>['master', 'complex', 'zugzwang'],
    ),
    PuzzleInfo(
      id: 'master_002',
      title: 'Perfect Play',
      description: 'Demonstrate perfect endgame technique',
      category: PuzzleCategory.endgame,
      difficulty: PuzzleDifficulty.master,
      initialPosition: 'p2/3/p1p/3/3/p1p/3/3 w m 3 4 0',
      solutionMoves: <List<String>>[
        <String>['a1-d1', 'c3-f3', 'd1-d2', 'f3-d3'],
      ],
      optimalMoveCount: 4,
      hint: 'Each move must restrict opponent\'s options progressively.',
      tags: <String>['master', 'endgame', 'perfect-play'],
    ),
  ];
}
