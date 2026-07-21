// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_page/services/analysis/move_feedback.dart';
import '../../game_page/services/analysis/move_feedback_native_adapter.dart';
import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/services/mill.dart' show LiveEvaluationService;
import '../../game_platform/game_session.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../general_settings/models/general_settings.dart';
import '../../shared/database/database.dart';
import '../../src/rust/api/simple.dart' as tgf;
import '../models/review_models.dart';
import 'review_causal_attribution.dart';
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
  ReviewAnalysisService() : _storage = ReviewStorage.instance;

  @visibleForTesting
  ReviewAnalysisService.forTesting(this._storage);

  final ReviewStorage _storage;
  int _generation = 0;
  bool _searching = false;

  List<ReviewTurnBoundary> buildTimeline(PrivateGameRecord record) {
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(record.sourcePgn);
    final List<PgnNodeData> groupedMoves = game.moves.mainline().toList();
    final NativeMillGameSession session = NativeMillGameSession(
      rules: record.rules,
      generalSettings: _engineSettings(),
    );
    final String setupFen = game.headers['FEN']?.trim() ?? record.initialFen;
    if (setupFen.isNotEmpty && !session.loadFen(setupFen)) {
      session.dispose();
      throw StateError('Review record carries an invalid initial FEN.');
    }

    final List<ReviewTurnBoundary> turns = <ReviewTurnBoundary>[];
    int atomicIndex = 0;
    try {
      for (int groupIndex = 0; groupIndex < groupedMoves.length; groupIndex++) {
        final PgnNodeData groupedMove = groupedMoves[groupIndex];
        final List<String> segments = splitMillSan(groupedMove.san);
        if (segments.isEmpty) {
          continue;
        }
        final int startAtomicIndex = atomicIndex;
        final ReviewSide turnSide = _reviewSide(session.state.value.activeSeat);
        for (final String move in segments) {
          _applyMove(session, move);
          atomicIndex++;
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
    } finally {
      session.dispose();
    }
    return List<ReviewTurnBoundary>.unmodifiable(turns);
  }

  Future<ReviewReport> analyze(
    PrivateGameRecord record, {
    ReviewProfile profile = ReviewProfile.quick,
    void Function(int completed, int total)? onProgress,
    bool ignoreCache = false,
  }) async {
    await LiveEvaluationService.stopAndWait();
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

    final List<ReviewActionEvaluation> attributed =
        await _attributeCausalMistakes(
          record: record,
          actions: actions,
          capacity: capacity,
          generation: generation,
        );
    if (generation != _generation) {
      return _cancelledReport(
        record: record,
        profile: profile,
        actions: attributed,
        turns: turns,
        variationCount: _variationCount(game.moves),
        engineVersion: engineVersion,
      );
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
      actions: List<ReviewActionEvaluation>.unmodifiable(attributed),
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
    await LiveEvaluationService.stopAndWait();
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
    final _ScoredMoveEvaluation scored = await _scoreCurrentMove(
      session: session,
      move: move,
      capacity: capacity,
      profile: profile,
    );
    final MoveFeedbackResult feedback = MoveFeedbackClassifier.classify(
      scored.input,
    );
    final ReviewGrade grade = _reviewGrade(feedback.symbol, scored.loss);
    _applyMove(session, move);
    return ReviewActionEvaluation(
      atomicIndex: atomicIndex,
      groupIndex: groupIndex,
      move: move,
      side: scored.side,
      isHumanMove: record.humanSides.contains(scored.side),
      legalRootActionCount: scored.input.legalRootActionCount,
      bestScore: scored.input.bestScore,
      playedScore: scored.input.playedScore,
      loss: scored.loss,
      grade: grade,
      profile: profile,
      candidates: scored.candidates,
      automaticNag: feedback.symbol.nag,
      feedbackReasons: feedback.reasons,
    );
  }

  /// Shallow pass finds disadvantage windows; binary-searched deep probes
  /// attribute the true root ply, then suppress later already-decided marks.
  Future<List<ReviewActionEvaluation>> _attributeCausalMistakes({
    required PrivateGameRecord record,
    required List<ReviewActionEvaluation> actions,
    required int capacity,
    required int generation,
  }) async {
    if (actions.isEmpty) {
      return actions;
    }
    List<ReviewActionEvaluation> updated = List<ReviewActionEvaluation>.from(
      actions,
    );
    final Map<int, _ProbeSnapshot> probeCache = <int, _ProbeSnapshot>{};

    Future<_ProbeSnapshot> probe(int atomicIndex) async {
      final _ProbeSnapshot? cached = probeCache[atomicIndex];
      if (cached != null) {
        return cached;
      }
      final _ProbeSnapshot fresh = await _probeParentPosition(
        record: record,
        actions: updated,
        atomicIndex: atomicIndex,
        capacity: capacity,
        profile: ReviewProfile.blameProbe,
      );
      probeCache[atomicIndex] = fresh;
      return fresh;
    }

    for (final ReviewSide side in ReviewSide.values) {
      int fromAtomicIndex = 0;
      while (true) {
        if (generation != _generation) {
          return updated;
        }
        final int? collapse = ReviewCausalAttribution.firstDisadvantageAnchor(
          updated,
          side,
          fromAtomicIndex: fromAtomicIndex,
        );
        if (collapse == null) {
          break;
        }
        final List<int> indices = ReviewCausalAttribution.sideIndicesThrough(
          updated,
          side,
          collapse,
          fromAtomicIndex: fromAtomicIndex,
        );
        if (indices.length < 2) {
          fromAtomicIndex = collapse + 1;
          continue;
        }

        final int? blameIndex =
            await ReviewCausalAttribution.findRootBlameIndex(
              indices: indices,
              isSaveable: (int atomicIndex) async {
                final _ProbeSnapshot snapshot = await probe(atomicIndex);
                return ReviewCausalAttribution.positionIsSaveable(
                  bestScore: snapshot.bestScore,
                  source: snapshot.source,
                );
              },
              probe: (int atomicIndex) async {
                final _ProbeSnapshot snapshot = await probe(atomicIndex);
                return BlameProbe(
                  bestScore: snapshot.bestScore,
                  playedScore: snapshot.playedScore,
                  playedRank: snapshot.playedRank,
                  source: snapshot.source,
                );
              },
            );
        if (blameIndex == null) {
          // No true self-root: clear episode negatives without inventing blame.
          updated = ReviewCausalAttribution.clearNegativesAt(updated, indices);
          fromAtomicIndex = collapse + 1;
          continue;
        }

        final _ProbeSnapshot blameProbe = await probe(blameIndex);
        final int listIndex = updated.indexWhere(
          (ReviewActionEvaluation action) => action.atomicIndex == blameIndex,
        );
        assert(listIndex >= 0);
        final ReviewActionEvaluation current = updated[listIndex];
        final MoveFeedbackResult feedback = MoveFeedbackClassifier.classify(
          MoveFeedbackInput(
            bestScore: blameProbe.bestScore,
            playedScore: blameProbe.playedScore,
            playedRank: blameProbe.playedRank,
            legalRootActionCount: blameProbe.legalRootActionCount,
            depth: blameProbe.depth,
            runnerUpScore: blameProbe.runnerUpScore,
            searchStable: true,
            candidateCoverageComplete: true,
            allCandidatesLosing: blameProbe.allCandidatesLosing,
            causalResultForfeited: true,
            source: blameProbe.source,
            evidence: blameProbe.evidence,
          ),
        );
        updated[listIndex] = ReviewActionEvaluation(
          atomicIndex: current.atomicIndex,
          groupIndex: current.groupIndex,
          move: current.move,
          side: current.side,
          isHumanMove: current.isHumanMove,
          legalRootActionCount: blameProbe.legalRootActionCount,
          bestScore: blameProbe.bestScore,
          playedScore: blameProbe.playedScore,
          loss: blameProbe.loss,
          grade: _reviewGrade(feedback.symbol, blameProbe.loss),
          profile: ReviewProfile.blameProbe,
          candidates: blameProbe.candidates,
          automaticNag: feedback.symbol.nag,
          feedbackReasons: feedback.reasons,
        );
        updated = ReviewCausalAttribution.suppressSubsequentNegatives(
          actions: updated,
          side: side,
          blameAtomicIndex: blameIndex,
        );
        fromAtomicIndex = collapse + 1;
      }
    }

    return ReviewCausalAttribution.suppressTrailingNegativesAfterFirstBlame(
      updated,
    );
  }

  Future<_ProbeSnapshot> _probeParentPosition({
    required PrivateGameRecord record,
    required List<ReviewActionEvaluation> actions,
    required int atomicIndex,
    required int capacity,
    required ReviewProfile profile,
  }) async {
    final NativeMillGameSession session = NativeMillGameSession(
      rules: record.rules,
      generalSettings: _engineSettings(),
    );
    try {
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(record.sourcePgn);
      final String setupFen = game.headers['FEN']?.trim() ?? record.initialFen;
      if (setupFen.isNotEmpty && !session.loadFen(setupFen)) {
        throw StateError('Review record carries an invalid initial FEN.');
      }
      final ReviewActionEvaluation target = actions.firstWhere(
        (ReviewActionEvaluation action) => action.atomicIndex == atomicIndex,
      );
      for (final ReviewActionEvaluation action in actions) {
        if (action.atomicIndex >= atomicIndex) {
          break;
        }
        _applyMove(session, action.move);
      }
      final _ScoredMoveEvaluation scored = await _scoreCurrentMove(
        session: session,
        move: target.move,
        capacity: capacity,
        profile: profile,
      );
      return _ProbeSnapshot(
        bestScore: scored.input.bestScore,
        playedScore: scored.input.playedScore,
        loss: scored.loss,
        playedRank: scored.input.playedRank,
        legalRootActionCount: scored.input.legalRootActionCount,
        depth: scored.input.depth,
        runnerUpScore: scored.input.runnerUpScore,
        allCandidatesLosing: scored.input.allCandidatesLosing,
        source: scored.input.source,
        evidence: scored.input.evidence,
        candidates: scored.candidates,
      );
    } finally {
      session.dispose();
    }
  }

  Future<_ScoredMoveEvaluation> _scoreCurrentMove({
    required NativeMillGameSession session,
    required String move,
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
    final MoveFeedbackExactScores? exact = moveFeedbackExactScores(
      session.analyzePerfectDb(),
      playedMove: move,
      legalActionCount: legalActions.length,
    );
    final int bestScore =
        exact?.bestScore ?? variations.first.score * perspective;
    final int playedScore = exact?.playedScore ?? played.score * perspective;
    final int loss = bestScore > playedScore ? bestScore - playedScore : 0;
    final MoveFeedbackEvidence evidence = moveFeedbackEvidenceFromNative(
      session.feedbackEvidenceForMove(move, variations),
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
    final ReviewCandidate? runnerUp = candidates
        .where((ReviewCandidate candidate) => candidate.rank == 2)
        .firstOrNull;
    return _ScoredMoveEvaluation(
      side: side,
      loss: loss,
      candidates: candidates,
      input: MoveFeedbackInput(
        bestScore: bestScore,
        playedScore: playedScore,
        playedRank: played.rank,
        legalRootActionCount: legalActions.length,
        depth: played.depth,
        runnerUpScore: exact?.runnerUpScore ?? runnerUp?.score,
        searchStable:
            variations.every(
              (NativeMillPrincipalVariation variation) =>
                  variation.depth == played.depth,
            ) &&
            played.depth > 0,
        candidateCoverageComplete: variations.length == legalActions.length,
        allCandidatesLosing:
            exact?.allCandidatesLosing ??
            candidates.every(
              (ReviewCandidate candidate) =>
                  candidate.score <= -MoveQualityThresholds.engineTerminalScore,
            ),
        source: exact == null
            ? MoveFeedbackSource.engine
            : MoveFeedbackSource.perfectDatabase,
        evidence: evidence,
      ),
    );
  }

  static ReviewGrade _reviewGrade(MoveFeedbackSymbol symbol, int loss) {
    return switch (symbol) {
      MoveFeedbackSymbol.blunder => ReviewGrade.blunder,
      MoveFeedbackSymbol.mistake => ReviewGrade.mistake,
      MoveFeedbackSymbol.dubious => ReviewGrade.dubious,
      MoveFeedbackSymbol.interesting => ReviewGrade.good,
      MoveFeedbackSymbol.brilliant ||
      MoveFeedbackSymbol.good => ReviewGrade.best,
      MoveFeedbackSymbol.none =>
        loss <= MoveQualityThresholds.bestMaximum()
            ? ReviewGrade.best
            : ReviewGrade.good,
    };
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

class _ScoredMoveEvaluation {
  const _ScoredMoveEvaluation({
    required this.side,
    required this.loss,
    required this.candidates,
    required this.input,
  });

  final ReviewSide side;
  final int loss;
  final List<ReviewCandidate> candidates;
  final MoveFeedbackInput input;
}

class _ProbeSnapshot {
  const _ProbeSnapshot({
    required this.bestScore,
    required this.playedScore,
    required this.loss,
    required this.playedRank,
    required this.legalRootActionCount,
    required this.depth,
    required this.runnerUpScore,
    required this.allCandidatesLosing,
    required this.source,
    required this.evidence,
    required this.candidates,
  });

  final int bestScore;
  final int playedScore;
  final int loss;
  final int playedRank;
  final int legalRootActionCount;
  final int depth;
  final int? runnerUpScore;
  final bool allCandidatesLosing;
  final MoveFeedbackSource source;
  final MoveFeedbackEvidence evidence;
  final List<ReviewCandidate> candidates;
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
