// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Maintainer tool: assemble the shipped unified opening book asset.
//
//   dart run tool/build_opening_book.dart
//
// It merges AUTHORED SOURCES (all under tool/) into one JSON per variant:
//   * the engine move oracle (canonical Sanmill FEN -> moves) in
//     tool/mill_opening_book_oracle_source.dart,
//   * the curated, human-readable named openings in
//     tool/<variant>_curated_openings.json (Sanmill source schema; the legacy
//     NMM_LLM array schema is still accepted during migration), and
//   * the imported/self-play learned openings in
//     tool/<variant>_learned_openings.json (legacy NMM_LLM array schema).
//
// Curated and learned openings are concatenated and then deduplicated under the
// board's full 16-element symmetry group (D4 x inner/outer ring swap): lines
// that coincide after some rotation, reflection, or ring swap collapse to a
// single entry, keeping the highest-priority representative (curated > book
// import > novel self-play).
//
// Outputs:
//   * assets/opening_books/<variant>/opening_book.json — the ONLY shipped
//     artefact, consumed at runtime by OpeningBookRepository. The oracle
//     section is copied verbatim and a parity check confirms the round-tripped
//     JSON reproduces the authored oracle exactly, so AI move selection is
//     unchanged.
//   * tool/<variant>_opening_book_atlas.md — a committed, human-readable view:
//     an ASCII board per oracle position plus a metadata summary per named
//     opening (JSON cannot hold these board comments because FEN keys contain
//     "/*" and "*/").

import 'dart:convert';
import 'dart:io';

import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_source_models.dart';

import 'mill_opening_book_oracle_source.dart';

const String _nmmDir = 'assets/opening_books/nmm';
const String _elFiljaDir = 'assets/opening_books/el_filja';
const String _nmmCuratedSource = 'tool/nmm_curated_openings.json';
const String _nmmLearnedSource = 'tool/nmm_learned_openings.json';

/// Parses every opening in [path] (Sanmill source package or legacy NMM_LLM
/// array) in file order, without filtering. A missing file yields an empty
/// list so optional sources stay optional.
List<OpeningEntry> _loadOpeningEntries(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('note: $path not found; skipping.');
    return <OpeningEntry>[];
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is List) {
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> raw) =>
              OpeningEntry.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList(growable: false);
  }
  if (decoded is Map) {
    return SanmillOpeningBookSourcePackage.fromJson(
      Map<String, dynamic>.from(decoded),
    ).toOpeningEntries();
  }
  throw FormatException(
    'opening source must be a JSON array or package: $path',
  );
}

/// Tie-break priority when several openings collapse onto the same symmetry
/// class. Lower wins: hand-curated book lines first, then imported book games,
/// then self-play "novel" discoveries, then anything else.
int _openingRank(OpeningEntry entry) {
  if (entry.source == 'book') {
    return 0;
  }
  if (entry.id.startsWith('book-')) {
    return 1;
  }
  if (entry.id.startsWith('novel-')) {
    return 2;
  }
  return 3;
}

/// Canonical key for a placement line under the board's full 16-element
/// symmetry group (D4 x inner/outer ring swap): the lexicographically smallest
/// of all 16 transformed move sequences. Two lines share a key iff they are the
/// same sequence of positions up to rotation, reflection, and ring swap.
String _canonicalLineKey(List<String> moves) {
  assert(moves.isNotEmpty, 'line must contain at least one move');
  String? best;
  for (final TransformationType type in TransformationType.values) {
    final String candidate = moves
        .map((String move) => transformMoveNotation(move, type))
        .join(',');
    if (best == null || candidate.compareTo(best) < 0) {
      best = candidate;
    }
  }
  return best!;
}

