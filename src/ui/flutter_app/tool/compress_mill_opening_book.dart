// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Maintainer tool: canonicalise the Mill opening-book tables.
//
// The book stores one representative best-move line per 16-way symmetry orbit,
// keyed by the lexicographically smallest FEN in that orbit. A maintainer may
// add a new opening in ANY orientation to mill_opening_book_data.dart; running
//
//   dart run tool/compress_mill_opening_book.dart
//
// rewrites every entry in canonical form (canonical FEN key + the move line
// expressed in the canonical frame). The transform is idempotent, so running
// it on already-canonical data reproduces the file unchanged.

import 'dart:convert';
import 'dart:io';

import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/mill_opening_book_data.dart';
import 'package:sanmill/games/mill/mill_opening_book_symmetry.dart';

/// Re-expresses [moves] (legal in [fen]'s frame) in the canonical frame.
List<String> _toCanonicalFrame(String fen, List<String> moves) {
  final TransformationType toCanonical = symmetryToCanonical(fen);
  return moves
      .map((String move) => transformMoveNotation(move, toCanonical))
      .toList();
}

Map<String, List<String>> _canonicalise(Map<String, List<String>> raw) {
  final Map<String, List<String>> canonical = <String, List<String>>{};
  for (final MapEntry<String, List<String>> entry in raw.entries) {
    final String normalized = normalizeOpeningBookFen(entry.key);
    final String canonicalKey = canonicalOpeningBookFen(normalized);
    final List<String> canonicalMoves = _toCanonicalFrame(
      normalized,
      entry.value,
    );
    final List<String>? existing = canonical[canonicalKey];
    if (existing != null &&
        existing.toSet().difference(canonicalMoves.toSet()).isNotEmpty) {
      stderr.writeln(
        'warning: $canonicalKey already has a different move set; '
        'keeping the first occurrence',
      );
      continue;
    }
    canonical[canonicalKey] = canonicalMoves;
  }
  return canonical;
}

/// Board point notation indexed by FEN board position (0-23).
///
/// FEN board segments are inner / middle / outer, matching the ring layout in
/// transform.dart's `_transformIndexToNotation`.
const List<String> _fenIndexToNotation = <String>[
  // Inner ring (0-7)
  'd5', 'e5', 'e4', 'e3', 'd3', 'c3', 'c4', 'c5',
  // Middle ring (8-15)
  'd6', 'f6', 'f4', 'f2', 'd2', 'b2', 'b4', 'b6',
  // Outer ring (16-23)
  'd7', 'g7', 'g4', 'g1', 'd1', 'a1', 'a4', 'a7',
];

/// Coordinate-labelled board template; each 2-char point label is replaced by
/// ` O` (white) or ` @` (black) when that point is occupied.
const String _boardTemplate =
    '    a7 ----- d7 ----- g7\n'
    '    |         |        |\n'
    '    |  b6 -- d6 -- f6  |\n'
    '    |  |      |     |  |\n'
    '    |  |  c5-d5-e5  |  |\n'
    '    a4-b4-c4    e4-f4-g4\n'
    '    |  |  c3-d3-e3  |  |\n'
    '    |  |      |     |  |\n'
    '    |  b2 -- d2 -- f2  |\n'
    '    |         |        |\n'
    '    a1 ----- d1 ----- g1';

/// Renders the FEN board part as an ASCII block comment for readability.
///
/// Occupied points show their piece (`O`/`@`); empty points keep their
/// coordinate label so the diagram doubles as a coordinate legend.
String _renderBoard(String fen) {
  final String board = fen.substring(0, 26).replaceAll('/', '');
  assert(board.length == 24, 'FEN board must have 24 points');
  String diagram = _boardTemplate;
  for (int i = 0; i < 24; i++) {
    final String cell = board[i];
    if (cell == '*') {
      continue;
    }
    final String glyph = cell == 'O' ? ' O' : ' @';
    diagram = diagram.replaceAll(_fenIndexToNotation[i], glyph);
  }
  return '  /*\n$diagram\n  */';
}

String _renderMap(String name, Map<String, List<String>> book) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('Map<String, List<String>> $name = <String, List<String>>{');
  final List<String> keys = book.keys.toList()..sort();
  for (final String key in keys) {
    final String moves = book[key]!.map(jsonEncode).join(', ');
    buffer.writeln(_renderBoard(key));
    buffer.writeln('  ${jsonEncode(key)}: <String>[$moves],');
  }
  buffer.writeln('};');
  return buffer.toString();
}

void main() {
  final Map<String, List<String>> nine = _canonicalise(
    nineMensMorrisCanonicalOpeningBook,
  );
  final Map<String, List<String>> elFilja = _canonicalise(
    elFiljaCanonicalOpeningBook,
  );

  final String content =
      '''
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_opening_book_data.dart
//
// Canonical FEN -> best-move tables for Nine Men's Morris and El Filja.
//
// Each key is the lexicographically smallest FEN in its 16-way symmetry orbit
// and stores a single representative best-move line in that canonical frame.
// [MillOpeningBookProvider] maps a query position onto its canonical key and
// rotates the stored line back into the query frame via transform.dart, so the
// 16 symmetric variants of every position are covered without duplicating data.
//
// Regenerate after editing entries with:
//   dart run tool/compress_mill_opening_book.dart

${_renderMap('nineMensMorrisCanonicalOpeningBook', nine)}
${_renderMap('elFiljaCanonicalOpeningBook', elFilja)}''';

  File('lib/games/mill/mill_opening_book_data.dart').writeAsStringSync(content);
  stdout.writeln(
    'Wrote ${nine.length} + ${elFilja.length} canonical opening-book entries.',
  );
}
