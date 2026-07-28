// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Merge generated Mill puzzle packages while removing positions equivalent
// under all 16 abstract board symmetries.
//
// Usage:
//   dart run tool/merge_puzzle_packs.dart \
//     --base assets/puzzles/malom_perfect_db_puzzles.sanmill_puzzles \
//     --out merged.sanmill_puzzles \
//     --version 1.2.0 \
//     --max-lines 8 \
//     --mark-composed \
//     --curriculum-order \
//     candidates-a.sanmill_puzzles candidates-b.sanmill_puzzles

import 'dart:convert';
import 'dart:io';

import 'package:sanmill/game_page/services/transform/transform.dart';

Never _fail(String message) {
  stderr.writeln('[puzzle-merge] ERROR: $message');
  exit(2);
}

Map<String, dynamic> _readPackage(String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on Object catch (error) {
    _fail('cannot read or decode $path: $error');
  }
  if (decoded is! Map<String, dynamic>) {
    _fail('$path must contain a JSON object');
  }
  if (decoded['puzzles'] is! List<dynamic>) {
    _fail('$path must contain a puzzles array');
  }
  return decoded;
}

String _canonicalFen(String fen) {
  String? canonical;
  for (final TransformationType type in TransformationType.values) {
    final String transformed = transformFEN(fen, type);
    if (canonical == null || transformed.compareTo(canonical) < 0) {
      canonical = transformed;
    }
  }
  return canonical!;
}

String _requiredString(
  Map<String, dynamic> object,
  String key,
  String context,
) {
  final Object? value = object[key];
  if (value is! String || value.isEmpty) {
    _fail('$context must contain a non-empty $key string');
  }
  return value;
}

void _markComposed(Map<String, dynamic> puzzle) {
  final String id = _requiredString(puzzle, 'id', 'puzzle');
  final Object? rawTags = puzzle['tags'];
  if (rawTags is! List<dynamic>) {
    _fail('$id must contain a tags array');
  }
  if (!rawTags.contains('source:composed')) {
    rawTags.add('source:composed');
  }

  const String label =
      'Composed position: rule-consistent and Perfect DB-certified; '
      'no legal replay witness is claimed.';
  final String description = _requiredString(puzzle, 'description', id);
  if (!description.contains(label)) {
    puzzle['description'] = '$description $label';
  }
}

const List<String> _topicOrder = <String>[
  'capture-choice',
  'quiet-move',
  'mill-block',
  'greedy-mill-trap',
  'wrong-mill-trap',
  'double-mill',
  'dual-threat',
  'mill-abandonment',
  'sacrifice',
  'immobilization',
  'flying-defence',
  'zugzwang',
  'calculation',
];

String _primaryTopic(List<dynamic> tags) {
  bool has(String tag) => tags.contains(tag);

  if (has('capture-choice')) {
    return 'capture-choice';
  }
  if (has('mill-block')) {
    return 'mill-block';
  }
  if (has('dual-threat')) {
    return 'dual-threat';
  }
  if (has('mill-abandonment')) {
    return 'mill-abandonment';
  }
  if (has('zugzwang')) {
    return 'zugzwang';
  }
  if (has('trap:greedy-mill')) {
    return 'greedy-mill-trap';
  }
  if (has('trap:wrong-mill')) {
    return 'wrong-mill-trap';
  }
  if (has('double-mill')) {
    return 'double-mill';
  }
  if (has('immobilization')) {
    return 'immobilization';
  }
  if (has('sacrifice')) {
    return 'sacrifice';
  }
  if (has('quiet-move')) {
    return 'quiet-move';
  }
  if (has('vs-flying')) {
    return 'flying-defence';
  }
  return 'calculation';
}

String _strandForTopic(String topic) {
  switch (topic) {
    case 'capture-choice':
    case 'quiet-move':
      return '01-foundations';
    case 'mill-block':
    case 'greedy-mill-trap':
    case 'wrong-mill-trap':
    case 'double-mill':
    case 'dual-threat':
      return '02-mill-tactics';
    case 'mill-abandonment':
    case 'sacrifice':
      return '03-positional-play';
    case 'immobilization':
    case 'flying-defence':
    case 'zugzwang':
      return '04-endgames';
    case 'calculation':
      return '05-calculation';
  }
  throw StateError('unhandled curriculum topic $topic');
}

int _difficultyRank(String difficulty) {
  switch (difficulty) {
    case 'beginner':
      return 1;
    case 'easy':
      return 2;
    case 'medium':
      return 3;
    case 'hard':
      return 4;
    case 'expert':
      return 5;
  }
  _fail('unknown puzzle difficulty $difficulty');
}

