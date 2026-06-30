// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// opening_book_models.dart
//
// Pure-Dart data model for the unified Mill opening book.
//
// A single JSON asset per variant holds two sections:
//   * `oracle`  : canonical Sanmill FEN -> best-move list (the engine-quality
//                 move table that drives AI placement; symmetry-expanded at
//                 lookup time via mill_opening_book_symmetry.dart).
//   * `openings`: rich, human-curated named lines carrying provenance and
//                 annotations (name, source, strategic notes, branches, ...),
//                 used for in-game opening recognition and UI display.
//
// Metadata never lives inside the FEN; the FEN is only ever a lookup key.
// fromJson is deliberately tolerant (missing fields fall back to neutral
// defaults) so hand-edited books and future schema additions stay loadable.

/// One named variation that branches off an [OpeningEntry]'s main line.
class OpeningBranch {
  const OpeningBranch({
    required this.branchId,
    required this.deviationPly,
    required this.deviationMove,
    required this.name,
    required this.lineContinuation,
    required this.strategicNotes,
    required this.source,
    required this.outcomeStats,
  });

  factory OpeningBranch.fromJson(Map<String, dynamic> json) {
    return OpeningBranch(
      branchId: (json['branchId'] ?? json['branch_id'] ?? '') as String,
      deviationPly: (json['deviationPly'] ?? json['deviation_ply'] ?? 0) as int,
      deviationMove:
          (json['deviationMove'] ?? json['deviation_move'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      lineContinuation: _stringList(
        json['lineContinuation'] ?? json['line_continuation'],
      ),
      strategicNotes:
          (json['strategicNotes'] ?? json['strategic_notes'] ?? '') as String,
      source: (json['source'] ?? json['seed_source'] ?? 'book') as String,
      outcomeStats: _intMap(json['outcomeStats'] ?? json['outcome_stats']),
    );
  }

  final String branchId;
  final int deviationPly;
  final String deviationMove;
  final String name;
  final List<String> lineContinuation;
  final String strategicNotes;
  final String source;
  final Map<String, int> outcomeStats;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'branchId': branchId,
    'deviationPly': deviationPly,
    'deviationMove': deviationMove,
    'name': name,
    'lineContinuation': lineContinuation,
    'strategicNotes': strategicNotes,
    'source': source,
    'outcomeStats': outcomeStats,
  };
}

/// A rich, named opening line with provenance and annotations.
class OpeningEntry {
  const OpeningEntry({
    required this.id,
    required this.name,
    required this.aliases,
    required this.family,
    required this.side,
    required this.source,
    required this.sourceReference,
    required this.confidence,
    required this.tags,
    required this.strategicNotes,
    required this.commonBlunders,
    required this.recommendedResponses,
    required this.outcomeStats,
    required this.lineMoves,
    required this.branchMoves,
    required this.favoredSide,
  });

