// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../rule_settings/models/rule_settings.dart';

const int reviewSchemaVersion = 1;
const String reviewEngineVersion = 'tgf-review-v1';

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String canonicalRuleSettingsJson(RuleSettings settings) {
  final SplayTreeMap<String, dynamic> sorted = SplayTreeMap<String, dynamic>()
    ..addAll(settings.toJson());
  return jsonEncode(sorted);
}

String ruleSettingsFingerprint(RuleSettings settings) =>
    _sha256Text(canonicalRuleSettingsJson(settings));

String _movetextForIdentity(String pgn) => pgn
    .split(RegExp(r'\r?\n'))
    .where((String line) => !line.trimLeft().startsWith('['))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String pgnFingerprint(String pgn) {
  final String initialFen =
      RegExp(
        r'^\s*\[FEN\s+"([^"]*)"\]',
        multiLine: true,
      ).firstMatch(pgn)?.group(1) ??
      '';
  return _sha256Text('$initialFen\n${_movetextForIdentity(pgn)}');
}

enum ReviewSide { white, black }

enum ReviewProfile {
  quick(depth: 24, moveLimitMs: 200),
  deep(depth: 64, moveLimitMs: 6000);

  const ReviewProfile({required this.depth, required this.moveLimitMs});

  final int depth;
  final int moveLimitMs;
}

enum ReviewGrade { best, good, dubious, mistake, blunder }

enum ReviewWdlBand { loss, draw, win }

enum ReviewStatus { complete, cancelled }

@immutable
class PrivateGameRecord {
  const PrivateGameRecord({
    required this.id,
    required this.sourcePgn,
    required this.initialFen,
    required this.result,
    required this.rules,
    required this.completedAt,
    required this.white,
    required this.black,
    required this.humanSides,
    required this.finalBoardLayout,
    required this.moveCount,
    this.version = reviewSchemaVersion,
  });

  factory PrivateGameRecord.create({
    required String sourcePgn,
    required String? initialFen,
    required String result,
    required RuleSettings rules,
    required DateTime completedAt,
    required String white,
    required String black,
    required Set<ReviewSide> humanSides,
    required String? finalBoardLayout,
    required int moveCount,
  }) {
    final String normalizedFen = initialFen?.trim() ?? '';
    final String id = _sha256Text(
      '${_movetextForIdentity(sourcePgn)}\n$normalizedFen\n$result\n'
      '${canonicalRuleSettingsJson(rules)}',
    );
    return PrivateGameRecord(
      id: id,
      sourcePgn: sourcePgn,
      initialFen: normalizedFen,
      result: result,
      rules: rules,
      completedAt: completedAt,
      white: white,
      black: black,
      humanSides: Set<ReviewSide>.unmodifiable(humanSides),
      finalBoardLayout: finalBoardLayout,
      moveCount: moveCount,
    );
  }

  factory PrivateGameRecord.fromJson(Map<dynamic, dynamic> json) {
    final Map<String, dynamic> rulesJson = Map<String, dynamic>.from(
      json['rules']! as Map<dynamic, dynamic>,
    );
    return PrivateGameRecord(
      version: json['version']! as int,
      id: json['id']! as String,
      sourcePgn: json['sourcePgn']! as String,
      initialFen: json['initialFen']! as String,
      result: json['result']! as String,
      rules: RuleSettings.fromJson(rulesJson),
      completedAt: DateTime.parse(json['completedAt']! as String),
      white: json['white']! as String,
      black: json['black']! as String,
      humanSides: (json['humanSides']! as List<dynamic>)
          .map((dynamic value) => ReviewSide.values.byName(value! as String))
          .toSet(),
      finalBoardLayout: json['finalBoardLayout'] as String?,
      moveCount: json['moveCount']! as int,
    );
  }