int _winDistance(List<dynamic> tags) {
  for (final Object? rawTag in tags) {
    if (rawTag is! String || !rawTag.startsWith('win-in-')) {
      continue;
    }
    return int.tryParse(rawTag.substring('win-in-'.length)) ?? 1 << 30;
  }
  return 1 << 30;
}

void _applyCurriculum(List<dynamic> puzzles) {
  for (final Object? rawPuzzle in puzzles) {
    final Map<String, dynamic> puzzle = rawPuzzle! as Map<String, dynamic>;
    final String id = _requiredString(puzzle, 'id', 'puzzle');
    final Object? rawTags = puzzle['tags'];
    if (rawTags is! List<dynamic>) {
      _fail('$id must contain a tags array');
    }
    rawTags.removeWhere(
      (dynamic tag) =>
          tag is String &&
          (tag.startsWith('topic:') ||
              tag.startsWith('curriculum:') ||
              tag.startsWith('progression:') ||
              tag.startsWith('distance-band:')),
    );
    final String topic = _primaryTopic(rawTags);
    final String strand = _strandForTopic(topic);
    final String difficulty = _requiredString(puzzle, 'difficulty', id);
    final int level = _difficultyRank(difficulty);
    final int winDistance = _winDistance(rawTags);
    final String distanceBand = switch (winDistance) {
      <= 7 => 'short',
      <= 15 => 'medium',
      _ => 'long',
    };
    rawTags
      ..add('topic:$topic')
      ..add('curriculum:$strand')
      ..add('progression:$level-$difficulty')
      ..add('distance-band:$distanceBand');
  }

  puzzles.sort((dynamic rawLeft, dynamic rawRight) {
    final Map<String, dynamic> left = rawLeft as Map<String, dynamic>;
    final Map<String, dynamic> right = rawRight as Map<String, dynamic>;
    final List<dynamic> leftTags = left['tags']! as List<dynamic>;
    final List<dynamic> rightTags = right['tags']! as List<dynamic>;
    final String leftTopic = _primaryTopic(leftTags);
    final String rightTopic = _primaryTopic(rightTags);
    final int topicComparison = _topicOrder
        .indexOf(leftTopic)
        .compareTo(_topicOrder.indexOf(rightTopic));
    if (topicComparison != 0) {
      return topicComparison;
    }
    final int difficultyComparison = _difficultyRank(
      left['difficulty']! as String,
    ).compareTo(_difficultyRank(right['difficulty']! as String));
    if (difficultyComparison != 0) {
      return difficultyComparison;
    }
    final int winComparison = _winDistance(
      leftTags,
    ).compareTo(_winDistance(rightTags));
    if (winComparison != 0) {
      return winComparison;
    }
    final int ratingComparison = (left['rating'] as int? ?? 1 << 30).compareTo(
      right['rating'] as int? ?? 1 << 30,
    );
    if (ratingComparison != 0) {
      return ratingComparison;
    }
    return _requiredString(
      left,
      'id',
      'puzzle',
    ).compareTo(_requiredString(right, 'id', 'puzzle'));
  });
}

