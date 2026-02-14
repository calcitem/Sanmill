// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_recorder_extended_test.dart
//
// Extended tests for GameRecorder: variations, branching, history text,
// preferred children, and PGN tree navigation.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  late GameController controller;

  setUp(() {
    DB.instance = MockDB();
    initBitboards();
    SoundManager.instance = MockAudios();
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
    controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // GameRecorder construction
  // ---------------------------------------------------------------------------
  group('GameRecorder construction', () {
    test('new recorder should have empty mainline', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.mainlineMoves, isEmpty);
    });

    test('new recorder should have no variations', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.hasVariations(), isFalse);
    });

    test('new recorder should be at end', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.isAtEnd(), isTrue);
    });

    test('new recorder pgnRoot should have no children', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.pgnRoot.children, isEmpty);
    });

    test('moveCountNotifier should start at 0', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.moveCountNotifier.value, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // appendMove
  // ---------------------------------------------------------------------------
  group('GameRecorder.appendMove', () {
    test('should add a move to the mainline', () {
      final GameRecorder recorder = controller.gameRecorder;
      final ExtMove move = ExtMove('d6', side: PieceColor.white);

      recorder.appendMove(move);

      expect(recorder.mainlineMoves.length, 1);
      expect(recorder.mainlineMoves.first.move, 'd6');
    });

    test('should add multiple moves to the mainline', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('b4', side: PieceColor.white));

      expect(recorder.mainlineMoves.length, 3);
      expect(recorder.mainlineMoves[0].move, 'd6');
      expect(recorder.mainlineMoves[1].move, 'f4');
      expect(recorder.mainlineMoves[2].move, 'b4');
    });

    test('should update moveCountNotifier', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));

      expect(recorder.moveCountNotifier.value, greaterThan(0));
    });

    test('should advance activeNode', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));

      expect(recorder.activeNode, isNotNull);
      expect(recorder.activeNode!.data!.move, 'd6');
    });
  });

  // ---------------------------------------------------------------------------
  // branchNewMoveFromActiveNode
  // ---------------------------------------------------------------------------
  group('GameRecorder.branchNewMoveFromActiveNode', () {
    test('should create a branch (variation) from current position', () {
      final GameRecorder recorder = controller.gameRecorder;

      // Add mainline: d6 → f4
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back to after d6
      recorder.activeNode = recorder.pgnRoot.children.first;

      // Branch with a different continuation: b4
      recorder.branchNewMoveFromActiveNode(
        ExtMove('b4', side: PieceColor.black),
      );

      // The first child of d6 should now have 2 children (f4 and b4)
      final int childCount = recorder.pgnRoot.children.first.children.length;
      expect(childCount, 2);
    });

    test('should not create duplicate branch for same move', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back to after d6
      recorder.activeNode = recorder.pgnRoot.children.first;

      // Try to branch with same move (f4 already exists)
      recorder.branchNewMoveFromActiveNode(
        ExtMove('f4', side: PieceColor.black),
      );

      // Should not create a duplicate: still only 1 child
      final int childCount = recorder.pgnRoot.children.first.children.length;
      expect(childCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // hasVariations
  // ---------------------------------------------------------------------------
  group('GameRecorder.hasVariations', () {
    test('should return false for linear game', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('b4', side: PieceColor.white));

      expect(recorder.hasVariations(), isFalse);
    });

    test('should return true after branching', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back and branch
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.branchNewMoveFromActiveNode(
        ExtMove('a1', side: PieceColor.black),
      );

      expect(recorder.hasVariations(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // isAtEnd
  // ---------------------------------------------------------------------------
  group('GameRecorder.isAtEnd', () {
    test('should return true for empty recorder', () {
      final GameRecorder recorder = controller.gameRecorder;
      expect(recorder.isAtEnd(), isTrue);
    });

    test('should return true after appending (active at last node)', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      expect(recorder.isAtEnd(), isTrue);
    });

    test('should return false when active is not at end', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Move back to first move
      recorder.activeNode = recorder.pgnRoot.children.first;

      expect(recorder.isAtEnd(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // currentPath
  // ---------------------------------------------------------------------------
  group('GameRecorder.currentPath', () {
    test('should return empty for new recorder', () {
      final GameRecorder recorder = controller.gameRecorder;
      expect(recorder.currentPath, isEmpty);
    });

    test('should return all moves when at end', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      final List<ExtMove> path = recorder.currentPath;
      expect(path.length, 2);
      expect(path[0].move, 'd6');
      expect(path[1].move, 'f4');
    });

    test('should return partial path when not at end', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('b4', side: PieceColor.white));

      // Move back to second node
      recorder.activeNode = recorder.pgnRoot.children.first.children.first;

      final List<ExtMove> path = recorder.currentPath;
      expect(path.length, 2); // d6, f4
    });
  });

  // ---------------------------------------------------------------------------
  // moveHistoryText
  // ---------------------------------------------------------------------------
  group('GameRecorder.moveHistoryText', () {
    test('should include move notations', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      final String text = recorder.moveHistoryText;
      expect(text, contains('d6'));
      expect(text, contains('f4'));
    });

    test('empty recorder should produce minimal text', () {
      final GameRecorder recorder = controller.gameRecorder;
      final String text = recorder.moveHistoryText;

      // Should at least contain result marker or be non-null
      expect(text, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Preferred children
  // ---------------------------------------------------------------------------
  group('GameRecorder preferred children', () {
    test('default preferred child index should be 0', () {
      final GameRecorder recorder = controller.gameRecorder;
      expect(recorder.getPreferredChildIndex(recorder.pgnRoot), 0);
    });

    test('setPreferredChild should store and retrieve', () {
      final GameRecorder recorder = controller.gameRecorder;

      recorder.setPreferredChild(recorder.pgnRoot, 2);
      expect(recorder.getPreferredChildIndex(recorder.pgnRoot), 2);
    });

    test('clearPreferredChildren should reset all', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.setPreferredChild(recorder.pgnRoot, 5);

      recorder.clearPreferredChildren();

      expect(recorder.getPreferredChildIndex(recorder.pgnRoot), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Setup position and lastPositionWithRemove
  // ---------------------------------------------------------------------------
  group('GameRecorder properties', () {
    test('lastPositionWithRemove should be nullable', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.lastPositionWithRemove, isNull);

      recorder.lastPositionWithRemove = 'some FEN';
      expect(recorder.lastPositionWithRemove, 'some FEN');
    });

    test('setupPosition should be nullable', () {
      final GameRecorder recorder = GameRecorder();
      expect(recorder.setupPosition, isNull);

      recorder.setupPosition = 'custom FEN';
      expect(recorder.setupPosition, 'custom FEN');
    });

    test('gameResultPgn should return valid termination', () {
      final GameRecorder recorder = controller.gameRecorder;
      final String result = recorder.gameResultPgn;

      expect(<String>['1-0', '0-1', '1/2-1/2', '*'].contains(result), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // hasVariationsAtActiveNode
  // ---------------------------------------------------------------------------
  group('GameRecorder.hasVariationsAtActiveNode', () {
    test('should return false when no variations at current node', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));

      expect(recorder.hasVariationsAtActiveNode(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // getNextMoveOptions / hasMultipleNextMoves
  // ---------------------------------------------------------------------------
  group('GameRecorder.getNextMoveOptions', () {
    test('empty recorder should have no next options', () {
      final GameRecorder recorder = controller.gameRecorder;
      expect(recorder.getNextMoveOptions(), isEmpty);
    });

    test('hasMultipleNextMoves should be false for linear game', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));

      // At the end, no children → no multiple next moves
      expect(recorder.hasMultipleNextMoves(), isFalse);
    });
  });
}
