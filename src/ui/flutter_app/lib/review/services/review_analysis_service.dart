// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_page/services/import_export/pgn.dart';
import '../../game_platform/game_session.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../general_settings/models/general_settings.dart';
import '../../shared/database/database.dart';
import '../../src/rust/api/simple.dart' as tgf;
import '../models/review_models.dart';
import 'review_storage.dart';

class ReviewCapacityException implements Exception {
  const ReviewCapacityException(this.legalActionCount, this.capacity);

  final int legalActionCount;
  final int capacity;

  @override
  String toString() =>
      'Unsupported review position: $legalActionCount legal root actions '
      'exceed search capacity $capacity.';
}

class ReviewMoveException implements Exception {
  const ReviewMoveException(this.move);

  final String move;

  @override
  String toString() => 'Review move is not legal under the record rules: $move';
}

class ReviewAnalysisService {
  ReviewAnalysisService({this._storage = ReviewStorage.instance});

  final ReviewStorage _storage;
  int _generation = 0;
  bool _searching = false;

  Future<ReviewReport> analyze(
    PrivateGameRecord record, {
    ReviewProfile profile = ReviewProfile.quick,
    void Function(int completed, int total)? onProgress,
    bool ignoreCache = false,
  }) async {
    final int generation = ++_generation;
    final String engineVersion = _engineCacheVersion();
    if (!ignoreCache) {
      final ReviewReport? cached = _storage.reportFor(
        record,
        profile: profile,
        engineVersion: engineVersion,
      );
      if (cached != null) {
        return _storage.touchReport(cached);
      }
    }

    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(record.sourcePgn);
    final List<PgnNodeData> groupedMoves = game.moves.mainline().toList();
    final int totalActions = groupedMoves.fold<int>(
      0,
      (int total, PgnNodeData move) => total + splitMillSan(move.san).length,
    );
    final int capacity = tgf.nativeMillSearchActionCapacity();
    final NativeMillGameSession session = NativeMillGameSession(
      rules: record.rules,
      generalSettings: _engineSettings(),
    );
    final String setupFen = game.headers['FEN']?.trim() ?? record.initialFen;
    if (setupFen.isNotEmpty) {
      final bool loaded = session.loadFen(setupFen);
      if (!loaded) {
        session.dispose();
        throw StateError('Review record carries an invalid initial FEN.');
      }
    }

    final List<ReviewActionEvaluation> actions = <ReviewActionEvaluation>[];
    final List<ReviewTurnBoundary> turns = <ReviewTurnBoundary>[];
    int atomicIndex = 0;
    try {
      for (int groupIndex = 0; groupIndex < groupedMoves.length; groupIndex++) {
        if (generation != _generation) {
          return _cancelledReport(
            record: record,
            profile: profile,
            actions: actions,
            turns: turns,
            variationCount: _variationCount(game.moves),
            engineVersion: engineVersion,
          );
        }
        final PgnNodeData groupedMove = groupedMoves[groupIndex];
        final List<String> segments = splitMillSan(groupedMove.san);
        if (segments.isEmpty) {
          continue;
        }
        final int startAtomicIndex = atomicIndex;
        final ReviewSide turnSide = _reviewSide(session.state.value.activeSeat);

        for (final String move in segments) {
          final ReviewActionEvaluation evaluation = await _evaluateCurrentMove(
            session: session,
            record: record,
            move: move,
            atomicIndex: atomicIndex,
            groupIndex: groupIndex,
            capacity: capacity,
            profile: profile,
          );
          actions.add(evaluation);
          atomicIndex++;
          onProgress?.call(atomicIndex, totalActions);
          if (generation != _generation) {
            return _cancelledReport(
              record: record,
              profile: profile,
              actions: actions,
              turns: turns,
              variationCount: _variationCount(game.moves),
              engineVersion: engineVersion,
            );
          }
        }

        turns.add(
          ReviewTurnBoundary(
            groupIndex: groupIndex,
            startAtomicIndex: startAtomicIndex,
            endAtomicIndex: atomicIndex - 1,
            san: groupedMove.san,
            anchorMove: segments.first,
            side: turnSide,
            sourceNags: List<int>.unmodifiable(
              groupedMove.nags ?? const <int>[],
            ),
            boardLayout: _boardLayout(session.getFen()),
          ),
        );
      }
    } on Object {
      if (generation != _generation) {
        return _cancelledReport(
          record: record,
          profile: profile,
          actions: actions,
          turns: turns,
          variationCount: _variationCount(game.moves),
          engineVersion: engineVersion,
        );
      }
      rethrow;
    } finally {
      session.dispose();
      _searching = false;
    }

    final DateTime now = DateTime.now().toUtc();
    final ReviewReport? previous = _storage.latestReportForRecord(record.id);
    final ReviewReport report = ReviewReport(
      recordId: record.id,
      pgnHash: pgnFingerprint(record.sourcePgn),
      rulesHash: record.rulesFingerprint,
      engineVersion: engineVersion,
      profile: profile,
      status: ReviewStatus.complete,
      actions: List<ReviewActionEvaluation>.unmodifiable(actions),
      turns: List<ReviewTurnBoundary>.unmodifiable(turns),
      variationCount: _variationCount(game.moves),
      userNagOverrides: previous?.userNagOverrides ?? const <int, int?>{},
      includeAnnotationsOnExport: previous?.includeAnnotationsOnExport ?? false,
      createdAt: now,
      updatedAt: now,
      lastAccessedAt: now,
    );
    await _storage.saveReport(report);
    return report;
  }

