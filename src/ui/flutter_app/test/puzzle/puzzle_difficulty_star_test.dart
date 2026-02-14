// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_difficulty_star_test.dart
//
// Tests for PuzzleDifficulty starThreshold and PuzzleProgress.calculateStars.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // PuzzleDifficulty.starThreshold
  // ---------------------------------------------------------------------------
  group('PuzzleDifficulty.starThreshold', () {
    test('beginner should have threshold of 3', () {
      expect(PuzzleDifficulty.beginner.starThreshold, 3);
    });

    test('easy should have threshold of 2', () {
      expect(PuzzleDifficulty.easy.starThreshold, 2);
    });

    test('medium should have threshold of 1', () {
      expect(PuzzleDifficulty.medium.starThreshold, 1);
    });

    test('hard should have threshold of 1', () {
      expect(PuzzleDifficulty.hard.starThreshold, 1);
    });

    test('expert should have threshold of 0', () {
      expect(PuzzleDifficulty.expert.starThreshold, 0);
    });

    test('master should have threshold of 0', () {
      expect(PuzzleDifficulty.master.starThreshold, 0);
    });

    test(
      'thresholds should decrease or stay same with increasing difficulty',
      () {
        int prevThreshold = PuzzleDifficulty.values.first.starThreshold;
        for (int i = 1; i < PuzzleDifficulty.values.length; i++) {
          final int current = PuzzleDifficulty.values[i].starThreshold;
          expect(
            current,
            lessThanOrEqualTo(prevThreshold),
            reason:
                '${PuzzleDifficulty.values[i]} threshold should be <= '
                '${PuzzleDifficulty.values[i - 1]} threshold',
          );
          prevThreshold = current;
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // PuzzleDifficulty enum
  // ---------------------------------------------------------------------------
  group('PuzzleDifficulty enum', () {
    test('should have six difficulty levels', () {
      expect(PuzzleDifficulty.values.length, 6);
    });

    test('should be ordered from beginner to master', () {
      expect(PuzzleDifficulty.values[0], PuzzleDifficulty.beginner);
      expect(PuzzleDifficulty.values[1], PuzzleDifficulty.easy);
      expect(PuzzleDifficulty.values[2], PuzzleDifficulty.medium);
      expect(PuzzleDifficulty.values[3], PuzzleDifficulty.hard);
      expect(PuzzleDifficulty.values[4], PuzzleDifficulty.expert);
      expect(PuzzleDifficulty.values[5], PuzzleDifficulty.master);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleCategory enum
  // ---------------------------------------------------------------------------
  group('PuzzleCategory enum', () {
    test('should have eight categories', () {
      expect(PuzzleCategory.values.length, 8);
    });

    test('should include all expected categories', () {
      expect(
        PuzzleCategory.values,
        containsAll(<PuzzleCategory>[
          PuzzleCategory.formMill,
          PuzzleCategory.capturePieces,
          PuzzleCategory.winGame,
          PuzzleCategory.defend,
          PuzzleCategory.findBestMove,
          PuzzleCategory.endgame,
          PuzzleCategory.opening,
          PuzzleCategory.mixed,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleProgress.calculateStars
  // ---------------------------------------------------------------------------
  group('PuzzleProgress.calculateStars', () {
    test('optimal move count should get 3 stars without hints', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
      );

      expect(stars, 3);
    });

    test('within threshold should get 2 stars without hints', () {
      // Easy threshold = 2, so optimal+2 should get 2 stars
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 5,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
      );

      expect(stars, 2);
    });

    test('within 2x threshold should get 1 star without hints', () {
      // Easy threshold = 2, so optimal + 2*2 = optimal + 4 should get 1 star
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 7,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
      );

      expect(stars, 1);
    });

    test('far over optimal should get 0 stars', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 100,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
      );

      expect(stars, 0);
    });

    test('with hints used, max 2 stars on optimal', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: true,
      );

      expect(stars, 2);
    });

    test('with hints used, within threshold gets 1 star', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 5,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: true,
      );

      expect(stars, 1);
    });

    test('with hints used, far over gets 0 stars', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 100,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: true,
      );

      expect(stars, 0);
    });

    test('solution viewed should always get 0 stars', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
        solutionViewed: true,
      );

      expect(stars, 0);
    });

    test('solution viewed + hints still gets 0 stars', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: true,
        solutionViewed: true,
      );

      expect(stars, 0);
    });

    test('expert difficulty with 0 threshold: exact or nothing', () {
      // Expert starThreshold = 0
      final int stars3 = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.expert,
        hintsUsed: false,
      );
      expect(stars3, 3);

      final int stars0 = PuzzleProgress.calculateStars(
        moveCount: 4,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.expert,
        hintsUsed: false,
      );
      expect(stars0, 0);
    });

    test('beginner difficulty is more lenient', () {
      // Beginner threshold = 3
      // optimal + 3 = 2 stars, optimal + 6 = 1 star
      final int stars2 = PuzzleProgress.calculateStars(
        moveCount: 6,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.beginner,
        hintsUsed: false,
      );
      expect(stars2, 2);

      final int stars1 = PuzzleProgress.calculateStars(
        moveCount: 9,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.beginner,
        hintsUsed: false,
      );
      expect(stars1, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleProgress model
  // ---------------------------------------------------------------------------
  group('PuzzleProgress', () {
    test('constructor defaults', () {
      final PuzzleProgress progress = PuzzleProgress(puzzleId: 'test-1');

      expect(progress.puzzleId, 'test-1');
      expect(progress.completed, isFalse);
      expect(progress.stars, 0);
      expect(progress.bestMoveCount, isNull);
      expect(progress.attempts, 0);
      expect(progress.hintsUsed, 0);
      expect(progress.solutionViewed, isFalse);
      expect(progress.lastAttemptDate, isNull);
      expect(progress.completionDate, isNull);
    });

    test('copyWith should override specified fields', () {
      final PuzzleProgress original = PuzzleProgress(puzzleId: 'test-1');
      final PuzzleProgress updated = original.copyWith(
        completed: true,
        stars: 3,
        bestMoveCount: 5,
        attempts: 2,
      );

      expect(updated.completed, isTrue);
      expect(updated.stars, 3);
      expect(updated.bestMoveCount, 5);
      expect(updated.attempts, 2);
      // Unchanged fields
      expect(updated.puzzleId, 'test-1');
      expect(updated.hintsUsed, 0);
    });

    test('toJson should include all fields', () {
      final DateTime now = DateTime(2026, 2, 14);
      final PuzzleProgress progress = PuzzleProgress(
        puzzleId: 'test-1',
        completed: true,
        stars: 3,
        bestMoveCount: 5,
        attempts: 2,
        hintsUsed: 1,
        solutionViewed: false,
        lastAttemptDate: now,
        completionDate: now,
      );

      final Map<String, dynamic> json = progress.toJson();

      expect(json['puzzleId'], 'test-1');
      expect(json['completed'], isTrue);
      expect(json['stars'], 3);
      expect(json['bestMoveCount'], 5);
      expect(json['attempts'], 2);
      expect(json['hintsUsed'], 1);
      expect(json['solutionViewed'], isFalse);
      expect(json['lastAttemptDate'], isNotNull);
      expect(json['completionDate'], isNotNull);
    });

    test('fromJson should parse all fields', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'puzzleId': 'test-2',
        'completed': true,
        'stars': 2,
        'bestMoveCount': 7,
        'attempts': 3,
        'hintsUsed': 1,
        'solutionViewed': true,
        'lastAttemptDate': '2026-02-14T00:00:00.000',
        'completionDate': '2026-02-14T00:00:00.000',
      };

      final PuzzleProgress progress = PuzzleProgress.fromJson(json);

      expect(progress.puzzleId, 'test-2');
      expect(progress.completed, isTrue);
      expect(progress.stars, 2);
      expect(progress.bestMoveCount, 7);
      expect(progress.attempts, 3);
      expect(progress.hintsUsed, 1);
      expect(progress.solutionViewed, isTrue);
      expect(progress.lastAttemptDate, isNotNull);
      expect(progress.completionDate, isNotNull);
    });

    test('fromJson with missing fields should use defaults', () {
      final PuzzleProgress progress = PuzzleProgress.fromJson(<String, dynamic>{
        'puzzleId': 'minimal',
      });

      expect(progress.puzzleId, 'minimal');
      expect(progress.completed, isFalse);
      expect(progress.stars, 0);
      expect(progress.bestMoveCount, isNull);
      expect(progress.attempts, 0);
      expect(progress.hintsUsed, 0);
      expect(progress.solutionViewed, isFalse);
    });

    test('toJson/fromJson round-trip', () {
      final DateTime now = DateTime(2026, 2, 14);
      final PuzzleProgress original = PuzzleProgress(
        puzzleId: 'round-trip',
        completed: true,
        stars: 3,
        bestMoveCount: 4,
        attempts: 1,
        hintsUsed: 0,
        solutionViewed: false,
        lastAttemptDate: now,
        completionDate: now,
      );

      final Map<String, dynamic> json = original.toJson();
      final PuzzleProgress restored = PuzzleProgress.fromJson(json);

      expect(restored.puzzleId, original.puzzleId);
      expect(restored.completed, original.completed);
      expect(restored.stars, original.stars);
      expect(restored.bestMoveCount, original.bestMoveCount);
      expect(restored.attempts, original.attempts);
      expect(restored.hintsUsed, original.hintsUsed);
      expect(restored.solutionViewed, original.solutionViewed);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleSolution model
  // ---------------------------------------------------------------------------
  group('PuzzleSolution', () {
    test('constructor defaults', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      );

      expect(solution.moves.length, 1);
      expect(solution.description, isNull);
      expect(solution.isOptimal, isTrue);
    });

    test('getPlayerMoves should filter by side', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'b2', side: PieceColor.black),
          PuzzleMove(notation: 'c3', side: PieceColor.white),
          PuzzleMove(notation: 'd4', side: PieceColor.black),
        ],
      );

      expect(solution.getPlayerMoves(PieceColor.white).length, 2);
      expect(solution.getPlayerMoves(PieceColor.black).length, 2);
    });

    test('getOpponentMoves should return opponent moves', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'b2', side: PieceColor.black),
          PuzzleMove(notation: 'c3', side: PieceColor.white),
        ],
      );

      expect(solution.getOpponentMoves(PieceColor.white).length, 1);
      expect(solution.getOpponentMoves(PieceColor.black).length, 2);
    });

    test('getPlayerMoveCount should return count', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'b2', side: PieceColor.black),
          PuzzleMove(notation: 'c3', side: PieceColor.white),
        ],
      );

      expect(solution.getPlayerMoveCount(PieceColor.white), 2);
      expect(solution.getPlayerMoveCount(PieceColor.black), 1);
    });

    test('equality should work for identical solutions', () {
      const PuzzleSolution s1 = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      );
      const PuzzleSolution s2 = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      );

      expect(s1, equals(s2));
    });

    test('toString should contain move count', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'b2', side: PieceColor.black),
        ],
      );

      expect(solution.toString(), contains('2 moves'));
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleMove model
  // ---------------------------------------------------------------------------
  group('PuzzleMove', () {
    test('should store notation and side', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd6',
        side: PieceColor.white,
      );

      expect(move.notation, 'd6');
      expect(move.side, PieceColor.white);
      expect(move.comment, isNull);
    });

    test('should accept optional comment', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd6',
        side: PieceColor.white,
        comment: 'Good opening move',
      );

      expect(move.comment, 'Good opening move');
    });

    test('toJson should include all fields', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'xa1',
        side: PieceColor.black,
        comment: 'Capture!',
      );

      final Map<String, dynamic> json = move.toJson();

      expect(json['notation'], 'xa1');
      expect(json['side'], 'black');
      expect(json['comment'], 'Capture!');
    });

    test('toJson should omit null comment', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd6',
        side: PieceColor.white,
      );

      final Map<String, dynamic> json = move.toJson();
      expect(json.containsKey('comment'), isFalse);
    });

    test('fromJson should parse correctly', () {
      final PuzzleMove move = PuzzleMove.fromJson(<String, dynamic>{
        'notation': 'b4',
        'side': 'white',
        'comment': 'Defense',
      });

      expect(move.notation, 'b4');
      expect(move.side, PieceColor.white);
      expect(move.comment, 'Defense');
    });

    test('equality should work', () {
      const PuzzleMove m1 = PuzzleMove(notation: 'a1', side: PieceColor.white);
      const PuzzleMove m2 = PuzzleMove(notation: 'a1', side: PieceColor.white);

      expect(m1, equals(m2));
      expect(m1.hashCode, m2.hashCode);
    });

    test('different notation should not be equal', () {
      const PuzzleMove m1 = PuzzleMove(notation: 'a1', side: PieceColor.white);
      const PuzzleMove m2 = PuzzleMove(notation: 'b2', side: PieceColor.white);

      expect(m1, isNot(equals(m2)));
    });

    test('toString should contain notation and side', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd6',
        side: PieceColor.black,
      );

      expect(move.toString(), contains('d6'));
      expect(move.toString(), contains('black'));
    });
  });
}
