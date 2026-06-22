// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'opening_book_models.dart';

const String sanmillOpeningBookSourceFormat = 'sanmill.openingBook.source';

const List<String> sanmillOpeningBookCoordinates = <String>[
  'a7',
  'd7',
  'g7',
  'b6',
  'd6',
  'f6',
  'c5',
  'd5',
  'e5',
  'a4',
  'b4',
  'c4',
  'e4',
  'f4',
  'g4',
  'c3',
  'd3',
  'e3',
  'b2',
  'd2',
  'f2',
  'a1',
  'd1',
  'g1',
];

List<String> parseOpeningMoveList(String value) {
  return value
      .split(RegExp(r'[\s,;]+'))
      .map((String token) => token.trim().toLowerCase())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

String formatOpeningMoveList(List<String> moves) => moves.join(' ');

class SanmillOpeningBookSourcePackage {
  const SanmillOpeningBookSourcePackage({
    required this.format,
    required this.schemaVersion,
    required this.game,
    required this.variant,
    required this.rules,
    required this.notation,
    required this.book,
    required this.openings,
  });

  factory SanmillOpeningBookSourcePackage.nmm({
    required List<SanmillOpeningSourceEntry> openings,
  }) {
    return SanmillOpeningBookSourcePackage(
      format: sanmillOpeningBookSourceFormat,
      schemaVersion: 1,
      game: 'mill',
      variant: 'nmm',
      rules: const <String, Object?>{'id': 'standard_9mm', 'pieces': 9},
      notation: const SanmillOpeningNotation(),
      book: const SanmillOpeningBookMetadata(),
      openings: openings,
    );
  }

  factory SanmillOpeningBookSourcePackage.fromJson(Map<String, dynamic> json) {
    final Object? rawOpenings = json['openings'];
    final List<SanmillOpeningSourceEntry> openings = rawOpenings is List
        ? rawOpenings
              .whereType<Map<Object?, Object?>>()
              .map(
                (Map<Object?, Object?> raw) =>
                    SanmillOpeningSourceEntry.fromJson(
                      Map<String, dynamic>.from(raw),
                    ),
              )
              .toList(growable: false)
        : const <SanmillOpeningSourceEntry>[];
    return SanmillOpeningBookSourcePackage(
      format: (json['format'] ?? sanmillOpeningBookSourceFormat) as String,
      schemaVersion: (json['schemaVersion'] ?? 1) as int,
      game: (json['game'] ?? 'mill') as String,
      variant: (json['variant'] ?? 'nmm') as String,
      rules: _objectMap(json['rules']),
      notation: SanmillOpeningNotation.fromJson(_jsonMap(json['notation'])),
      book: SanmillOpeningBookMetadata.fromJson(_jsonMap(json['book'])),
      openings: openings,
    );
  }

  factory SanmillOpeningBookSourcePackage.fromOpeningEntries(
    List<OpeningEntry> entries,
  ) {
    return SanmillOpeningBookSourcePackage.nmm(
      openings: entries
          .map(SanmillOpeningSourceEntry.fromOpeningEntry)
          .toList(growable: false),
    );
  }

  final String format;
  final int schemaVersion;
  final String game;
  final String variant;
  final Map<String, Object?> rules;
  final SanmillOpeningNotation notation;
  final SanmillOpeningBookMetadata book;
  final List<SanmillOpeningSourceEntry> openings;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'schemaVersion': schemaVersion,
    'game': game,
    'variant': variant,
    'rules': rules,
    'notation': notation.toJson(),
    'book': book.toJson(),
    'openings': openings
        .map((SanmillOpeningSourceEntry opening) => opening.toJson())
        .toList(growable: false),
  };

  List<OpeningEntry> toOpeningEntries() {
    return openings
        .map((SanmillOpeningSourceEntry opening) => opening.toOpeningEntry())
        .toList(growable: false);
  }

  SanmillOpeningBookSourcePackage copyWith({
    List<SanmillOpeningSourceEntry>? openings,
  }) {
    return SanmillOpeningBookSourcePackage(
      format: format,
      schemaVersion: schemaVersion,
      game: game,
      variant: variant,
      rules: rules,
      notation: notation,
      book: book,
      openings: openings ?? this.openings,
    );
  }
}