/// Concatenates all opening sources and drops symmetry-equivalent duplicates,
/// keeping the highest-priority representative of each class (see
/// [_openingRank]). Output order is stable and diff-friendly: by rank first,
/// then by original load order.
List<OpeningEntry> _mergeAndDedupOpenings(List<OpeningEntry> entries) {
  final List<int> order = List<int>.generate(entries.length, (int i) => i);
  order.sort((int a, int b) {
    final int byRank = _openingRank(
      entries[a],
    ).compareTo(_openingRank(entries[b]));
    return byRank != 0 ? byRank : a.compareTo(b);
  });

  final Set<String> seen = <String>{};
  final List<OpeningEntry> kept = <OpeningEntry>[];
  int dropped = 0;
  for (final int index in order) {
    final OpeningEntry entry = entries[index];
    assert(entry.lineMoves.isNotEmpty, 'opening ${entry.id} has no line moves');
    if (seen.add(_canonicalLineKey(entry.lineMoves))) {
      kept.add(entry);
    } else {
      dropped++;
    }
  }
  stdout.writeln(
    'Merged ${entries.length} openings -> ${kept.length} unique '
    '($dropped symmetry duplicate(s) removed).',
  );
  return kept;
}

/// Standard Nine Men's Morris mills (no diagonals), in placement notation.
const List<List<String>> _nmmMills = <List<String>>[
  <String>['a7', 'd7', 'g7'],
  <String>['b6', 'd6', 'f6'],
  <String>['c5', 'd5', 'e5'],
  <String>['a4', 'b4', 'c4'],
  <String>['e4', 'f4', 'g4'],
  <String>['c3', 'd3', 'e3'],
  <String>['b2', 'd2', 'f2'],
  <String>['a1', 'd1', 'g1'],
  <String>['a7', 'a4', 'a1'],
  <String>['b6', 'b4', 'b2'],
  <String>['c5', 'c4', 'c3'],
  <String>['d7', 'd6', 'd5'],
  <String>['d3', 'd2', 'd1'],
  <String>['e5', 'e4', 'e3'],
  <String>['f6', 'f4', 'f2'],
  <String>['g7', 'g4', 'g1'],
];

/// Length of the longest valid placement prefix of [moves].
///
/// Placement alternates between the two players (even plies = first player).
/// A square may only be re-used after a mill-forming move frees an opponent
/// piece; because removals are stripped from the stored line, we credit one
/// re-placement per mill formed. The placement phase caps at 18 moves (9 per
/// side), so anything beyond — or any placement onto an occupied square without
/// an available removal credit — is moving-phase data or noise and is dropped.
int _validPlacementPrefix(List<String> moves) {
  final Map<String, int> occupied = <String, int>{};
  int removalCredits = 0;
  final int limit = moves.length < 18 ? moves.length : 18;
  int kept = 0;
  for (; kept < limit; kept++) {
    final String square = moves[kept];
    final int player = kept.isEven ? 0 : 1;
    if (occupied.containsKey(square)) {
      if (removalCredits == 0) {
        break;
      }
      removalCredits--;
    }
    occupied[square] = player;
    final bool formedMill = _nmmMills.any(
      (List<String> mill) =>
          mill.contains(square) &&
          mill.every((String s) => occupied[s] == player),
    );
    if (formedMill) {
      removalCredits++;
    }
  }
  return kept;
}

/// Returns [entry] truncated to its valid placement prefix (see
/// [_validPlacementPrefix]); the original entry is returned untouched when the
/// whole line is already valid. Branches anchored beyond the kept prefix are
/// dropped so the line stays self-consistent.
OpeningEntry _sanitizeOpening(OpeningEntry entry) {
  final int keep = _validPlacementPrefix(entry.lineMoves);
  if (keep == entry.lineMoves.length) {
    return entry;
  }
  return OpeningEntry(
    id: entry.id,
    name: entry.name,
    aliases: entry.aliases,
    family: entry.family,
    side: entry.side,
    source: entry.source,
    sourceReference: entry.sourceReference,
    confidence: entry.confidence,
    tags: entry.tags,
    strategicNotes: entry.strategicNotes,
    commonBlunders: entry.commonBlunders,
    recommendedResponses: entry.recommendedResponses,
    outcomeStats: entry.outcomeStats,
    lineMoves: entry.lineMoves.sublist(0, keep),
    branchMoves: entry.branchMoves
        .where((OpeningBranch branch) => branch.deviationPly <= keep)
        .toList(growable: false),
    favoredSide: entry.favoredSide,
  );
}