  factory OpeningEntry.fromJson(Map<String, dynamic> json) {
    return OpeningEntry(
      id: (json['id'] ?? json['opening_id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      aliases: _stringList(json['aliases']),
      family: (json['family'] ?? '') as String,
      side: (json['side'] ?? 'both') as String,
      source: (json['source'] ?? json['seed_source'] ?? 'book') as String,
      sourceReference:
          (json['sourceReference'] ?? json['source_reference'] ?? '') as String,
      confidence: ((json['confidence'] ?? 1.0) as num).toDouble(),
      tags: _stringList(json['tags']),
      strategicNotes:
          (json['strategicNotes'] ?? json['strategic_notes'] ?? '') as String,
      commonBlunders: _stringList(
        json['commonBlunders'] ?? json['common_blunders'],
      ),
      recommendedResponses: _stringListMap(
        json['recommendedResponses'] ?? json['recommended_responses'],
      ),
      outcomeStats: _intMap(json['outcomeStats'] ?? json['outcome_stats']),
      lineMoves: _stringList(json['lineMoves'] ?? json['line_moves']),
      branchMoves: _branchList(json['branchMoves'] ?? json['branch_moves']),
      favoredSide:
          (json['favoredSide'] ?? json['favored_side'] ?? 'equal') as String,
    );
  }

  final String id;
  final String name;
  final List<String> aliases;
  final String family;

  /// "W", "B", or "both".
  final String side;

  /// Provenance: "book" | "learned" | "human" | "oracle".
  final String source;
  final String sourceReference;
  final double confidence;
  final List<String> tags;
  final String strategicNotes;
  final List<String> commonBlunders;

  /// Suggested replies keyed by side ("W" / "B").
  final Map<String, List<String>> recommendedResponses;

  /// Read-only win/draw/loss tally retained for a future learning subsystem;
  /// the current build never mutates it nor uses it for move selection.
  final Map<String, int> outcomeStats;

  /// Alternating placement moves in placement notation (e.g. "d2", "d6").
  final List<String> lineMoves;
  final List<OpeningBranch> branchMoves;

  /// Which side the line is expected to favour: "W", "B", or "equal".
  ///
  /// Distinct from [side] (which colour plays the line). Used to display the
  /// expected outcome and, when enabled, to bias the AI toward openings that
  /// favour its own colour.
  final String favoredSide;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'aliases': aliases,
    'family': family,
    'side': side,
    'source': source,
    'sourceReference': sourceReference,
    'confidence': confidence,
    'tags': tags,
    'strategicNotes': strategicNotes,
    'commonBlunders': commonBlunders,
    'recommendedResponses': recommendedResponses,
    'outcomeStats': outcomeStats,
    'lineMoves': lineMoves,
    'branchMoves': branchMoves
        .map((OpeningBranch b) => b.toJson())
        .toList(growable: false),
    'favoredSide': favoredSide,
  };
}

/// Top-level unified opening book for one Mill variant.
class OpeningBookData {
  const OpeningBookData({
    required this.schemaVersion,
    required this.variant,
    required this.symmetry,
    required this.oracle,
    required this.openings,
  });

  factory OpeningBookData.fromJson(Map<String, dynamic> json) {
    final Map<String, List<String>> oracle = <String, List<String>>{};
    final Object? rawOracle = json['oracle'];
    if (rawOracle is Map) {
      rawOracle.forEach((Object? key, Object? value) {
        oracle[key! as String] = _stringList(value);
      });
    }
    final List<OpeningEntry> openings = <OpeningEntry>[];
    final Object? rawOpenings = json['openings'];
    if (rawOpenings is List) {
      for (final Object? raw in rawOpenings) {
        if (raw is Map) {
          openings.add(OpeningEntry.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return OpeningBookData(
      schemaVersion: (json['schemaVersion'] ?? 1) as int,
      variant: (json['variant'] ?? '') as String,
      symmetry: (json['symmetry'] ?? 'ring16') as String,
      oracle: oracle,
      openings: openings,
    );
  }

  /// Bumped when the on-disk schema changes incompatibly.
  final int schemaVersion;

  /// Variant id, e.g. "nmm" or "el_filja".
  final String variant;

  /// Symmetry group tag; "ring16" = Sanmill D4 x inner/outer-ring swap.
  final String symmetry;

  /// Canonical Sanmill FEN -> best-move list (canonical frame).
  final Map<String, List<String>> oracle;

  /// Rich named lines (may be empty for variants without curated openings).
  final List<OpeningEntry> openings;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'variant': variant,
    'symmetry': symmetry,
    'oracle': oracle,
    'openings': openings
        .map((OpeningEntry o) => o.toJson())
        .toList(growable: false),
  };
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw.map((Object? e) => e.toString()).toList(growable: false);
  }
  return const <String>[];
}

Map<String, int> _intMap(Object? raw) {
  final Map<String, int> result = <String, int>{};
  if (raw is Map) {
    raw.forEach((Object? key, Object? value) {
      if (value is num) {
        result[key.toString()] = value.toInt();
      }
    });
  }
  return result;
}

Map<String, List<String>> _stringListMap(Object? raw) {
  final Map<String, List<String>> result = <String, List<String>>{};
  if (raw is Map) {
    raw.forEach((Object? key, Object? value) {
      result[key.toString()] = _stringList(value);
    });
  }
  return result;
}

List<OpeningBranch> _branchList(Object? raw) {
  if (raw is List) {
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> e) =>
              OpeningBranch.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(growable: false);
  }
  return const <OpeningBranch>[];
}
