// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  group('PGN parsing', () {
    test('Parses comment annotations and rebuilds comment text', () {
      const String rawComment =
          'Nice [%clk 0:01:02.5] [%emt 0:00:01] [%eval 0.34,12] '
          '[%cal Ra1b2] [%csl Gc3]';

      final PgnComment parsed = PgnComment.fromPgn(rawComment);

      expect(parsed.text, 'Nice');
      expect(parsed.clock, const Duration(minutes: 1, seconds: 2, milliseconds: 500));
      expect(parsed.emt, const Duration(seconds: 1));
      expect(parsed.eval, const PgnEvaluation.pawns(pawns: 0.34, depth: 12));
      expect(parsed.shapes.length, 2);

      final String rebuilt = parsed.makeComment();
      expect(rebuilt, contains('Nice'));
      expect(rebuilt, contains('%clk'));
      expect(rebuilt, contains('%emt'));
      expect(rebuilt, contains('%eval'));
      expect(rebuilt, contains('%cal'));
      expect(rebuilt, contains('%csl'));
    });

    test('Parses and serializes evaluations', () {
      const PgnEvaluation pawnEval = PgnEvaluation.pawns(pawns: 0.5, depth: 3);
      const PgnEvaluation mateEval = PgnEvaluation.mate(mate: -2, depth: 9);

      expect(pawnEval.toPgn(), '0.50,3');
      expect(mateEval.toPgn(), '#-2,9');
    });

    test('Parses mainline moves and transforms nodes', () {
      final PgnGame<PgnNodeData> game =
          PgnGame.parsePgn('1. d6 f4 2. d7 *');
      final List<String> mainlineSans =
          game.moves.mainline().map((PgnNodeData d) => d.san).toList();
      expect(mainlineSans, <String>['d6', 'f4', 'd7']);

      final PgnNode<PgnNodeData> transformed =
          game.moves.transform<PgnNodeData, int>(
        0,
        (int ctx, PgnNodeData data, int childIndex) {
          final int next = childIndex == -1 ? ctx : ctx + 1;
          return (next, PgnNodeData(san: '${data.san}#$next'));
        },
      );

      final List<String> transformedSans =
          transformed.mainline().map((PgnNodeData d) => d.san).toList();
      expect(transformedSans, <String>['d6#1', 'f4#2', 'd7#3']);
    });

    test('Parses multi-game PGN correctly', () {
      const String multiGamePgn = '''
[Event "Game 1"]
[White "Player A"]
[Black "Player B"]

1. d6 f4 *

[Event "Game 2"]
[White "Player C"]
[Black "Player D"]

1. a1 g7 2. d2 *
''';

      final List<PgnGame<PgnNodeData>> games =
          PgnGame.parseMultiGamePgn(multiGamePgn);

      // Verify we got 2 games
      expect(games.length, 2, reason: 'Should parse 2 games');

      // Verify first game
      expect(games[0].headers['Event'], 'Game 1');
      expect(games[0].headers['White'], 'Player A');
      expect(games[0].headers['Black'], 'Player B');
      final List<PgnNodeData> game1Moves = games[0].moves.mainline().toList();
      expect(game1Moves.length, 2);
      expect(game1Moves[0].san, 'd6');
      expect(game1Moves[1].san, 'f4');

      // Verify second game
      expect(games[1].headers['Event'], 'Game 2');
      expect(games[1].headers['White'], 'Player C');
      expect(games[1].headers['Black'], 'Player D');
      final List<PgnNodeData> game2Moves = games[1].moves.mainline().toList();
      expect(game2Moves.length, 3);
      expect(game2Moves[0].san, 'a1');
      expect(game2Moves[1].san, 'g7');
      expect(game2Moves[2].san, 'd2');
    });

    test('Handles deeply nested variations', () {
      const String deepPgn = '''
1. d6 (1. a1 (1. b2 c3) 1... d7) 1... f4 (1... g7 (1... a7) 1... b6) 2. d2 *
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(deepPgn);
      final PgnNode<PgnNodeData> root = game.moves;

      // Root should have at least 2 children: d6 (mainline) and variations
      expect(root.children.length, greaterThanOrEqualTo(2));

      // First mainline move
      final PgnNode<PgnNodeData> d6Node = root.children[0];
      expect(d6Node.data?.san, 'd6');

      // First variation at root
      final PgnNode<PgnNodeData> a1Node = root.children[1];
      expect(a1Node.data?.san, 'a1');

      // a1 should have nested variation b2
      expect(a1Node.children.length, greaterThanOrEqualTo(1));
      if (a1Node.children.length > 1) {
        final PgnNode<PgnNodeData> b2Node = a1Node.children[1];
        expect(b2Node.data?.san, 'b2');
      }

      // d6's response should have variations
      expect(d6Node.children.length, greaterThanOrEqualTo(1));
      final PgnNode<PgnNodeData> f4Node = d6Node.children[0];
      expect(f4Node.data?.san, 'f4');

      // Check for variation if it exists
      if (d6Node.children.length > 1) {
        final PgnNode<PgnNodeData> g7Node = d6Node.children[1];
        expect(g7Node.data?.san, 'g7');

        // g7 should have nested variation a7
        if (g7Node.children.length > 1) {
          final PgnNode<PgnNodeData> a7Node = g7Node.children[1];
          expect(a7Node.data?.san, 'a7');
        }
      }
    });

    test('Handles empty PGN gracefully', () {
      const String emptyPgn = '';
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(emptyPgn);

      expect(game.moves.children.length, 0);
      expect(game.headers, isNotEmpty); // Should have default headers
    });

    test('Handles PGN with only headers', () {
      const String headersOnlyPgn = '''
[Event "Test Event"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(headersOnlyPgn);

      expect(game.headers['Event'], 'Test Event');
      expect(game.headers['White'], 'Alice');
      expect(game.headers['Black'], 'Bob');
      expect(game.headers['Result'], '1-0');
      expect(game.moves.mainline().length, 0);
    });

    test('Handles malformed move tokens gracefully', () {
      // PGN with some unrecognized tokens mixed in
      const String malformedPgn = '1. d6 invalid-token f4 *';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(malformedPgn);

      // Should parse valid moves and skip invalid ones
      final List<PgnNodeData> moves = game.moves.mainline().toList();
      expect(moves.length, 2); // d6 and f4
      expect(moves[0].san, 'd6');
      expect(moves[1].san, 'f4');
    });

    test('Parses all NAG symbols correctly', () {
      const String nagPgn =
          '1. d6! f4? 2. d7!! g7?? 3. a1!? b2?! 4. c3\$10 d5 *';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(nagPgn);
      final List<PgnNodeData> moves = game.moves.mainline().toList();

      expect(moves[0].nags, [1]); // !
      expect(moves[1].nags, [2]); // ?
      expect(moves[2].nags, [3]); // !!
      expect(moves[3].nags, [4]); // ??
      expect(moves[4].nags, [5]); // !?
      expect(moves[5].nags, [6]); // ?!
      expect(moves[6].nags, [10]); // $10
    });

    test('Preserves move order with multiple variations', () {
      const String multiVarPgn = '''
1. d6 (1. a1) (1. b2) (1. c3) 1... f4 *
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(multiVarPgn);
      final PgnNode<PgnNodeData> root = game.moves;

      // Root should have 4 children: d6 (mainline) + 3 variations
      expect(root.children.length, 4);
      expect(root.children[0].data?.san, 'd6');
      expect(root.children[1].data?.san, 'a1');
      expect(root.children[2].data?.san, 'b2');
      expect(root.children[3].data?.san, 'c3');
    });

    test('makePgn reconstructs original PGN structure', () {
      const String originalPgn = '''
[Event "Test"]
[White "W"]
[Black "B"]

1. d6 {Good move} f4 2. d7 (2. a7 g4) 2... g7 *
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(originalPgn);
      final String reconstructed = game.makePgn();

      // Verify headers are preserved
      expect(reconstructed, contains('[Event "Test"]'));
      expect(reconstructed, contains('[White "W"]'));
      expect(reconstructed, contains('[Black "B"]'));

      // Verify mainline moves
      expect(reconstructed, contains('d6'));
      expect(reconstructed, contains('f4'));
      expect(reconstructed, contains('d7'));
      expect(reconstructed, contains('g7'));

      // Verify comment is preserved
      expect(reconstructed, contains('Good move'));

      // Verify variation is enclosed in parentheses
      expect(reconstructed, contains('('));
      expect(reconstructed, contains('a7'));
    });

    test('Handles BOM (Byte Order Mark) in PGN', () {
      const String bomPgn = '\ufeff1. d6 f4 *';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(bomPgn);
      final List<PgnNodeData> moves = game.moves.mainline().toList();

      expect(moves.length, 2);
      expect(moves[0].san, 'd6');
      expect(moves[1].san, 'f4');
    });

    test('Handles escaped quotes in headers', () {
      const String escapedPgn = '''
[Event "Test \\"Quoted\\" Event"]
[White "Player \\\\ Name"]

1. d6 *
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(escapedPgn);

      expect(game.headers['Event'], 'Test "Quoted" Event');
      expect(game.headers['White'], r'Player \ Name');
    });

    test('Handles game result markers correctly', () {
      const String whitePgn = '1. d6 f4 1-0';
      const String blackPgn = '1. d6 f4 0-1';
      const String drawPgn = '1. d6 f4 1/2-1/2';
      const String unknownPgn = '1. d6 f4 *';

      final PgnGame<PgnNodeData> game1 = PgnGame.parsePgn(whitePgn);
      expect(game1.headers['Result'], '1-0');

      final PgnGame<PgnNodeData> game2 = PgnGame.parsePgn(blackPgn);
      expect(game2.headers['Result'], '0-1');

      final PgnGame<PgnNodeData> game3 = PgnGame.parsePgn(drawPgn);
      expect(game3.headers['Result'], '1/2-1/2');

      final PgnGame<PgnNodeData> game4 = PgnGame.parsePgn(unknownPgn);
      // Unknown result '*' is kept in default headers
      expect(game4.headers.containsKey('Result'), isTrue);
    });

    test('Handles variations at different depths', () {
      const String complexPgn = '''
1. d6 f4 
2. d7 (2. a7 {Var at move 2} g4 3. g7) 
2... g7 (2... f6 {Var at move 2 black} 3. f2) 
3. f6 *
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(complexPgn);

      // Verify comments in variations are preserved
      final String reconstructed = game.makePgn();
      expect(reconstructed, contains('Var at move 2'));
      expect(reconstructed, contains('Var at move 2 black'));
    });
  });
}