/// Assembles the shipped NMM named openings: the hand-curated book lines plus
/// the imported/self-play learned lines. Each line is first sanitised to a
/// valid placement prefix (dropping moving-phase/corrupt tails), then the whole
/// set is symmetry-deduplicated.
List<OpeningEntry> _assembleNmmOpenings() {
  final List<OpeningEntry> all = <OpeningEntry>[
    ..._loadOpeningEntries(_nmmCuratedSource),
    ..._loadOpeningEntries(_nmmLearnedSource),
  ];

  int truncated = 0;
  final List<OpeningEntry> sanitized = <OpeningEntry>[];
  for (final OpeningEntry entry in all) {
    final OpeningEntry clean = _sanitizeOpening(entry);
    if (clean.lineMoves.length != entry.lineMoves.length) {
      truncated++;
    }
    // A line shorter than two plies carries no usable opening knowledge.
    if (clean.lineMoves.length >= 2) {
      sanitized.add(clean);
    }
  }
  stdout.writeln(
    'Sanitised ${all.length} openings: $truncated truncated, '
    '${all.length - sanitized.length} dropped (too short).',
  );
  return _mergeAndDedupOpenings(sanitized);
}

void _writeBook(String dir, OpeningBookData data) {
  Directory(dir).createSync(recursive: true);
  final String path = '$dir/opening_book.json';
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  File(path).writeAsStringSync('${encoder.convert(data.toJson())}\n');

  // Parity guard: the persisted oracle must round-trip byte-for-set identically
  // to the authored Dart oracle so AI placement strength is preserved.
  final OpeningBookData reparsed = OpeningBookData.fromJson(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  );
  if (reparsed.oracle.length != data.oracle.length) {
    throw StateError('oracle parity failed for $dir (key count mismatch)');
  }
  for (final MapEntry<String, List<String>> e in data.oracle.entries) {
    final List<String>? got = reparsed.oracle[e.key];
    if (got == null || got.join(',') != e.value.join(',')) {
      throw StateError('oracle parity failed for $dir at key ${e.key}');
    }
  }
  stdout.writeln(
    'Wrote $path: ${data.oracle.length} oracle entries, '
    '${data.openings.length} named openings.',
  );
}

// ---------------------------------------------------------------------------
// Human-readable board atlas
// ---------------------------------------------------------------------------
//
// JSON cannot carry the ASCII board diagrams that the authored oracle source
// keeps (and comment-stripping is unsafe because FEN keys contain "/*" and
// "*/"). So the readability lives in a generated companion atlas instead: the
// oracle gets a board per position, named openings get a metadata summary.

/// Board-position index (0-23) -> point notation, matching the FEN ring order
/// (inner / middle / outer) used by the oracle keys.
const List<String> _fenIndexToNotation = <String>[
  'd5', 'e5', 'e4', 'e3', 'd3', 'c3', 'c4', 'c5', //
  'd6', 'f6', 'f4', 'f2', 'd2', 'b2', 'b4', 'b6', //
  'd7', 'g7', 'g4', 'g1', 'd1', 'a1', 'a4', 'a7', //
];

/// Coordinate-labelled board; occupied points are overwritten with ` O` / ` @`.
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

String _renderBoard(String fen) {
  final String board = fen.substring(0, 26).replaceAll('/', '');
  String diagram = _boardTemplate;
  for (int i = 0; i < 24 && i < board.length; i++) {
    final String glyph = switch (board[i]) {
      'O' => ' O',
      '@' => ' @',
      'X' => ' X',
      _ => '',
    };
    if (glyph.isNotEmpty) {
      diagram = diagram.replaceAll(_fenIndexToNotation[i], glyph);
    }
  }
  return diagram;
}