  Future<ReviewReport> deepenTurn(
    PrivateGameRecord record,
    ReviewReport report,
    int groupIndex,
  ) async {
    assert(report.status == ReviewStatus.complete);
    final int generation = ++_generation;
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(record.sourcePgn);
    final List<PgnNodeData> groups = game.moves.mainline().toList();
    assert(groupIndex >= 0 && groupIndex < groups.length);
    final int capacity = tgf.nativeMillSearchActionCapacity();
    final NativeMillGameSession session = NativeMillGameSession(
      rules: record.rules,
      generalSettings: _engineSettings(),
    );
    final String setupFen = game.headers['FEN']?.trim() ?? record.initialFen;
    if (setupFen.isNotEmpty && !session.loadFen(setupFen)) {
      session.dispose();
      throw StateError('Review record carries an invalid initial FEN.');
    }

    int atomicIndex = 0;
    final List<ReviewActionEvaluation> replacements =
        <ReviewActionEvaluation>[];
    try {
      for (int currentGroup = 0; currentGroup <= groupIndex; currentGroup++) {
        for (final String move in splitMillSan(groups[currentGroup].san)) {
          if (currentGroup == groupIndex) {
            replacements.add(
              await _evaluateCurrentMove(
                session: session,
                record: record,
                move: move,
                atomicIndex: atomicIndex,
                groupIndex: groupIndex,
                capacity: capacity,
                profile: ReviewProfile.deep,
              ),
            );
          } else {
            _applyMove(session, move);
          }
          atomicIndex++;
        }
      }
    } on Object {
      if (generation != _generation) {
        return _cancelledDeepReport(report);
      }
      rethrow;
    } finally {
      session.dispose();
      _searching = false;
    }

    if (generation != _generation) {
      return _cancelledDeepReport(report);
    }

    final List<ReviewActionEvaluation> merged = report.actions
        .map((ReviewActionEvaluation action) {
          if (action.groupIndex != groupIndex) {
            return action;
          }
          return replacements.firstWhere(
            (ReviewActionEvaluation replacement) =>
                replacement.atomicIndex == action.atomicIndex,
          );
        })
        .toList(growable: false);
    final DateTime now = DateTime.now().toUtc();
    final ReviewReport updated = report.copyWith(
      actions: merged,
      updatedAt: now,
      lastAccessedAt: now,
    );
    await _storage.saveReport(updated);
    return updated;
  }

  void cancel() {
    _generation++;
    if (_searching) {
      tgf.nativeMillSearchStop();
    }
  }

  Future<ReviewActionEvaluation> _evaluateCurrentMove({
    required NativeMillGameSession session,
    required PrivateGameRecord record,
    required String move,
    required int atomicIndex,
    required int groupIndex,
    required int capacity,
    required ReviewProfile profile,
  }) async {
    final List<GameAction> legalActions = session.legalActions;
    if (legalActions.length > capacity) {
      throw ReviewCapacityException(legalActions.length, capacity);
    }
    if (legalActions.isEmpty) {
      throw ReviewMoveException(move);
    }
    final ReviewSide side = _reviewSide(session.state.value.activeSeat);
    _searching = true;
    final List<NativeMillPrincipalVariation> variations = await session
        .searchPrincipalVariations(
          depth: profile.depth,
          moveLimitMs: profile.moveLimitMs,
          multiPv: legalActions.length,
          engineSettings: _engineSettings(),
        );
    _searching = false;
    if (variations.isEmpty) {
      throw StateError('The review engine returned no candidate moves.');
    }
    final NativeMillPrincipalVariation played = variations.firstWhere(
      (NativeMillPrincipalVariation variation) => variation.move == move,
      orElse: () => throw ReviewMoveException(move),
    );
    final int perspective = side == ReviewSide.white ? 1 : -1;
    final int bestScore = variations.first.score * perspective;
    final int playedScore = played.score * perspective;
    final int loss = bestScore > playedScore ? bestScore - playedScore : 0;
    final ReviewGrade grade = ReviewGrading.grade(
      bestScore: bestScore,
      playedScore: playedScore,
    );
    final List<ReviewCandidate> candidates = variations
        .map(
          (NativeMillPrincipalVariation variation) => ReviewCandidate(
            rank: variation.rank,
            move: variation.move,
            score: variation.score * perspective,
            depth: variation.depth,
            line: List<String>.unmodifiable(variation.line),
          ),
        )
        .toList(growable: false);
    _applyMove(session, move);
    return ReviewActionEvaluation(
      atomicIndex: atomicIndex,
      groupIndex: groupIndex,
      move: move,
      side: side,
      isHumanMove: record.humanSides.contains(side),
      legalRootActionCount: legalActions.length,
      bestScore: bestScore,
      playedScore: playedScore,
      loss: loss,
      grade: grade,
      profile: profile,
      candidates: candidates,
    );
  }

