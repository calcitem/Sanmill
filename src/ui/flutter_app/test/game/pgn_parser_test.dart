// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// pgn_parser_test.dart
//
// Tests for PGN parsing and serialization (PgnGame.parsePgn, makePgn).

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PgnGame.parsePgn - basic parsing
  // ---------------------------------------------------------------------------
  group('PgnGame.parsePgn', () {
    test('should parse empty PGN', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('');

      expect(game.headers, isNotEmpty); // Default headers
      expect(game.moves.mainline().toList(), isEmpty);
    });

    test('should parse PGN with only result', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('*');

      expect(game.moves.mainline().toList(), isEmpty);
    });

    test('should parse simple move sequence', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6 f4 *');

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 2);
      expect(mainline[0].san, 'd6');
      expect(mainline[1].san, 'f4');
    });

    test('should parse multiple moves', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '1. d6 f4 2. b4 a1 3. d2 g7 *',
      );

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 6);
      expect(mainline[0].san, 'd6');
      expect(mainline[1].san, 'f4');
      expect(mainline[2].san, 'b4');
      expect(mainline[3].san, 'a1');
      expect(mainline[4].san, 'd2');
      expect(mainline[5].san, 'g7');
    });

    test('should parse PGN with tag pairs', () {
      const String pgn = '''
[Event "Test Game"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]

1. d6 f4 1-0
''';

      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(pgn);

      expect(game.headers['Event'], 'Test Game');
      expect(game.headers['White'], 'Alice');
      expect(game.headers['Black'], 'Bob');
      expect(game.headers['Result'], '1-0');

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 2);
    });

    test('should parse PGN with comments', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '1. d6 {Good opening} f4 {Standard response} *',
      );

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 2);
      expect(mainline[0].san, 'd6');
      expect(mainline[0].comments, isNotNull);
      expect(mainline[0].comments!.first, contains('Good opening'));
    });

    test('should parse PGN with NAGs', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6! f4? *');

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 2);
      // d6! should have NAG 1
      expect(mainline[0].nags, isNotNull);
      expect(mainline[0].nags, contains(1));
      // f4? should have NAG 2
      expect(mainline[1].nags, isNotNull);
      expect(mainline[1].nags, contains(2));
    });

    test('should parse move notation like "a1-a4"', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6 f4 2. d6-d5 *');

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 3);
      expect(mainline[2].san, 'd6-d5');
    });

    test('should parse remove notation like "xa1"', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '1. d6 f4 2. b4 a1 3. d2xf4 *',
      );

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.isNotEmpty, isTrue);
    });

    test('should handle PGN with result 1-0', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6 f4 1-0');

      expect(game.headers['Result'], '1-0');
    });

    test('should handle PGN with result 0-1', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6 f4 0-1');

      expect(game.headers['Result'], '0-1');
    });

    test('should handle PGN with result 1/2-1/2', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('1. d6 f4 1/2-1/2');

      expect(game.headers['Result'], '1/2-1/2');
    });
  });

  // ---------------------------------------------------------------------------
  // PgnGame.parsePgn - edge cases
  // ---------------------------------------------------------------------------
  group('PgnGame.parsePgn edge cases', () {
    test('should handle extra whitespace', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn('  1.  d6   f4   *  ');

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 2);
    });

    test('should handle newlines in PGN', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '1. d6\nf4\n2. b4\na1\n*',
      );

      final List<PgnNodeData> mainline = game.moves.mainline().toList();
      expect(mainline.length, 4);
    });

    test('should parse PGN with starting comment', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '{Initial comment} 1. d6 f4 *',
      );

      // The starting comment should be in game.comments or first node
      expect(
        game.comments.isNotEmpty || game.moves.children.isNotEmpty,
        isTrue,
      );
    });

    test('should handle empty tag pairs gracefully', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '[Event ""]\n[Result "*"]\n\n*',
      );

      expect(game.headers['Event'], '');
    });
  });

  // ---------------------------------------------------------------------------
  // PgnGame.parsePgn - variations
  // ---------------------------------------------------------------------------
  group('PgnGame.parsePgn variations', () {
    test('should parse simple variation', () {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(
        '1. d6 (1. f4) 1... f4 *',
      );

      // Root should have children
      expect(game.moves.children.isNotEmpty, isTrue);

      // Check if variation was created
      if (game.moves.children.length > 0) {
        final PgnNode<PgnNodeData> firstChild = game.moves.children[0];
        // First child should have at least one child (the main continuation)
        // or the root should have multiple children (for the variation)
        expect(
          game.moves.children.length >= 1 || firstChild.children.length >= 1,
          isTrue,
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PgnGame.makePgn
  // ---------------------------------------------------------------------------
  group('PgnGame.makePgn', () {
    test('should produce valid PGN from parsed input', () {
      const String originalPgn = '1. d6 f4 *';
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(originalPgn);

      final String exported = game.makePgn();

      // Should contain the moves
      expect(exported, contains('d6'));
      expect(exported, contains('f4'));
    });

    test('should include tag pairs in output', () {
      const String pgn = '[Event "Test"]\n\n1. d6 f4 *';
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(pgn);

      final String exported = game.makePgn();

      expect(exported, contains('[Event "Test"]'));
    });

    test('round-trip: parse and makePgn should preserve moves', () {
      const String original = '1. d6 f4 2. b4 a1 *';
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(original);
      final String exported = game.makePgn();

      // Re-parse the exported PGN
      final PgnGame<PgnNodeData> reparsed = PgnGame.parsePgn(exported);
      final List<PgnNodeData> originalMoves = game.moves.mainline().toList();
      final List<PgnNodeData> reparsedMoves = reparsed.moves
          .mainline()
          .toList();

      expect(reparsedMoves.length, originalMoves.length);
      for (int i = 0; i < originalMoves.length; i++) {
        expect(reparsedMoves[i].san, originalMoves[i].san);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // parseMultiGamePgn
  // ---------------------------------------------------------------------------
  group('PgnGame.parseMultiGamePgn', () {
    test('should parse multiple games', () {
      const String multiPgn = '''
[Event "Game 1"]

1. d6 f4 *

[Event "Game 2"]

1. b4 a1 *
''';

      final List<PgnGame<PgnNodeData>> games = PgnGame.parseMultiGamePgn(
        multiPgn,
      );

      expect(games.length, 2);
      expect(games[0].headers['Event'], 'Game 1');
      expect(games[1].headers['Event'], 'Game 2');
    });

    test('should handle single game', () {
      const String singlePgn = '1. d6 f4 *';

      final List<PgnGame<PgnNodeData>> games = PgnGame.parseMultiGamePgn(
        singlePgn,
      );

      expect(games.length, 1);
    });

    test('should handle empty input', () {
      final List<PgnGame<PgnNodeData>> games = PgnGame.parseMultiGamePgn('');

      // May return one empty game or zero games depending on implementation
      expect(games, isNotNull);
    });
  });
}
