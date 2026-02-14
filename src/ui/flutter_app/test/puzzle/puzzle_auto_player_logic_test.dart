// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_auto_player_logic_test.dart
//
// Tests for PuzzleAutoPlayer pure logic helpers.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/services/puzzle_auto_player.dart';
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
  // normalizeMove
  // ---------------------------------------------------------------------------
  group('PuzzleAutoPlayer.normalizeMove', () {
    test('should lowercase the move', () {
      expect(PuzzleAutoPlayer.normalizeMove('D6'), 'd6');
      expect(PuzzleAutoPlayer.normalizeMove('XA1'), 'xa1');
    });

    test('should trim whitespace', () {
      expect(PuzzleAutoPlayer.normalizeMove('  d6  '), 'd6');
      expect(PuzzleAutoPlayer.normalizeMove('\ta1\n'), 'a1');
    });

    test('should handle move notation with dash', () {
      expect(PuzzleAutoPlayer.normalizeMove('A1-A4'), 'a1-a4');
    });

    test('should handle empty string', () {
      expect(PuzzleAutoPlayer.normalizeMove(''), '');
    });
  });

  // ---------------------------------------------------------------------------
  // pickSolutionForPrefix
  // ---------------------------------------------------------------------------
  group('PuzzleAutoPlayer.pickSolutionForPrefix', () {
    test('should return null for empty solutions', () {
      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: <List<String>>[],
        movesSoFar: <String>['d6'],
      );
      expect(result, isNull);
    });

    test('should return first matching solution for empty prefix', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6', 'f4', 'b4'],
        <String>['a1', 'g7', 'd5'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>[],
      );

      expect(result, solutions.first);
    });

    test('should match prefix correctly', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6', 'f4', 'b4'],
        <String>['a1', 'g7', 'd5'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['a1'],
      );

      expect(result, solutions[1]);
    });

    test('should return null when no solution matches prefix', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6', 'f4', 'b4'],
        <String>['a1', 'g7', 'd5'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['c3'],
      );

      expect(result, isNull);
    });

    test('should handle case-insensitive prefix matching', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['D6', 'F4'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['d6'],
      );

      expect(result, isNotNull);
    });

    test('should return null when prefix is longer than solution', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['d6', 'f4'],
      );

      expect(result, isNull);
    });

    test('should match exact solution', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6', 'f4', 'b4'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['d6', 'f4', 'b4'],
      );

      expect(result, solutions.first);
    });

    test('should prefer first matching when multiple match', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['d6', 'f4', 'b4'],
        <String>['d6', 'f4', 'a1'],
      ];

      final List<String>? result = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['d6', 'f4'],
      );

      // Should return first matching solution
      expect(result, solutions.first);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleAutoPlayOutcome enum
  // ---------------------------------------------------------------------------
  group('PuzzleAutoPlayOutcome', () {
    test('should have five values', () {
      expect(PuzzleAutoPlayOutcome.values.length, 5);
    });

    test('should include all expected values', () {
      expect(
        PuzzleAutoPlayOutcome.values,
        containsAll(<PuzzleAutoPlayOutcome>[
          PuzzleAutoPlayOutcome.noOp,
          PuzzleAutoPlayOutcome.playedMoves,
          PuzzleAutoPlayOutcome.wrongMove,
          PuzzleAutoPlayOutcome.reachedEndOfLine,
          PuzzleAutoPlayOutcome.illegalAutoMove,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // autoPlayOpponentResponses - with simulated callbacks
  // ---------------------------------------------------------------------------
  group('PuzzleAutoPlayer.autoPlayOpponentResponses', () {
    test('should return noOp when game is over', () async {
      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: <List<String>>[
          <String>['d6', 'f4'],
        ],
        humanColor: PieceColor.white,
        isGameOver: () => true,
        sideToMove: () => PieceColor.black,
        movesSoFar: () => <String>[],
        applyMove: (String move) => true,
        onWrongMove: () async {},
      );

      expect(outcome, PuzzleAutoPlayOutcome.noOp);
    });

    test('should return noOp when it is human turn', () async {
      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: <List<String>>[
          <String>['d6', 'f4'],
        ],
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => PieceColor.white, // Human's turn
        movesSoFar: () => <String>[],
        applyMove: (String move) => true,
        onWrongMove: () async {},
      );

      expect(outcome, PuzzleAutoPlayOutcome.noOp);
    });

    test('should play moves until human turn', () async {
      // Simulate: black plays one move, then it's white's (human) turn
      int moveCount = 0;
      PieceColor currentSide = PieceColor.black;

      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: <List<String>>[
          <String>['d6', 'f4', 'b4'],
        ],
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => currentSide,
        movesSoFar: () => <String>['d6'].sublist(0, moveCount),
        applyMove: (String move) {
          moveCount++;
          currentSide = PieceColor.white; // Switch to human
          return true;
        },
        onWrongMove: () async {},
      );

      expect(outcome, PuzzleAutoPlayOutcome.playedMoves);
      expect(moveCount, 1);
    });

    test('should return wrongMove when no solution matches', () async {
      bool wrongMoveCalled = false;

      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: <List<String>>[
          <String>['d6', 'f4'],
        ],
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => PieceColor.black,
        movesSoFar: () => <String>['c3'], // Not matching any solution
        applyMove: (String move) => true,
        onWrongMove: () async {
          wrongMoveCalled = true;
        },
      );

      expect(outcome, PuzzleAutoPlayOutcome.wrongMove);
      expect(wrongMoveCalled, isTrue);
    });

    test('should return reachedEndOfLine at solution end', () async {
      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: <List<String>>[
          <String>['d6'],
        ],
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => PieceColor.black,
        movesSoFar: () => <String>['d6'], // Already at end
        applyMove: (String move) => true,
        onWrongMove: () async {},
      );

      expect(outcome, PuzzleAutoPlayOutcome.reachedEndOfLine);
    });
  });
}