  static void _applyMove(NativeMillGameSession session, String move) {
    GameAction? action;
    for (final GameAction candidate in session.legalActions) {
      if (MillActionCodec.moveStringFrom(candidate) == move) {
        action = candidate;
        break;
      }
    }
    if (action == null) {
      throw ReviewMoveException(move);
    }
    final bool applied = session.applyMoveString(move);
    if (!applied) {
      throw ReviewMoveException(move);
    }
  }

  static GeneralSettings _engineSettings() {
    return DB().generalSettings.copyWith(
      searchAlgorithm: SearchAlgorithm.pvs,
      aiIsLazy: false,
      skillLevel: 30,
      resignIfMostLose: false,
      shufflingEnabled: false,
      useLazySmp: false,
      engineThreads: 1,
    );
  }

  static String _engineCacheVersion() =>
      '$reviewEngineVersion:${tgf.tgfVersion()}';

  static ReviewSide _reviewSide(PlayerSeat seat) => switch (seat) {
    PlayerSeat.first => ReviewSide.white,
    PlayerSeat.second => ReviewSide.black,
    PlayerSeat.none => throw StateError('Review position has no active side.'),
  };

  static String _boardLayout(String fen) {
    final String board = fen.trim().split(RegExp(r'\s+')).first;
    if (board.length != 26) {
      throw StateError('Review engine returned an invalid Mill FEN.');
    }
    return board;
  }

  static int _variationCount(PgnNode<PgnNodeData> root) {
    int count = root.children.length > 1 ? root.children.length - 1 : 0;
    for (final PgnNode<PgnNodeData> child in root.children) {
      count += _variationCount(child);
    }
    return count;
  }

  static ReviewReport _cancelledReport({
    required PrivateGameRecord record,
    required ReviewProfile profile,
    required List<ReviewActionEvaluation> actions,
    required List<ReviewTurnBoundary> turns,
    required int variationCount,
    required String engineVersion,
  }) {
    final DateTime now = DateTime.now().toUtc();
    return ReviewReport(
      recordId: record.id,
      pgnHash: pgnFingerprint(record.sourcePgn),
      rulesHash: record.rulesFingerprint,
      engineVersion: engineVersion,
      profile: profile,
      status: ReviewStatus.cancelled,
      actions: List<ReviewActionEvaluation>.unmodifiable(actions),
      turns: List<ReviewTurnBoundary>.unmodifiable(turns),
      variationCount: variationCount,
      userNagOverrides: const <int, int?>{},
      includeAnnotationsOnExport: false,
      createdAt: now,
      updatedAt: now,
      lastAccessedAt: now,
    );
  }

  static ReviewReport _cancelledDeepReport(ReviewReport report) {
    final DateTime now = DateTime.now().toUtc();
    return report.copyWith(
      status: ReviewStatus.cancelled,
      updatedAt: now,
      lastAccessedAt: now,
    );
  }
}

List<String> splitMillSan(String san) {
  final String cleaned = san
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .trim()
      .toLowerCase();
  if (cleaned.isEmpty || cleaned == 'p') {
    return const <String>[];
  }
  if (!cleaned.contains('x')) {
    return <String>[cleaned];
  }
  final List<String> segments = <String>[];
  if (!cleaned.startsWith('x')) {
    segments.add(cleaned.substring(0, cleaned.indexOf('x')));
  }
  segments.addAll(
    RegExp(
      r'x[a-g][1-7]',
    ).allMatches(cleaned).map((RegExpMatch match) => match.group(0)!),
  );
  return segments;
}