class SanmillOpeningNotation {
  const SanmillOpeningNotation({
    this.type = 'sanmill-coordinate',
    this.phase = 'placement',
    this.coordinates = sanmillOpeningBookCoordinates,
  });

  factory SanmillOpeningNotation.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningNotation(
      type: (json['type'] ?? 'sanmill-coordinate') as String,
      phase: (json['phase'] ?? 'placement') as String,
      coordinates: _stringList(json['coordinates']).isEmpty
          ? sanmillOpeningBookCoordinates
          : _stringList(json['coordinates']),
    );
  }

  final String type;
  final String phase;
  final List<String> coordinates;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'phase': phase,
    'coordinates': coordinates,
  };
}

class SanmillOpeningBookMetadata {
  const SanmillOpeningBookMetadata({
    this.id = 'sanmill-nmm-core',
    this.name = 'Sanmill NMM Opening Book',
    this.source = 'manual',
    this.createdBy = 'Sanmill Opening Book Studio',
  });

  factory SanmillOpeningBookMetadata.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningBookMetadata(
      id: (json['id'] ?? 'sanmill-nmm-core') as String,
      name: (json['name'] ?? 'Sanmill NMM Opening Book') as String,
      source: (json['source'] ?? 'manual') as String,
      createdBy: (json['createdBy'] ?? 'Sanmill Opening Book Studio') as String,
    );
  }

  final String id;
  final String name;
  final String source;
  final String createdBy;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'source': source,
    'createdBy': createdBy,
  };
}

class SanmillOpeningSourceEntry {
  const SanmillOpeningSourceEntry({
    required this.id,
    required this.name,
    required this.family,
    required this.aliases,
    required this.side,
    required this.favoredSide,
    required this.confidence,
    required this.tags,
    required this.stats,
    required this.line,
    required this.commonBlunders,
    required this.recommendedResponses,
    required this.source,
    required this.sourceReference,
  });

  factory SanmillOpeningSourceEntry.empty(int index) {
    return SanmillOpeningSourceEntry(
      id: 'new-opening-$index',
      name: 'New Opening $index',
      family: 'Custom',
      aliases: const <String>[],
      side: 'both',
      favoredSide: 'equal',
      confidence: 1.0,
      tags: const <String>['placement'],
      stats: const SanmillOpeningStats(),
      line: const SanmillOpeningLine(moves: <String>['d2', 'd6']),
      commonBlunders: const <String>[],
      recommendedResponses: const <String, List<String>>{},
      source: 'book',
      sourceReference: 'Opening Book Studio',
    );
  }