  final int version;
  final String id;
  final String sourcePgn;
  final String initialFen;
  final String result;
  final RuleSettings rules;
  final DateTime completedAt;
  final String white;
  final String black;
  final Set<ReviewSide> humanSides;
  final String? finalBoardLayout;
  final int moveCount;

  String get rulesFingerprint => ruleSettingsFingerprint(rules);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'id': id,
    'sourcePgn': sourcePgn,
    'initialFen': initialFen,
    'result': result,
    'rules': rules.toJson(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'white': white,
    'black': black,
    'humanSides': humanSides.map((ReviewSide side) => side.name).toList(),
    'finalBoardLayout': finalBoardLayout,
    'moveCount': moveCount,
  };
}

@immutable
class ReviewCandidate {
  const ReviewCandidate({
    required this.rank,
    required this.move,
    required this.score,
    required this.depth,
    required this.line,
  });

  factory ReviewCandidate.fromJson(Map<dynamic, dynamic> json) {
    return ReviewCandidate(
      rank: json['rank']! as int,
      move: json['move']! as String,
      score: json['score']! as int,
      depth: json['depth']! as int,
      line: List<String>.from(json['line']! as List<dynamic>),
    );
  }

  final int rank;
  final String move;
  final int score;
  final int depth;
  final List<String> line;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rank': rank,
    'move': move,
    'score': score,
    'depth': depth,
    'line': line,
  };
}

@immutable
class ReviewActionEvaluation {
  const ReviewActionEvaluation({
    required this.atomicIndex,
    required this.groupIndex,
    required this.move,
    required this.side,
    required this.isHumanMove,
    required this.legalRootActionCount,
    required this.bestScore,
    required this.playedScore,
    required this.loss,
    required this.grade,
    required this.profile,
    required this.candidates,
  });