void _writeAtlas(String atlasPath, OpeningBookData data, String title) {
  // Markdown so it can live in version control (`.md` is not gitignored) and
  // render on GitHub. Monospaced blocks are fenced so the board art keeps its
  // alignment.
  final StringBuffer b = StringBuffer()
    ..writeln('# $title opening book atlas')
    ..writeln()
    ..writeln('GENERATED by `tool/build_opening_book.dart` -- do not edit.')
    ..writeln()
    ..writeln(
      'Readable view of '
      '`assets/opening_books/${data.variant}/opening_book.json`. '
      'Empty points keep their coordinate label; '
      '`O` = first player, `@` = second.',
    )
    ..writeln()
    ..writeln('## Oracle (${data.oracle.length} canonical positions)')
    ..writeln()
    ..writeln('```text');

  final List<String> keys = data.oracle.keys.toList()..sort();
  for (final String key in keys) {
    b
      ..writeln('FEN: $key')
      ..writeln(_renderBoard(key))
      ..writeln('best: ${data.oracle[key]!.join(", ")}')
      ..writeln();
  }

  b
    ..writeln('```')
    ..writeln()
    ..writeln('## Named openings (${data.openings.length})')
    ..writeln();

  if (data.openings.isEmpty) {
    b.writeln('_None for this variant._');
  } else {
    b.writeln('```text');
    for (final OpeningEntry o in data.openings) {
      b
        ..writeln('[${o.id}] ${o.name}')
        ..writeln(
          '  side ${o.side} | favours ${o.favoredSide} | source ${o.source}',
        );
      if (o.family.isNotEmpty) {
        b.writeln('  family: ${o.family}');
      }
      if (o.aliases.isNotEmpty) {
        b.writeln('  aliases: ${o.aliases.join(", ")}');
      }
      if (o.sourceReference.isNotEmpty) {
        b.writeln('  reference: ${o.sourceReference}');
      }
      b.writeln('  line: ${o.lineMoves.join(" ")}');
      if (o.strategicNotes.isNotEmpty) {
        b.writeln('  notes: ${o.strategicNotes}');
      }
      if (o.commonBlunders.isNotEmpty) {
        b.writeln('  avoid: ${o.commonBlunders.join(", ")}');
      }
      for (final MapEntry<String, List<String>> r
          in o.recommendedResponses.entries) {
        if (r.value.isNotEmpty) {
          b.writeln('  reply (${r.key}): ${r.value.join(", ")}');
        }
      }
      for (final OpeningBranch branch in o.branchMoves) {
        b.writeln(
          '  branch [ply ${branch.deviationPly} ${branch.deviationMove}] '
          '${branch.name}: ${branch.lineContinuation.join(" ")}',
        );
        if (branch.strategicNotes.isNotEmpty) {
          b.writeln('    ${branch.strategicNotes}');
        }
      }
      b.writeln();
    }
    b.writeln('```');
  }

  File(atlasPath).writeAsStringSync(b.toString());
  stdout.writeln('Wrote $atlasPath');
}

void main() {
  final OpeningBookData nmm = OpeningBookData(
    schemaVersion: 1,
    variant: 'nmm',
    symmetry: 'ring16',
    oracle: nineMensMorrisCanonicalOpeningBook,
    openings: _assembleNmmOpenings(),
  );
  _writeBook(_nmmDir, nmm);
  _writeAtlas('tool/nmm_opening_book_atlas.md', nmm, "Nine Men's Morris");

  // El Filja ships the move oracle only; it has no curated named lines yet.
  final OpeningBookData elFilja = OpeningBookData(
    schemaVersion: 1,
    variant: 'el_filja',
    symmetry: 'ring16',
    oracle: elFiljaCanonicalOpeningBook,
    openings: const <OpeningEntry>[],
  );
  _writeBook(_elFiljaDir, elFilja);
  _writeAtlas('tool/el_filja_opening_book_atlas.md', elFilja, 'El Filja');
}