  factory SanmillOpeningSourceEntry.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningSourceEntry(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      family: (json['family'] ?? '') as String,
      aliases: _stringList(json['aliases']),
      side: (json['side'] ?? 'both') as String,
      favoredSide: (json['favoredSide'] ?? 'equal') as String,
      confidence: ((json['confidence'] ?? 1.0) as num).toDouble(),
      tags: _stringList(json['tags']),
      stats: SanmillOpeningStats.fromJson(_jsonMap(json['stats'])),
      line: SanmillOpeningLine.fromJson(_jsonMap(json['line'])),
      commonBlunders: _stringList(json['commonBlunders']),
      recommendedResponses: _stringListMap(json['recommendedResponses']),
      source: (json['source'] ?? 'book') as String,
      sourceReference: (json['sourceReference'] ?? '') as String,
    );
  }

  factory SanmillOpeningSourceEntry.fromOpeningEntry(OpeningEntry entry) {
    return SanmillOpeningSourceEntry(
      id: entry.id,
      name: entry.name,
      family: entry.family,
      aliases: entry.aliases,
      side: entry.side,
      favoredSide: entry.favoredSide,
      confidence: entry.confidence,
      tags: entry.tags,
      stats: SanmillOpeningStats.fromLegacyOutcomeStats(entry.outcomeStats),
      line: SanmillOpeningLine(
        moves: entry.lineMoves,
        comment: entry.strategicNotes,
        variations: entry.branchMoves
            .map(SanmillOpeningVariation.fromOpeningBranch)
            .toList(growable: false),
      ),
      commonBlunders: entry.commonBlunders,
      recommendedResponses: entry.recommendedResponses,
      source: entry.source,
      sourceReference: entry.sourceReference,
    );
  }

  final String id;
  final String name;
  final String family;
  final List<String> aliases;
  final String side;
  final String favoredSide;
  final double confidence;
  final List<String> tags;
  final SanmillOpeningStats stats;
  final SanmillOpeningLine line;
  final List<String> commonBlunders;
  final Map<String, List<String>> recommendedResponses;
  final String source;
  final String sourceReference;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'family': family,
    'aliases': aliases,
    'side': side,
    'favoredSide': favoredSide,
    'confidence': confidence,
    'tags': tags,
    'stats': stats.toJson(),
    'line': line.toJson(),
    'commonBlunders': commonBlunders,
    'recommendedResponses': recommendedResponses,
    'source': source,
    'sourceReference': sourceReference,
  };

  OpeningEntry toOpeningEntry() {
    return OpeningEntry(
      id: id,
      name: name,
      aliases: aliases,
      family: family,
      side: side,
      source: source,
      sourceReference: sourceReference,
      confidence: confidence,
      tags: tags,
      strategicNotes: line.comment,
      commonBlunders: commonBlunders,
      recommendedResponses: recommendedResponses,
      outcomeStats: stats.toLegacyOutcomeStats(),
      lineMoves: line.moves,
      branchMoves: line.variations
          .map((SanmillOpeningVariation variation) {
            return variation.toOpeningBranch(source: source);
          })
          .toList(growable: false),
      favoredSide: favoredSide,
    );
  }

  SanmillOpeningSourceEntry copyWith({
    String? id,
    String? name,
    String? family,
    List<String>? aliases,
    String? side,
    String? favoredSide,
    double? confidence,
    List<String>? tags,
    SanmillOpeningStats? stats,
    SanmillOpeningLine? line,
    List<String>? commonBlunders,
    Map<String, List<String>>? recommendedResponses,
    String? source,
    String? sourceReference,
  }) {
    return SanmillOpeningSourceEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      family: family ?? this.family,
      aliases: aliases ?? this.aliases,
      side: side ?? this.side,
      favoredSide: favoredSide ?? this.favoredSide,
      confidence: confidence ?? this.confidence,
      tags: tags ?? this.tags,
      stats: stats ?? this.stats,
      line: line ?? this.line,
      commonBlunders: commonBlunders ?? this.commonBlunders,
      recommendedResponses: recommendedResponses ?? this.recommendedResponses,
      source: source ?? this.source,
      sourceReference: sourceReference ?? this.sourceReference,
    );
  }
}

class SanmillOpeningLine {
  const SanmillOpeningLine({
    required this.moves,
    this.comment = '',
    this.nags = const <String>[],
    this.variations = const <SanmillOpeningVariation>[],
  });

  factory SanmillOpeningLine.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningLine(
      moves: _stringList(json['moves']),
      comment: (json['comment'] ?? '') as String,
      nags: _stringList(json['nags']),
      variations: _variationList(json['variations']),
    );
  }

  final List<String> moves;
  final String comment;
  final List<String> nags;
  final List<SanmillOpeningVariation> variations;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'moves': moves,
    'comment': comment,
    'nags': nags,
    'variations': variations
        .map((SanmillOpeningVariation variation) => variation.toJson())
        .toList(growable: false),
  };

  SanmillOpeningLine copyWith({
    List<String>? moves,
    String? comment,
    List<String>? nags,
    List<SanmillOpeningVariation>? variations,
  }) {
    return SanmillOpeningLine(
      moves: moves ?? this.moves,
      comment: comment ?? this.comment,
      nags: nags ?? this.nags,
      variations: variations ?? this.variations,
    );
  }
}

class SanmillOpeningVariation {
  const SanmillOpeningVariation({
    required this.id,
    required this.name,
    required this.afterPly,
    required this.moves,
    this.comment = '',
    this.stats = const SanmillOpeningStats(),
    this.variations = const <SanmillOpeningVariation>[],
  });