  factory ReviewActionEvaluation.fromJson(Map<dynamic, dynamic> json) {
    return ReviewActionEvaluation(
      atomicIndex: json['atomicIndex']! as int,
      groupIndex: json['groupIndex']! as int,
      move: json['move']! as String,
      side: ReviewSide.values.byName(json['side']! as String),
      isHumanMove: json['isHumanMove']! as bool,
      legalRootActionCount: json['legalRootActionCount']! as int,
      bestScore: json['bestScore']! as int,
      playedScore: json['playedScore']! as int,
      loss: json['loss']! as int,
      grade: ReviewGrade.values.byName(json['grade']! as String),
      profile: ReviewProfile.values.byName(json['profile']! as String),
      candidates: (json['candidates']! as List<dynamic>)
          .map(
            (dynamic value) =>
                ReviewCandidate.fromJson(value! as Map<dynamic, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final int atomicIndex;
  final int groupIndex;
  final String move;
  final ReviewSide side;
  final bool isHumanMove;
  final int legalRootActionCount;
  final int bestScore;
  final int playedScore;
  final int loss;
  final ReviewGrade grade;
  final ReviewProfile profile;
  final List<ReviewCandidate> candidates;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'atomicIndex': atomicIndex,
    'groupIndex': groupIndex,
    'move': move,
    'side': side.name,
    'isHumanMove': isHumanMove,
    'legalRootActionCount': legalRootActionCount,
    'bestScore': bestScore,
    'playedScore': playedScore,
    'loss': loss,
    'grade': grade.name,
    'profile': profile.name,
    'candidates': candidates
        .map((ReviewCandidate candidate) => candidate.toJson())
        .toList(),
  };
}

@immutable
class ReviewTurnBoundary {
  const ReviewTurnBoundary({
    required this.groupIndex,
    required this.startAtomicIndex,
    required this.endAtomicIndex,
    required this.san,
    required this.anchorMove,
    required this.side,
    required this.sourceNags,
    required this.boardLayout,
  });

  factory ReviewTurnBoundary.fromJson(Map<dynamic, dynamic> json) {
    return ReviewTurnBoundary(
      groupIndex: json['groupIndex']! as int,
      startAtomicIndex: json['startAtomicIndex']! as int,
      endAtomicIndex: json['endAtomicIndex']! as int,
      san: json['san']! as String,
      anchorMove: json['anchorMove']! as String,
      side: ReviewSide.values.byName(json['side']! as String),
      sourceNags: List<int>.from(json['sourceNags']! as List<dynamic>),
      boardLayout: json['boardLayout']! as String,
    );
  }

  final int groupIndex;
  final int startAtomicIndex;
  final int endAtomicIndex;
  final String san;
  final String anchorMove;
  final ReviewSide side;
  final List<int> sourceNags;
  final String boardLayout;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'groupIndex': groupIndex,
    'startAtomicIndex': startAtomicIndex,
    'endAtomicIndex': endAtomicIndex,
    'san': san,
    'anchorMove': anchorMove,
    'side': side.name,
    'sourceNags': sourceNags,
    'boardLayout': boardLayout,
  };
}

@immutable
class ReviewReport {
  const ReviewReport({
    required this.recordId,
    required this.pgnHash,
    required this.rulesHash,
    required this.engineVersion,
    required this.profile,
    required this.status,
    required this.actions,
    required this.turns,
    required this.variationCount,
    required this.userNagOverrides,
    required this.includeAnnotationsOnExport,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAccessedAt,
    this.version = reviewSchemaVersion,
  });

  factory ReviewReport.fromJson(Map<dynamic, dynamic> json) {
    final Map<int, int?> overrides = <int, int?>{};
    (json['userNagOverrides']! as Map<dynamic, dynamic>).forEach((
      dynamic key,
      dynamic value,
    ) {
      overrides[int.parse(key! as String)] = value as int?;
    });
    return ReviewReport(
      version: json['version']! as int,
      recordId: json['recordId']! as String,
      pgnHash: json['pgnHash']! as String,
      rulesHash: json['rulesHash']! as String,
      engineVersion: json['engineVersion']! as String,
      profile: ReviewProfile.values.byName(json['profile']! as String),
      status: ReviewStatus.values.byName(json['status']! as String),
      actions: (json['actions']! as List<dynamic>)
          .map(
            (dynamic value) => ReviewActionEvaluation.fromJson(
              value! as Map<dynamic, dynamic>,
            ),
          )
          .toList(growable: false),
      turns: (json['turns']! as List<dynamic>)
          .map(
            (dynamic value) =>
                ReviewTurnBoundary.fromJson(value! as Map<dynamic, dynamic>),
          )
          .toList(growable: false),
      variationCount: json['variationCount']! as int,
      userNagOverrides: overrides,
      includeAnnotationsOnExport: json['includeAnnotationsOnExport']! as bool,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      lastAccessedAt: DateTime.parse(json['lastAccessedAt']! as String),
    );
  }

  final int version;
  final String recordId;
  final String pgnHash;
  final String rulesHash;
  final String engineVersion;
  final ReviewProfile profile;
  final ReviewStatus status;
  final List<ReviewActionEvaluation> actions;
  final List<ReviewTurnBoundary> turns;
  final int variationCount;

  /// A present key with a null value means the user explicitly cleared the
  /// quality annotation for that grouped turn.
  final Map<int, int?> userNagOverrides;
  final bool includeAnnotationsOnExport;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastAccessedAt;

  String get cacheKey => ReviewReport.cacheKeyFor(
    pgnHash: pgnHash,
    rulesHash: rulesHash,
    engineVersion: engineVersion,
    profile: profile,
  );

  static String cacheKeyFor({
    required String pgnHash,
    required String rulesHash,
    required String engineVersion,
    required ReviewProfile profile,
  }) => _sha256Text('$pgnHash|$rulesHash|$engineVersion|${profile.name}');

  Iterable<ReviewActionEvaluation> get humanMistakes => actions.where(
    (ReviewActionEvaluation action) =>
        action.isHumanMove &&
        (action.grade == ReviewGrade.dubious ||
            action.grade == ReviewGrade.mistake ||
            action.grade == ReviewGrade.blunder),
  );

  ReviewGrade gradeForTurn(int groupIndex) {
    final Iterable<ReviewActionEvaluation> grouped = actions.where(
      (ReviewActionEvaluation action) => action.groupIndex == groupIndex,
    );
    assert(grouped.isNotEmpty, 'Every review turn must contain an action.');
    return grouped
        .map((ReviewActionEvaluation action) => action.grade)
        .reduce((ReviewGrade a, ReviewGrade b) => a.index >= b.index ? a : b);
  }

  int? effectiveQualityNagForTurn(int groupIndex) {
    if (userNagOverrides.containsKey(groupIndex)) {
      return userNagOverrides[groupIndex];
    }
    final ReviewTurnBoundary turn = turns.firstWhere(
      (ReviewTurnBoundary value) => value.groupIndex == groupIndex,
    );
    for (final int nag in turn.sourceNags) {
      if (nag >= 1 && nag <= 6) {
        return nag;
      }
    }
    return automaticNagForGrade(gradeForTurn(groupIndex));
  }

  ReviewReport copyWith({
    ReviewStatus? status,
    List<ReviewActionEvaluation>? actions,
    List<ReviewTurnBoundary>? turns,
    Map<int, int?>? userNagOverrides,
    bool? includeAnnotationsOnExport,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
  }) {
    return ReviewReport(
      version: version,
      recordId: recordId,
      pgnHash: pgnHash,
      rulesHash: rulesHash,
      engineVersion: engineVersion,
      profile: profile,
      status: status ?? this.status,
      actions: actions ?? this.actions,
      turns: turns ?? this.turns,
      variationCount: variationCount,
      userNagOverrides: userNagOverrides ?? this.userNagOverrides,
      includeAnnotationsOnExport:
          includeAnnotationsOnExport ?? this.includeAnnotationsOnExport,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'recordId': recordId,
    'pgnHash': pgnHash,
    'rulesHash': rulesHash,
    'engineVersion': engineVersion,
    'profile': profile.name,
    'status': status.name,
    'actions': actions
        .map((ReviewActionEvaluation action) => action.toJson())
        .toList(),
    'turns': turns.map((ReviewTurnBoundary turn) => turn.toJson()).toList(),
    'variationCount': variationCount,
    'userNagOverrides': userNagOverrides.map(
      (int key, int? value) => MapEntry<String, int?>('$key', value),
    ),
    'includeAnnotationsOnExport': includeAnnotationsOnExport,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastAccessedAt': lastAccessedAt.toUtc().toIso8601String(),
  };
}

int? automaticNagForGrade(ReviewGrade grade) => switch (grade) {
  ReviewGrade.dubious => 6,
  ReviewGrade.mistake => 2,
  ReviewGrade.blunder => 4,
  ReviewGrade.best || ReviewGrade.good => null,
};

abstract final class ReviewGrading {
  static const int _terminalWinScore = 80;

  static ReviewWdlBand wdlBand(int score) {
    if (score >= _terminalWinScore) {
      return ReviewWdlBand.win;
    }
    if (score <= -_terminalWinScore) {
      return ReviewWdlBand.loss;
    }
    return ReviewWdlBand.draw;
  }

  static ReviewGrade grade({required int bestScore, required int playedScore}) {
    final int difference = bestScore - playedScore;
    final int loss = difference > 0 ? difference : 0;
    if (wdlBand(playedScore).index < wdlBand(bestScore).index) {
      return ReviewGrade.blunder;
    }
    if (loss <= 1) {
      return ReviewGrade.best;
    }
    if (loss <= 3) {
      return ReviewGrade.good;
    }
    if (loss <= 7) {
      return ReviewGrade.dubious;
    }
    if (loss <= 14) {
      return ReviewGrade.mistake;
    }
    return ReviewGrade.blunder;
  }
}
