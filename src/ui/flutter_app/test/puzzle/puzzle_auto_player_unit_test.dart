// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/services/puzzle_auto_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PuzzleAutoPlayer.pickSolutionForPrefix', () {
    test(
      'matches prefix with normalization and picks the first stable line',
      () {
        final List<List<String>> solutions = <List<String>>[
          <String>['A1', 'b2'],
          <String>['a1', 'c3'],
        ];

        final List<String>? picked = PuzzleAutoPlayer.pickSolutionForPrefix(
          solutions: solutions,
          movesSoFar: <String>[' a1 '],
        );

        expect(picked, isNotNull);
        expect(picked, solutions.first);
      },
    );

    test('returns null when no solution matches the prefix', () {
      final List<List<String>> solutions = <List<String>>[
        <String>['a1', 'b2'],
        <String>['a1', 'c3'],
      ];

      final List<String>? picked = PuzzleAutoPlayer.pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: <String>['d4'],
      );

      expect(picked, isNull);
    });
  });

  group('PuzzleAutoPlayer.autoPlayOpponentResponses', () {
    test(
      'auto-plays consecutive opponent moves until it is the human turn',
      () async {
        final List<List<String>> solutions = <List<String>>[
          <String>['a1', 'b2', 'c3'],
        ];

        final List<String> moves = <String>['a1'];
        PieceColor sideToMove = PieceColor.black;

        int applyCount = 0;
        int undoCount = 0;

        final PuzzleAutoPlayOutcome
        outcome = await PuzzleAutoPlayer.autoPlayOpponentResponses(
          solutions: solutions,
          humanColor: PieceColor.white,
          isGameOver: () => false,
          sideToMove: () => sideToMove,
          movesSoFar: () => List<String>.unmodifiable(moves),
          applyMove: (String move) {
            moves.add(move);
            applyCount++;

            // Simulate a multi-step opponent turn:
            // keep opponent to move after the first move, then return to the human.
            if (applyCount == 1) {
              sideToMove = PieceColor.black;
            } else {
              sideToMove = PieceColor.white;
            }

            return true;
          },
          onWrongMove: () async {
            undoCount++;
          },
        );

        expect(outcome, PuzzleAutoPlayOutcome.playedMoves);
        expect(applyCount, 2);
        expect(undoCount, 0);
        expect(moves, <String>['a1', 'b2', 'c3']);
        expect(sideToMove, PieceColor.white);
      },
    );

    test(
      'calls onWrongMove and stops when no solution matches the current line',
      () async {
        final List<List<String>> solutions = <List<String>>[
          <String>['a1', 'b2'],
        ];

        final List<String> moves = <String>['wrong'];
        PieceColor sideToMove = PieceColor.black;

        int applyCount = 0;
        int undoCount = 0;

        final PuzzleAutoPlayOutcome outcome =
            await PuzzleAutoPlayer.autoPlayOpponentResponses(
              solutions: solutions,
              humanColor: PieceColor.white,
              isGameOver: () => false,
              sideToMove: () => sideToMove,
              movesSoFar: () => List<String>.unmodifiable(moves),
              applyMove: (String move) {
                applyCount++;
                moves.add(move);
                return true;
              },
              onWrongMove: () async {
                undoCount++;
              },
            );

        expect(outcome, PuzzleAutoPlayOutcome.wrongMove);
        expect(applyCount, 0);
        expect(undoCount, 1);
        expect(moves, <String>['wrong']);
        expect(sideToMove, PieceColor.black);
      },
    );

    test('no-ops when it is already the human turn', () async {
      final List<List<String>> solutions = <List<String>>[
        <String>['a1', 'b2'],
      ];

      final List<String> moves = <String>['a1'];
      int applyCount = 0;
      int undoCount = 0;

      final PuzzleAutoPlayOutcome outcome =
          await PuzzleAutoPlayer.autoPlayOpponentResponses(
            solutions: solutions,
            humanColor: PieceColor.white,
            isGameOver: () => false,
            sideToMove: () => PieceColor.white,
            movesSoFar: () => List<String>.unmodifiable(moves),
            applyMove: (String move) {
              applyCount++;
              moves.add(move);
              return true;
            },
            onWrongMove: () async {
              undoCount++;
            },
          );

      expect(outcome, PuzzleAutoPlayOutcome.noOp);
      expect(applyCount, 0);
      expect(undoCount, 0);
      expect(moves, <String>['a1']);
    });
  });
}