void main(List<String> arguments) {
  String? basePath;
  String? outputPath;
  String? version;
  int maxLines = 8;
  bool markComposed = false;
  bool curriculumOrder = false;
  final List<String> inputPaths = <String>[];

  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    String optionValue(String name) {
      if (index + 1 >= arguments.length) {
        _fail('$name requires a value');
      }
      return arguments[++index];
    }

    switch (argument) {
      case '--base':
        basePath = optionValue('--base');
      case '--out':
        outputPath = optionValue('--out');
      case '--version':
        version = optionValue('--version');
      case '--max-lines':
        final String raw = optionValue('--max-lines');
        maxLines = int.tryParse(raw) ?? _fail('--max-lines must be an integer');
        if (maxLines < 1) {
          _fail('--max-lines must be positive');
        }
      case '--mark-composed':
        markComposed = true;
      case '--curriculum-order':
        curriculumOrder = true;
      default:
        if (argument.startsWith('--')) {
          _fail('unknown option $argument');
        }
        inputPaths.add(argument);
    }
  }

  if (basePath == null || outputPath == null) {
    _fail('--base and --out are required');
  }
  if (inputPaths.isEmpty) {
    _fail('at least one candidate package is required');
  }

  final Map<String, dynamic> base = _readPackage(basePath);
  final List<dynamic> basePuzzles = base['puzzles']! as List<dynamic>;
  final Map<String, dynamic>? metadata =
      base['metadata'] as Map<String, dynamic>?;
  final String? baseVariant = metadata?['ruleVariantId'] as String?;

  final Set<String> seenIds = <String>{};
  final Set<String> seenPositions = <String>{};
  for (final Object? rawPuzzle in basePuzzles) {
    if (rawPuzzle is! Map<String, dynamic>) {
      _fail('$basePath contains a non-object puzzle');
    }
    final String id = _requiredString(rawPuzzle, 'id', basePath);
    final String fen = _requiredString(rawPuzzle, 'initialPosition', id);
    if (!seenIds.add(id)) {
      _fail('$basePath contains duplicate puzzle id $id');
    }
    if (!seenPositions.add(_canonicalFen(fen))) {
      _fail('$basePath contains symmetry-equivalent puzzle position $id');
    }
  }

  final List<dynamic> additions = <dynamic>[];
  int skippedById = 0;
  int skippedBySymmetry = 0;
  String latestExportDate = base['exportDate'] as String? ?? '';
  final Set<String> candidateMetadataTags = <String>{};

  for (final String inputPath in inputPaths) {
    final Map<String, dynamic> candidatePackage = _readPackage(inputPath);
    final Object? rawCandidateMetadata = candidatePackage['metadata'];
    if (rawCandidateMetadata is Map<String, dynamic>) {
      final Object? rawTags = rawCandidateMetadata['tags'];
      if (rawTags is List<dynamic>) {
        candidateMetadataTags.addAll(rawTags.whereType<String>());
      }
    }
    final String candidateExportDate =
        candidatePackage['exportDate'] as String? ?? '';
    if (candidateExportDate.compareTo(latestExportDate) > 0) {
      latestExportDate = candidateExportDate;
    }

    for (final Object? rawPuzzle
        in candidatePackage['puzzles']! as List<dynamic>) {
      if (rawPuzzle is! Map<String, dynamic>) {
        _fail('$inputPath contains a non-object puzzle');
      }
      final String id = _requiredString(rawPuzzle, 'id', inputPath);
      final String fen = _requiredString(rawPuzzle, 'initialPosition', id);
      final String variant = _requiredString(rawPuzzle, 'ruleVariantId', id);
      if (baseVariant != null && variant != baseVariant) {
        _fail('$id uses $variant but the base package uses $baseVariant');
      }
      final Object? rawSolutions = rawPuzzle['solutions'];
      if (rawSolutions is! List<dynamic> || rawSolutions.isEmpty) {
        _fail('$id must contain at least one solution');
      }
      if (rawSolutions.length > maxLines) {
        _fail(
          '$id contains ${rawSolutions.length} solutions, exceeding '
          '--max-lines $maxLines',
        );
      }

      if (!seenIds.add(id)) {
        skippedById++;
        continue;
      }
      if (!seenPositions.add(_canonicalFen(fen))) {
        seenIds.remove(id);
        skippedBySymmetry++;
        continue;
      }
      additions.add(rawPuzzle);
    }
  }

  final List<dynamic> mergedPuzzles = <dynamic>[...basePuzzles, ...additions];
  if (markComposed) {
    for (final Object? rawPuzzle in mergedPuzzles) {
      _markComposed(rawPuzzle! as Map<String, dynamic>);
    }
    if (metadata != null) {
      metadata['description'] =
          'Forced-win composed positions generated offline from the Malom '
          'perfect-play database. Complete logical turns are certified, the '
          'attacker minimises the win distance, and a losing defender delays '
          'defeat. No legal replay witness is claimed.';
    }
  }
  if (curriculumOrder) {
    _applyCurriculum(mergedPuzzles);
    if (metadata != null) {
      metadata['description'] =
          'Perfect DB-certified composed and replay-backed puzzles organised '
          'as a progressive curriculum: foundations, mill tactics, '
          'positional play and endgames. Constraint-directed additions use '
          'Z3 for discovery and CP-SAT for editorial balance; anonymised '
          'HumanDB replays supply real-game missed wins, and Perfect DB '
          'remains the proof source.';
    }
  }
  base['exportDate'] = latestExportDate;
  base['puzzleCount'] = mergedPuzzles.length;
  base['puzzles'] = mergedPuzzles;
  if (version != null) {
    if (metadata == null) {
      _fail('--version requires metadata in the base package');
    }
    metadata['version'] = version;
  }
  if (metadata != null) {
    final Object? rawTags = metadata['tags'];
    if (rawTags is! List<dynamic>) {
      _fail('base metadata must contain a tags array');
    }
    final Set<String> mergedTags = <String>{
      ...rawTags.whereType<String>(),
      ...candidateMetadataTags,
      if (curriculumOrder) 'curriculum',
    };
    metadata['tags'] = mergedTags.toList()..sort();
  }

  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  File(outputPath).writeAsStringSync(encoder.convert(base));
  stdout.writeln(
    '[puzzle-merge] base=${basePuzzles.length} added=${additions.length} '
    'skipped-id=$skippedById skipped-symmetry=$skippedBySymmetry '
    'total=${mergedPuzzles.length} out=$outputPath',
  );
}
