// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
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

  group('GameRecorder tree operations', () {
    test('Creates new branch at specific index', () {
      final GameRecorder recorder = GameRecorder();

      // Build initial mainline: d6, f4, d7
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('d7', side: PieceColor.white));

      // Branch new move at index 1 (after d6)
      recorder.branchNewMove(1, ExtMove('a1', side: PieceColor.black));

      // Verify structure
      final PgnNode<ExtMove> d6Node = recorder.pgnRoot.children.first;
      expect(d6Node.children.length, greaterThanOrEqualTo(1));

      // New branch should be first child (mainline)
      expect(d6Node.children.first.data?.move, 'a1');
    });

    test('appendMove creates variation when move exists', () {
      final GameRecorder recorder = GameRecorder();

      // Build mainline
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back to d6 and add different black move
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // d6 should now have 2 children: f4 and g7
      final PgnNode<ExtMove> d6Node = recorder.pgnRoot.children.first;
      expect(d6Node.children.length, 2);
    });

    test('appendMove follows existing variation when matching', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back and create variation
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // Go back again and try to append g7 (already exists)
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // Should follow existing variation, not create duplicate
      final PgnNode<ExtMove> d6Node = recorder.pgnRoot.children.first;
      expect(d6Node.children.length, 2); // Still just f4 and g7
    });

    test('Reset clears all moves and state', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      expect(recorder.mainlineMoves.length, 2);
      expect(recorder.activeNode, isNotNull);

      recorder.reset();

      expect(recorder.mainlineMoves.length, 0);
      expect(recorder.activeNode, isNull);
      expect(recorder.pgnRoot.children.length, 0);
    });

    test('moveCountNotifier fires on move changes', () {
      final GameRecorder recorder = GameRecorder();
      int notificationCount = 0;

      recorder.moveCountNotifier.addListener(() {
        notificationCount++;
      });

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      expect(notificationCount, 1);

      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      expect(notificationCount, 2);

      recorder.reset();
      expect(notificationCount, 3);
    });

    test('mainlineNodes returns correct sequence', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Add variation (should not affect mainline)
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      final List<PgnNode<ExtMove>> mainlineNodes = recorder.mainlineNodes;

      // Mainline should still be d6 -> f4
      expect(mainlineNodes.length, 2);
      expect(mainlineNodes[0].data?.move, 'd6');
      expect(mainlineNodes[1].data?.move, 'f4');
    });

    test('Handles complex branching scenario', () {
      final GameRecorder recorder = GameRecorder();

      // Build main tree structure:
      //     d6
      //    /  \
      //   f4  a1
      //   |    |
      //   d7  b2
      //  / \
      // g7 f6

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('d7', side: PieceColor.white));
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // Create first variation: a1 instead of f4
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('a1', side: PieceColor.black));
      recorder.appendMove(ExtMove('b2', side: PieceColor.white));

      // Create second variation: f6 instead of g7
      final PgnNode<ExtMove> d7Node = recorder.pgnRoot
          .children.first.children.first.children.first;
      recorder.activeNode = d7Node;
      recorder.appendMove(ExtMove('f6', side: PieceColor.black));

      // Verify structure
      final PgnNode<ExtMove> d6Node = recorder.pgnRoot.children.first;
      expect(d6Node.children.length, 2); // f4 and a1

      final PgnNode<ExtMove> f4Node = d6Node.children.first;
      expect(f4Node.data?.move, 'f4');
      expect(f4Node.children.length, 1); // Only d7

      final PgnNode<ExtMove> a1Node = d6Node.children[1];
      expect(a1Node.data?.move, 'a1');
      expect(a1Node.children.length, 1); // Only b2

      final PgnNode<ExtMove> d7NodeCheck = f4Node.children.first;
      expect(d7NodeCheck.children.length, 2); // g7 and f6
    });

    test('Maintains parent pointers correctly', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      final PgnNode<ExtMove> d6Node = recorder.pgnRoot.children.first;
      final PgnNode<ExtMove> f4Node = d6Node.children.first;

      expect(d6Node.parent, recorder.pgnRoot);
      expect(f4Node.parent, d6Node);
    });

    test('currentPath traverses up to root correctly', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('d7', side: PieceColor.white));

      final List<ExtMove> path = recorder.currentPath;

      expect(path.length, 3);
      expect(path[0].move, 'd6');
      expect(path[1].move, 'f4');
      expect(path[2].move, 'd7');
    });

    test('hasMultipleNextMoves detects branching points', () {
      final GameRecorder recorder = GameRecorder();

      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Add variation
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.appendMove(ExtMove('g7', side: PieceColor.black));

      // Go to d6 node
      recorder.activeNode = recorder.pgnRoot.children.first;

      expect(recorder.hasMultipleNextMoves(), isTrue);
    });

    test('Exports empty recorder correctly', () {
      final GameRecorder recorder = GameRecorder();

      final String text = recorder.moveHistoryText;
      expect(text, isEmpty);
    });

    test('Exports recorder with setup position', () {
      final GameController controller = GameController.instance;
      final GameRecorder recorder = controller.gameRecorder;

      // Set a custom setup position
      recorder.setupPosition =
          '********/********/******** w p p 9 0 9 0 0 0 0 0 0 0 0 0';

      // isPositionSetup is a getter that checks setupPosition != null
      expect(controller.isPositionSetup, isTrue);

      final String text = recorder.moveHistoryText;
      expect(text, contains('[FEN'));
      expect(text, contains('[SetUp "1"]'));
    });
  });

  group('ExtMove operations', () {
    test('ExtMove parses place move correctly', () {
      final ExtMove move = ExtMove('d6', side: PieceColor.white);

      expect(move.type, MoveType.place);
      expect(move.to, greaterThan(0)); // Should map to valid square index
      expect(move.from, -1); // Place moves have no 'from' square
    });

    test('ExtMove parses step move correctly', () {
      final ExtMove move = ExtMove('d6-f4', side: PieceColor.white);

      expect(move.type, MoveType.move);
      expect(move.from, greaterThan(0));
      expect(move.to, greaterThan(0));
      expect(move.from, isNot(equals(move.to)));
    });

    test('ExtMove parses remove move correctly', () {
      final ExtMove move = ExtMove('xd6', side: PieceColor.white);

      expect(move.type, MoveType.remove);
      expect(move.to, greaterThan(0));
      expect(move.from, -1);
    });

    test('ExtMove rejects same-square move', () {
      expect(
        () => ExtMove('d6-d6', side: PieceColor.white),
        throwsException,
      );
    });

    test('ExtMove formats notation correctly', () {
      final ExtMove place = ExtMove('d6', side: PieceColor.white);
      final ExtMove move = ExtMove('d6-f4', side: PieceColor.white);
      final ExtMove remove = ExtMove('xa1', side: PieceColor.white);

      expect(place.notation, 'd6');
      expect(move.notation, 'd6-f4');
      expect(remove.notation, 'xa1');
    });

    test('ExtMove.sqToNotation converts square indices', () {
      // Test a few known mappings
      expect(ExtMove.sqToNotation(8), 'd5'); // Inner ring
      expect(ExtMove.sqToNotation(16), 'd6'); // Middle ring
      expect(ExtMove.sqToNotation(24), 'd7'); // Outer ring
      expect(ExtMove.sqToNotation(29), 'a1'); // Corner
      expect(ExtMove.sqToNotation(25), 'g7'); // Corner
    });

    test('ExtMove handles NAG conversion', () {
      expect(ExtMove.moveQualityToNag(MoveQuality.minorGoodMove), 1);
      expect(ExtMove.moveQualityToNag(MoveQuality.minorBadMove), 2);
      expect(ExtMove.moveQualityToNag(MoveQuality.majorGoodMove), 3);
      expect(ExtMove.moveQualityToNag(MoveQuality.majorBadMove), 4);
      expect(ExtMove.moveQualityToNag(MoveQuality.normal), isNull);

      expect(ExtMove.nagToMoveQuality(1), MoveQuality.minorGoodMove);
      expect(ExtMove.nagToMoveQuality(2), MoveQuality.minorBadMove);
      expect(ExtMove.nagToMoveQuality(3), MoveQuality.majorGoodMove);
      expect(ExtMove.nagToMoveQuality(4), MoveQuality.majorBadMove);
      expect(ExtMove.nagToMoveQuality(99), isNull);
    });

    test('ExtMove.getAllNags merges quality and explicit NAGs', () {
      final ExtMove move = ExtMove(
        'd6',
        side: PieceColor.white,
        nags: <int>[10, 20], // Custom NAGs without quality
      );
      move.quality = MoveQuality.minorGoodMove; // Should add NAG 1 (!)

      final List<int> allNags = move.getAllNags();

      expect(allNags, contains(10));
      expect(allNags, contains(20));
      // NAG 1 should be added because no quality NAG exists
      expect(allNags, contains(1));
    });

    test('ExtMove.updateQualityFromNags sets quality', () {
      final ExtMove move = ExtMove(
        'd6',
        side: PieceColor.white,
        nags: <int>[3, 10], // !! and custom
      );

      move.updateQualityFromNags();

      expect(move.quality, MoveQuality.majorGoodMove);
    });

    test('ExtMove validates draw and none special moves', () {
      final ExtMove draw = ExtMove('draw', side: PieceColor.white);
      final ExtMove none1 = ExtMove('(none)', side: PieceColor.white);
      final ExtMove none2 = ExtMove('none', side: PieceColor.white);

      expect(draw.type, MoveType.draw);
      expect(none1.type, MoveType.none);
      expect(none2.type, MoveType.none);
    });

    test('ExtMove rejects invalid notation formats', () {
      expect(
        () => ExtMove('h8', side: PieceColor.white),
        throwsFormatException,
      ); // Out of range
      expect(
        () => ExtMove('d', side: PieceColor.white),
        throwsFormatException,
      ); // Too short
      expect(
        () => ExtMove('invalid', side: PieceColor.white),
        throwsFormatException,
      ); // Invalid format
    });

    test('ExtMove stores additional metadata', () {
      final ExtMove move = ExtMove(
        'd6-f4',
        side: PieceColor.white,
        boardLayout: 'O......./......../@.......',
        moveIndex: 5,
        roundIndex: 3,
        preferredRemoveTarget: 18,
      );

      expect(move.boardLayout, 'O......./......../@.......');
      expect(move.moveIndex, 5);
      expect(move.roundIndex, 3);
      expect(move.preferredRemoveTarget, 18);
    });

    test('ExtMove handles variation metadata', () {
      final ExtMove move = ExtMove(
        'd6',
        side: PieceColor.white,
      );

      move.isVariation = true;
      move.variationDepth = 2;
      move.branchColumn = 1;
      move.branchLineType = 'fork';
      move.isLastSibling = false;
      move.siblingIndex = 1;

      expect(move.isVariation, isTrue);
      expect(move.variationDepth, 2);
      expect(move.branchColumn, 1);
      expect(move.branchLineType, 'fork');
      expect(move.isLastSibling, isFalse);
      expect(move.siblingIndex, 1);
    });
  });

  group('PGN node operations', () {
    test('PgnNode mainline iteration works correctly', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> node1 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'd6'));
      final PgnNode<PgnNodeData> node2 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'f4'));
      final PgnNode<PgnNodeData> node3 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'd7'));

      root.children.add(node1);
      node1.children.add(node2);
      node2.children.add(node3);

      final List<PgnNodeData> mainline = root.mainline().toList();

      expect(mainline.length, 3);
      expect(mainline[0].san, 'd6');
      expect(mainline[1].san, 'f4');
      expect(mainline[2].san, 'd7');
    });

    test('PgnNode transform skips nodes when callback returns null', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> node1 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'd6'));
      final PgnNode<PgnNodeData> node2 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'SKIP'));
      final PgnNode<PgnNodeData> node3 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'f4'));

      root.children.add(node1);
      node1.children.add(node2);
      node2.children.add(node3);

      // Transform, skipping "SKIP" nodes
      final PgnNode<PgnNodeData> transformed =
          root.transform<PgnNodeData, void>(
        null,
        (void ctx, PgnNodeData data, int childIndex) {
          if (data.san == 'SKIP') {
            return null; // Skip this node
          }
          return (null, data);
        },
      );

      final List<PgnNodeData> result = transformed.mainline().toList();

      // Should have d6 but not SKIP or f4 (because f4 is child of SKIP)
      expect(result.length, 1);
      expect(result[0].san, 'd6');
    });

    test('PgnNode transform updates context correctly', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> node1 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'd6'));
      final PgnNode<PgnNodeData> node2 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'f4'));

      root.children.add(node1);
      node1.children.add(node2);

      // Transform with accumulating context
      // Note: childIndex=-1 for node.data transform, then children get sequential indices
      final PgnNode<PgnNodeData> transformed =
          root.transform<PgnNodeData, int>(
        0,
        (int ctx, PgnNodeData data, int childIndex) {
          final int newCtx = ctx + 1;
          return (
            newCtx,
            PgnNodeData(san: '${data.san}[$newCtx]'),
          );
        },
      );

      final List<PgnNodeData> result = transformed.mainline().toList();

      expect(result.length, 2);
      // Context increments with each node processed
      expect(result[0].san, contains('d6'));
      expect(result[1].san, contains('f4'));
    });

    test('PgnNode handles multiple children (variations)', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> var1 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'd6'));
      final PgnNode<PgnNodeData> var2 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'a1'));
      final PgnNode<PgnNodeData> var3 =
          PgnNode<PgnNodeData>(PgnNodeData(san: 'b2'));

      root.children.add(var1);
      root.children.add(var2);
      root.children.add(var3);

      // Mainline should follow first child
      final List<PgnNodeData> mainline = root.mainline().toList();
      expect(mainline.length, 1);
      expect(mainline[0].san, 'd6');

      // All variations should be accessible
      expect(root.children.length, 3);
    });
  });

  group('Move parsing edge cases', () {
    test('MoveParser handles all move types', () {
      final MoveParser parser = MoveParser();

      expect(parser.parseMoveType('d6'), MoveType.place);
      expect(parser.parseMoveType('d6-f4'), MoveType.move);
      expect(parser.parseMoveType('xd6'), MoveType.remove);
      expect(parser.parseMoveType('draw'), MoveType.draw);
      expect(parser.parseMoveType('(none)'), MoveType.none);
      expect(parser.parseMoveType('none'), MoveType.none);
    });

    test('MoveParser rejects invalid formats', () {
      final MoveParser parser = MoveParser();

      expect(
        () => parser.parseMoveType('invalid'),
        throwsFormatException,
      );
      expect(
        () => parser.parseMoveType('h8'),
        throwsFormatException,
      ); // Out of range
    });

    test('ExtMove notation respects screen reader setting', () {
      // This test documents the behavior, actual implementation
      // may depend on DB().generalSettings.screenReaderSupport

      final ExtMove move1 = ExtMove('d6', side: PieceColor.white);
      final ExtMove move2 = ExtMove('d6-f4', side: PieceColor.white);
      final ExtMove move3 = ExtMove('xa1', side: PieceColor.white);

      // Default should be lowercase
      expect(move1.notation, 'd6');
      expect(move2.notation, contains('d6'));
      expect(move3.notation, 'xa1');
    });
  });
}