  factory SanmillOpeningVariation.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningVariation(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      afterPly: (json['afterPly'] ?? 0) as int,
      moves: _stringList(json['moves']),
      comment: (json['comment'] ?? '') as String,
      stats: SanmillOpeningStats.fromJson(_jsonMap(json['stats'])),
      variations: _variationList(json['variations']),
    );
  }

  factory SanmillOpeningVariation.fromOpeningBranch(OpeningBranch branch) {
    return SanmillOpeningVariation(
      id: branch.branchId,
      name: branch.name,
      afterPly: (branch.deviationPly - 1).clamp(0, 18),
      moves: branch.lineContinuation.isEmpty
          ? <String>[branch.deviationMove]
          : branch.lineContinuation,
      comment: branch.strategicNotes,
      stats: SanmillOpeningStats.fromLegacyOutcomeStats(branch.outcomeStats),
    );
  }

  final String id;
  final String name;
  final int afterPly;
  final List<String> moves;
  final String comment;
  final SanmillOpeningStats stats;
  final List<SanmillOpeningVariation> variations;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'afterPly': afterPly,
    'moves': moves,
    'comment': comment,
    'stats': stats.toJson(),
    'variations': variations
        .map((SanmillOpeningVariation variation) => variation.toJson())
        .toList(growable: false),
  };

  OpeningBranch toOpeningBranch({required String source}) {
    assert(moves.isNotEmpty, 'Opening variation must contain moves.');
    final int deviationPly = afterPly + 1;
    return OpeningBranch(
      branchId: id,
      deviationPly: deviationPly,
      deviationMove: moves.first,
      name: name,
      lineContinuation: moves,
      strategicNotes: comment,
      source: source,
      outcomeStats: stats.toLegacyOutcomeStats(),
    );
  }

  SanmillOpeningVariation copyWith({
    String? id,
    String? name,
    int? afterPly,
    List<String>? moves,
    String? comment,
    SanmillOpeningStats? stats,
    List<SanmillOpeningVariation>? variations,
  }) {
    return SanmillOpeningVariation(
      id: id ?? this.id,
      name: name ?? this.name,
      afterPly: afterPly ?? this.afterPly,
      moves: moves ?? this.moves,
      comment: comment ?? this.comment,
      stats: stats ?? this.stats,
      variations: variations ?? this.variations,
    );
  }
}

class SanmillOpeningStats {
  const SanmillOpeningStats({
    this.whiteWins = 0,
    this.blackWins = 0,
    this.draws = 0,
    this.sampleSize = 0,
  });

  factory SanmillOpeningStats.fromJson(Map<String, dynamic> json) {
    return SanmillOpeningStats(
      whiteWins: _intValue(json['whiteWins']),
      blackWins: _intValue(json['blackWins']),
      draws: _intValue(json['draws']),
      sampleSize: _intValue(json['sampleSize']),
    );
  }

  factory SanmillOpeningStats.fromLegacyOutcomeStats(Map<String, int> stats) {
    final int whiteWins = stats['W'] ?? 0;
    final int blackWins = stats['B'] ?? 0;
    final int draws = stats['D'] ?? 0;
    return SanmillOpeningStats(
      whiteWins: whiteWins,
      blackWins: blackWins,
      draws: draws,
      sampleSize: whiteWins + blackWins + draws,
    );
  }

  final int whiteWins;
  final int blackWins;
  final int draws;
  final int sampleSize;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'whiteWins': whiteWins,
    'blackWins': blackWins,
    'draws': draws,
    'sampleSize': sampleSize,
  };

  Map<String, int> toLegacyOutcomeStats() => <String, int>{
    'W': whiteWins,
    'B': blackWins,
    'D': draws,
  };

  SanmillOpeningStats copyWith({
    int? whiteWins,
    int? blackWins,
    int? draws,
    int? sampleSize,
  }) {
    return SanmillOpeningStats(
      whiteWins: whiteWins ?? this.whiteWins,
      blackWins: blackWins ?? this.blackWins,
      draws: draws ?? this.draws,
      sampleSize: sampleSize ?? this.sampleSize,
    );
  }
}

class OpeningBookSourceValidationResult {
  const OpeningBookSourceValidationResult({
    required this.errors,
    required this.warnings,
  });

  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;
}

