// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Maintainer tool: assemble the shipped unified opening book asset.
//
//   dart run tool/build_opening_book.dart
//
// It merges two AUTHORED SOURCES (both under tool/) into one JSON per variant:
//   * the engine move oracle (canonical Sanmill FEN -> moves) in
//     tool/mill_opening_book_oracle_source.dart, and
//   * the curated, human-readable named openings in
//     tool/<variant>_curated_openings.json (Sanmill source schema; the legacy
//     NMM_LLM array schema is still accepted during migration).
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

import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_source_models.dart';

import 'mill_opening_book_oracle_source.dart';

const String _nmmDir = 'assets/opening_books/nmm';
const String _elFiljaDir = 'assets/opening_books/el_filja';
const String _nmmCuratedSource = 'tool/nmm_curated_openings.json';

List<OpeningEntry> _loadCuratedOpenings(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('note: $path not found; emitting no named openings.');
    return <OpeningEntry>[];
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  final List<OpeningEntry> entries;
  if (decoded is List) {
    entries = decoded
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> raw) =>
              OpeningEntry.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList(growable: false);
  } else if (decoded is Map) {
    entries = SanmillOpeningBookSourcePackage.fromJson(
      Map<String, dynamic>.from(decoded),
    ).toOpeningEntries();
  } else {
    throw const FormatException(
      'curated openings file must be a JSON array or source package',
    );
  }

  final List<OpeningEntry> openings = <OpeningEntry>[];
  for (final OpeningEntry entry in entries) {
    // Only ship curated book lines; learned/self-play entries stay out of
    // the bundled asset (loader can opt them in later).
    if (entry.source == 'book') {
      openings.add(entry);
    }
  }
  return openings;
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
    openings: _loadCuratedOpenings(_nmmCuratedSource),
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
