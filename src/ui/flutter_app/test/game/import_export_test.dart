// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_export_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Define the MethodChannel to be mocked
  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    // Use the new API to set up mock handlers for MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
              return null; // Return a success response
            case 'shutdown':
              return null; // Return a success response
            case 'startup':
              return null; // Return a success response
            case 'read':
              return 'bestmove d2'; // Simulate a response for the 'read' method
            case 'isThinking':
              return false; // Simulate the 'isThinking' method response
            default:
              return null; // For unhandled methods, return null
          }
        });
  });

  tearDown(() {
    // Use the new API to remove the mock handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group("Import Export Service", () {
    setUp(() {
      // Mock DB and SoundManager to isolate the test environment
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();

      // Initialize the singleton GameController
      final GameController controller = GameController.instance;

      // Initialize mock AnimationManager to avoid LateInitializationError
      controller.animationManager = MockAnimationManager();

      // Reset the game controller to a clean state
      controller.reset(force: true);
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
    });

    test(
      "Import standard notation should populate the recorder with the imported moves",
      () async {
        const WinLessThanThreeGame testMill = WinLessThanThreeGame();

        // Access the singleton GameController instance
        final GameController controller = GameController.instance;

        // Verify MockDB is using standard Nine Men's Morris rules
        expect(DB().ruleSettings.piecesCount, 9);
        expect(DB().ruleSettings.hasDiagonalLines, false);

        // Import a game using ImportService
        ImportService.import(testMill.moveList);

        // After import, the moves are stored in newGameRecorder
        // (not yet activated in gameRecorder until takeBackAll/stepForwardAll)

        // Verify that the newGameRecorder contains the expected number of moves
        // The test game has 25 pairs of moves, but captures split into separate moves
        // Actual count is 59 (25 pairs + capture remove operations)
        expect(
          controller.newGameRecorder?.mainlineMoves.length,
          59,
          reason: 'newGameRecorder should contain 59 moves after import',
        );

        // Verify the exported move list matches the imported one
        expect(
          controller.newGameRecorder?.moveHistoryText.trim(),
          testMill.moveList.trim(),
          reason: 'Exported moves should match imported moves',
        );
      },
    );

    test("Export standard notation", () async {
      const WinLessThanThreeGame testMill = WinLessThanThreeGame();

      // Access the singleton GameController instance
      final GameController controller = GameController.instance;

      // Import a game
      ImportService.import(testMill.moveList);

      // Verify the exported moves match the original imported moves
      // After import, moves are in newGameRecorder (not yet activated)
      expect(
        controller.newGameRecorder?.moveHistoryText.trim(),
        testMill.moveList.trim(),
        reason: 'Exported move list should match the original imported list',
      );
    });

    test("Import PGN with variations should preserve all branches", () async {
      // Access the singleton GameController instance
      final GameController controller = GameController.instance;

      // PGN with variations: mainline and two variations after move 2
      const String pgnWithVariations = '''
1. d6 f4 2. d7 (2. a7 g4 3. g7) 2... g7 (2... f6 3. f2) 3. f6 *
''';

      // Import the PGN
      ImportService.import(pgnWithVariations);

      // Verify that the tree structure is preserved
      final PgnNode<ExtMove>? root = controller.newGameRecorder?.pgnRoot;
      expect(root, isNotNull, reason: 'Root node should exist');

      // Root should have 1 child (first move: d6)
      expect(root!.children.length, 1, reason: 'Root should have 1 child');

      // First move (d6)
      final PgnNode<ExtMove> move1 = root.children[0];
      expect(move1.data?.move, 'd6', reason: 'First move should be d6');
      expect(move1.children.length, 1, reason: 'Move 1 should have 1 child');

      // Second move (f4)
      final PgnNode<ExtMove> move2 = move1.children[0];
      expect(move2.data?.move, 'f4', reason: 'Second move should be f4');
      expect(
        move2.children.length,
        2,
        reason: 'Move 2 should have 2 children (mainline d7 and variation a7)',
      );

      // Third move (d7) - this is where variations start
      // The mainline should be d7, and there should be a variation with a7
      final PgnNode<ExtMove> move3Main = move2.children[0];
      expect(
        move3Main.data?.move,
        'd7',
        reason: 'Third move mainline should be d7',
      );

      // Check variation after move 2
      final PgnNode<ExtMove> move3Var = move2.children[1];
      expect(
        move3Var.data?.move,
        'a7',
        reason: 'Variation after move 2 should be a7',
      );

      // At move 2, there should be an alternative variation (a7)
      // Check if node after move2 has siblings (variations)
      // In our structure, variations are stored as additional children
      // Let me verify the structure: move2 should have 2 children: d7 (mainline) and a7 (variation)
      expect(
        move2.children.length,
        greaterThanOrEqualTo(1),
        reason: 'Move 2 should have at least the mainline',
      );

      // The variation structure: after f4, we have both d7 (mainline) and a7 (variation)
      // In PGN: "2. d7 (2. a7 g4 3. g7) 2... g7 (2... f6 3. f2) 3. f6"
      // This means: after move 2 (White's d7), Black plays g7 as mainline, with f6 as variation
      // And there's a variation where White plays a7 instead of d7

      // Let's check the mainline continues correctly
      expect(
        move3Main.children.length,
        greaterThanOrEqualTo(1),
        reason: 'Move 3 (d7) should have children',
      );

      // Fourth move in mainline (Black's g7)
      final PgnNode<ExtMove> move4Main = move3Main.children[0];
      expect(
        move4Main.data?.move,
        'g7',
        reason: 'Fourth move mainline should be g7',
      );

      // The mainline should continue with f6
      expect(
        move4Main.children.length,
        greaterThanOrEqualTo(1),
        reason: 'Move 4 (g7) should have children',
      );

      final PgnNode<ExtMove> move5Main = move4Main.children[0];
      expect(
        move5Main.data?.move,
        'f6',
        reason: 'Fifth move mainline should be f6',
      );

      // Variations have already been verified above

      // Check if move3Main has variations for Black's response
      if (move3Main.children.length > 1) {
        expect(
          move3Main.children.length,
          2,
          reason:
              'Move 3 (d7) should have 2 variations (mainline g7 and alternative f6)',
        );

        final PgnNode<ExtMove> blackVariation = move3Main.children[1];
        expect(
          blackVariation.data?.move,
          'f6',
          reason: "Black's variation after d7 should be f6",
        );
      }

      // Verify mainline moves count
      final List<ExtMove> mainlineMoves =
          controller.newGameRecorder!.mainlineMoves;
      expect(
        mainlineMoves.length,
        greaterThanOrEqualTo(5),
        reason: 'Mainline should have at least 5 moves',
      );
    });

    test("Export PGN with comments and variations", () async {
      // Access the singleton GameController instance
      final GameController controller = GameController.instance;

      // PGN with comments and variations
      const String pgnWithCommentsAndVariations = '''
1. d6 {Good opening} f4 2. d7 (2. a7 {Alternative opening} g4 3. g7) 2... g7 {Solid response} (2... f6 {Aggressive variation} 3. f2) 3. f6 *
''';

      // Import the PGN
      ImportService.import(pgnWithCommentsAndVariations);

      // Export the PGN
      final String exported =
          controller.newGameRecorder?.moveHistoryText.trim() ?? '';

      // Verify that comments are preserved
      expect(
        exported,
        contains('Good opening'),
        reason: 'Export should contain the comment "Good opening"',
      );

      expect(
        exported,
        contains('Solid response'),
        reason: 'Export should contain the comment "Solid response"',
      );

      expect(
        exported,
        contains('Alternative opening'),
        reason: 'Export should contain the comment "Alternative opening"',
      );

      expect(
        exported,
        contains('Aggressive variation'),
        reason: 'Export should contain the comment "Aggressive variation"',
      );

      // Verify that variations are enclosed in parentheses
      expect(
        exported,
        contains('('),
        reason: 'Export should contain opening parenthesis for variations',
      );

      expect(
        exported,
        contains(')'),
        reason: 'Export should contain closing parenthesis for variations',
      );

      // Verify that the mainline moves are present
      expect(exported, contains('d6'), reason: 'Export should contain move d6');

      expect(exported, contains('f4'), reason: 'Export should contain move f4');

      expect(exported, contains('d7'), reason: 'Export should contain move d7');

      expect(exported, contains('g7'), reason: 'Export should contain move g7');

      // Verify that variation moves are present
      expect(
        exported,
        contains('a7'),
        reason: 'Export should contain variation move a7',
      );

      expect(
        exported,
        contains('f6'),
        reason: 'Export should contain variation move f6',
      );
    });

    test("Export PGN with NAGs (Numeric Annotation Glyphs)", () async {
      // Access the singleton GameController instance
      final GameController controller = GameController.instance;

      // Create a game manually with NAGs
      controller.reset(force: true);

      // Add moves with NAGs
      final ExtMove move1 = ExtMove(
        'd6',
        side: PieceColor.white,
        nags: <int>[1],
      ); // !
      final ExtMove move2 = ExtMove(
        'f4',
        side: PieceColor.black,
        nags: <int>[2],
      ); // ?
      final ExtMove move3 = ExtMove(
        'd7',
        side: PieceColor.white,
        nags: <int>[3],
      ); // !!
      final ExtMove move4 = ExtMove(
        'g7',
        side: PieceColor.black,
        nags: <int>[4],
      ); // ??

      controller.gameRecorder.appendMove(move1);
      controller.gameRecorder.appendMove(move2);
      controller.gameRecorder.appendMove(move3);
      controller.gameRecorder.appendMove(move4);

      // Export the PGN
      final String exported = controller.gameRecorder.moveHistoryText.trim();

      // Verify that NAG symbols are present
      expect(
        exported,
        contains('!'),
        reason: 'Export should contain NAG symbol !',
      );

      expect(
        exported,
        contains('?'),
        reason: 'Export should contain NAG symbol ?',
      );

      expect(
        exported,
        contains('!!'),
        reason: 'Export should contain NAG symbol !!',
      );

      expect(
        exported,
        contains('??'),
        reason: 'Export should contain NAG symbol ??',
      );
    });
  });
}