OpeningBookSourceValidationResult validateSanmillOpeningBookSource(
  SanmillOpeningBookSourcePackage package,
) {
  final List<String> errors = <String>[];
  final List<String> warnings = <String>[];
  if (package.format != sanmillOpeningBookSourceFormat) {
    errors.add('Unsupported format: ${package.format}');
  }
  if (package.schemaVersion != 1) {
    errors.add('Unsupported schema version: ${package.schemaVersion}');
  }
  if (package.game != 'mill') {
    errors.add('Unsupported game: ${package.game}');
  }
  if (package.variant != 'nmm') {
    errors.add('Opening Book Studio currently supports nmm only.');
  }
  if (package.openings.isEmpty) {
    warnings.add('No openings have been defined.');
  }

  final Set<String> ids = <String>{};
  for (int i = 0; i < package.openings.length; i++) {
    final SanmillOpeningSourceEntry opening = package.openings[i];
    final String label = opening.id.isEmpty ? '#${i + 1}' : opening.id;
    if (opening.id.trim().isEmpty) {
      errors.add('Opening #${i + 1} has no id.');
    } else if (!ids.add(opening.id)) {
      errors.add('Duplicate opening id: ${opening.id}');
    }
    if (opening.name.trim().isEmpty) {
      errors.add('Opening $label has no name.');
    }
    if (!_validSide(opening.side, allowBoth: true)) {
      errors.add('Opening $label has invalid side: ${opening.side}');
    }
    if (!_validFavoredSide(opening.favoredSide)) {
      errors.add(
        'Opening $label has invalid favoured side: ${opening.favoredSide}',
      );
    }
    if (opening.confidence < 0 || opening.confidence > 1) {
      errors.add('Opening $label confidence must be between 0 and 1.');
    }
    _validateMoveSequence(
      errors,
      opening.line.moves,
      label: 'Opening $label main line',
    );
    for (int j = 0; j < opening.line.variations.length; j++) {
      final SanmillOpeningVariation variation = opening.line.variations[j];
      _validateVariation(
        errors,
        opening.line.moves,
        variation,
        label: 'Opening $label variation #${j + 1}',
      );
    }
  }

  return OpeningBookSourceValidationResult(errors: errors, warnings: warnings);
}

void _validateMoveSequence(
  List<String> errors,
  List<String> moves, {
  required String label,
}) {
  if (moves.isEmpty) {
    errors.add('$label has no moves.');
    return;
  }
  if (moves.length > 18) {
    errors.add(
      '$label has ${moves.length} moves; placing lines cannot exceed 18.',
    );
  }
  final Set<String> seen = <String>{};
  for (final String move in moves) {
    if (!sanmillOpeningBookCoordinates.contains(move)) {
      errors.add('$label contains invalid coordinate: $move');
    }
    if (!seen.add(move)) {
      errors.add('$label places twice on $move.');
    }
  }
}

void _validateVariation(
  List<String> errors,
  List<String> mainLine,
  SanmillOpeningVariation variation, {
  required String label,
}) {
  if (variation.afterPly < 0 || variation.afterPly > mainLine.length) {
    errors.add('$label has invalid afterPly: ${variation.afterPly}.');
    return;
  }
  if (variation.moves.isEmpty) {
    errors.add('$label has no moves.');
    return;
  }
  final List<String> sequence = <String>[
    ...mainLine.take(variation.afterPly),
    ...variation.moves,
  ];
  _validateMoveSequence(errors, sequence, label: label);
}

bool _validSide(String value, {required bool allowBoth}) {
  return value == 'W' || value == 'B' || (allowBoth && value == 'both');
}

bool _validFavoredSide(String value) {
  return value == 'W' || value == 'B' || value == 'equal';
}

List<SanmillOpeningVariation> _variationList(Object? raw) {
  if (raw is! List) {
    return const <SanmillOpeningVariation>[];
  }
  return raw
      .whereType<Map<Object?, Object?>>()
      .map(
        (Map<Object?, Object?> value) =>
            SanmillOpeningVariation.fromJson(Map<String, dynamic>.from(value)),
      )
      .toList(growable: false);
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((Object? value) => value.toString())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is String) {
    return parseOpeningMoveList(raw);
  }
  return const <String>[];
}

Map<String, List<String>> _stringListMap(Object? raw) {
  final Map<String, List<String>> result = <String, List<String>>{};
  if (raw is Map<Object?, Object?>) {
    raw.forEach((Object? key, Object? value) {
      result[key.toString()] = _stringList(value);
    });
  }
  return result;
}

Map<String, dynamic> _jsonMap(Object? raw) {
  if (raw is Map<Object?, Object?>) {
    return Map<String, dynamic>.from(raw);
  }
  return const <String, dynamic>{};
}

Map<String, Object?> _objectMap(Object? raw) {
  if (raw is Map<Object?, Object?>) {
    return Map<String, Object?>.from(raw);
  }
  return const <String, Object?>{};
}

int _intValue(Object? raw) {
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw) ?? 0;
  }
  return 0;
}
