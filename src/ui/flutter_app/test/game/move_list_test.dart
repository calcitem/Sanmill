// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'bestmove d2';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    DB.instance = MockDB();
    SoundManager.instance = MockAudios();

    final GameController controller = GameController.instance;
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group('Move list formatting', () {
    test('Includes annotations and variations', () {
      final GameRecorder recorder = GameController().gameRecorder;

      final ExtMove move1 = ExtMove(
        'd6',
        side: PieceColor.white,
        nags: <int>[1],
        startingComments: <String>['Start'],
        comments: <String>['After'],
      );
      final ExtMove move2 = ExtMove('f4', side: PieceColor.black);
      recorder.appendMove(move1);
      recorder.appendMove(move2);

      final PgnNode<ExtMove> move1Node = recorder.pgnRoot.children.first;
      recorder.activeNode = move1Node;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      final String text = recorder.moveHistoryText;
      expect(text, contains('{Start} d6!'));
      expect(text, contains('{After}'));
      expect(text, contains('f4'));
      expect(text, contains('(1... g7'));
    });

    test('Concatenates remove moves after placements', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('b2', side: PieceColor.white));
      recorder.appendMove(ExtMove('xf4', side: PieceColor.white));

      final String text = recorder.moveHistoryText;
      expect(text, contains('b2xf4'));
    });

    test('Move list prompt includes metadata and board layout', () {
      final GameRecorder recorder = GameController().gameRecorder;

      final ExtMove move = ExtMove(
        'd6',
        side: PieceColor.white,
        boardLayout: 'O......./......../@.......',
        nags: <int>[1],
        comments: <String>['C1'],
      );
      recorder.appendMove(move);

      final String prompt = recorder.moveListPrompt;
      expect(prompt, contains('side=white'));
      expect(prompt, contains('boardLayout="O......./......../@......."'));
      expect(prompt, contains('nags="!"'));
      expect(prompt, contains('comments="C1"'));
    });

    test('GameRecorder tracks current path correctly', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('d7', side: PieceColor.white));

      final List<ExtMove> path = recorder.currentPath;
      expect(path.length, 3);
      expect(path[0].move, 'd6');
      expect(path[1].move, 'f4');
      expect(path[2].move, 'd7');
    });

    test('GameRecorder detects variations at active node', () {
      final GameRecorder recorder = GameController().gameRecorder;

      // Build mainline
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Step back and add variation
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // Now activeNode's parent has 2 children
      expect(recorder.hasVariationsAtActiveNode(), isTrue);
      final List<PgnNode<ExtMove>> variations = recorder
          .getVariationsAtActiveNode();
      expect(variations.length, 1);
      expect(variations.first.data?.move, 'f4');
    });

    test('GameRecorder switches to variation correctly', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Create variation at root
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('a1', side: PieceColor.black));

      // Switch to first variation
      final List<PgnNode<ExtMove>> variations = recorder
          .getVariationsAtActiveNode();
      recorder.switchToVariation(variations.first);

      expect(recorder.activeNode?.data?.move, 'f4');
    });

    test('GameRecorder detects end of move history', () {
      final GameRecorder recorder = GameController().gameRecorder;

      // Empty recorder is at end
      expect(recorder.isAtEnd(), isTrue);

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      expect(recorder.isAtEnd(), isTrue); // Still at end (activeNode is last)

      recorder.activeNode = recorder.pgnRoot;
      expect(recorder.isAtEnd(), isFalse); // Not at end (has children)
    });

    test('GameRecorder provides next move options', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Add variation after d6
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('a1', side: PieceColor.black));

      // Go back to root
      recorder.activeNode = recorder.pgnRoot;

      final List<PgnNode<ExtMove>> nextMoves = recorder.getNextMoveOptions();
      expect(nextMoves.length, 1); // Only d6 from root
      expect(nextMoves.first.data?.move, 'd6');

      // Now check options from d6
      recorder.activeNode = recorder.pgnRoot.children.first;
      final List<PgnNode<ExtMove>> afterD6 = recorder.getNextMoveOptions();
      expect(afterD6.length, 2); // f4 and a1
    });

    test('Handles multiple consecutive remove moves', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('b2', side: PieceColor.white));
      recorder.appendMove(ExtMove('xf4', side: PieceColor.white));
      recorder.appendMove(ExtMove('xd6', side: PieceColor.white));
      recorder.appendMove(ExtMove('xa7', side: PieceColor.white));

      final String text = recorder.moveHistoryText;
      // All removes should be concatenated
      expect(text, contains('b2xf4xd6xa7'));
    });

    test('appendMoveIfDifferent avoids duplicates', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      final int initialCount = recorder.mainlineMoves.length;

      // Try to append the same move again
      recorder.activeNode = recorder.pgnRoot;
      recorder.appendMoveIfDifferent(ExtMove('d6', side: PieceColor.white));

      // Should not create duplicate
      expect(recorder.mainlineMoves.length, initialCount);
    });

    test('branchNewMoveFromActiveNode checks for existing moves', () {
      final GameRecorder recorder = GameController().gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Try to branch with same move that already exists
      recorder.activeNode = recorder.pgnRoot.children.first;
      final int childCountBefore = recorder.activeNode!.children.length;

      recorder.branchNewMoveFromActiveNode(
        ExtMove('f4', side: PieceColor.black),
      );

      // Should not create duplicate branch
      expect(recorder.activeNode!.parent!.children.length, childCountBefore);
    });

    test('Formats variations with correct move numbering', () {
      final GameRecorder recorder = GameController().gameRecorder;

      // 1. d6 f4
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Create variation at move 2 (after f4): 2. a1
      recorder.appendMove(ExtMove('a1', side: PieceColor.white));

      // Go back and add alternative black response
      recorder.activeNode = recorder.pgnRoot.children.first; // Back to d6
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      final String text = recorder.moveHistoryText;

      // Should have both "1... f4" and variation "1... g7"
      expect(text, contains('f4'));
      expect(text, contains('1... g7'));
    });
  });
}
