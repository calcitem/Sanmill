// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../game_platform/game_session.dart';
import '../../game_platform/opening_book_provider.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/services/human_database_service.dart';
import '../../shared/services/logger.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_action_codec.dart';
import 'mill_types.dart';
import 'native_mill_game_session.dart';

class MillHumanDatabaseProvider implements OpeningBookProvider {
  MillHumanDatabaseProvider({
    required this.ruleSettings,
    required this.generalSettings,
    Random? random,
  }) : _random = random ?? Random();

  static const int _maxCandidates = 24;

  /// Absolute floor for the per-move sample threshold sent to the query. The
  /// effective value is the user's "Minimum games to use a database move"
  /// setting ([GeneralSettings.humanDatabaseMinGames]); clamping here keeps a
  /// stored 0 or negative from dropping below a safe floor.
  static const int _minSamplesFloor = 1;

  // Mainstream pool used by the "Move randomly" mode: a candidate qualifies
  // when it was played at least [_mainstreamMinSamples] times and reached at
  // least [_mainstreamRatio] of the most-played move's sample count.
  static const double _mainstreamRatio = 0.25;
  static const int _mainstreamMinSamples = 10;

  final RuleSettings ruleSettings;
  final GeneralSettings generalSettings;
  final Random _random;

  String? _pendingCapture;
  HumanDatabaseMoveStats? _pendingStats;
  HumanDatabaseMoveStats? lastStats;

  void discardPendingMove() {
    _pendingCapture = null;
    _pendingStats = null;
    lastStats = null;
  }

  /// Per-move sample threshold actually used for the query: the user's
  /// "Minimum games to use a database move" setting, never below the safety
  /// floor. Positions whose only candidates fall short are left to the engine
  /// search, so a thin entry can no longer override calculated play.
  int get _effectiveMinSamples =>
      max(_minSamplesFloor, generalSettings.humanDatabaseMinGames);

  @override
  GameAction? lookup(GameSession session) {
    lastStats = null;
    if (!generalSettings.humanDatabaseEnabled) {
      _pendingCapture = null;
      _pendingStats = null;
      return null;
    }
    if (generalSettings.humanDatabaseFilePath.trim().isEmpty) {
      _pendingCapture = null;
      _pendingStats = null;
      return null;
    }
    if (!_supportsCurrentRules()) {
      _pendingCapture = null;
      _pendingStats = null;
      return null;
    }
    if (session is! NativeMillGameSession || session.outcome.isTerminal) {
      _pendingCapture = null;
      _pendingStats = null;
      return null;
    }

    final GameAction? pendingCapture = _lookupPendingCapture(session);
    if (pendingCapture != null) {
      return pendingCapture;
    }
    if (_isRemoveTurn(session)) {
      return null;
    }

    final HumanDatabaseReadyResult ready = HumanDatabaseService.instance
        .ensureReadySync(generalSettings.humanDatabaseFilePath);
    if (!ready.ready) {
      logger.w(
        '[MillHumanDatabaseProvider] Human Database unavailable: ${ready.status.error}',
      );
      return null;
    }

    final tgf.MillHumanDatabaseQuery query = tgf.millHumanDbQuery(
      fen: session.getFen(),
      maxMoves: _maxCandidates,
      minSamples: _effectiveMinSamples,
    );
    if (!query.available) {
      logger.w(
        '[MillHumanDatabaseProvider] Human Database query unavailable: ${query.error}',
      );
      return null;
    }

    // Collect every database candidate that maps to a legal base move, then
    // pick one according to the "Move randomly" switch.
    final List<_HumanDbCandidate> candidates = <_HumanDbCandidate>[];
    for (final tgf.MillHumanDatabaseMove move in query.moves) {
      final _HumanDbMoveParts parts = _HumanDbMoveParts.parse(move.notation);
      final GameAction? action = _findLegalAction(session, parts.baseMove);
      if (action == null) {
        continue;
      }
      candidates.add(
        _HumanDbCandidate(move: move, parts: parts, action: action),
      );
    }
    if (candidates.isEmpty) {
      return null;
    }

    final List<tgf.MillHumanDatabaseMove> moves = <tgf.MillHumanDatabaseMove>[
      for (final _HumanDbCandidate candidate in candidates) candidate.move,
    ];
    final int index = selectCandidateIndex(
      moves,
      shuffling: generalSettings.shufflingEnabled,
      random: _random,
    );
    final _HumanDbCandidate chosen = candidates[index];

    final HumanDatabaseMoveStats stats = HumanDatabaseMoveStats(
      notation: chosen.move.notation,
      wins: chosen.move.wins,
      losses: chosen.move.losses,
      draws: chosen.move.draws,
      total: chosen.move.total,
      scoreDelta: chosen.move.scoreDelta,
    );
    _pendingCapture = chosen.parts.captureMove;
    _pendingStats = chosen.parts.captureMove == null ? null : stats;
    lastStats = stats;
    logger.t(
      '[MillHumanDatabaseProvider] selected ${chosen.move.notation} '
      'score=${chosen.move.scoreDelta.toStringAsFixed(3)} '
      'samples=${chosen.move.total} '
      'shuffling=${generalSettings.shufflingEnabled}',
    );
    return chosen.action;
  }

  /// Selects the index of the Human Database candidate to play.
  ///
  /// When [shuffling] is false the move with the highest confidence-weighted
  /// score is chosen (ties broken by the larger sample count). When [shuffling]
  /// is true a move is drawn at random, weighted by play frequency, from the
  /// "mainstream" pool (moves played often enough relative to the most popular
  /// one); if that pool is empty the best-score move is used instead.
  @visibleForTesting
  static int selectCandidateIndex(
    List<tgf.MillHumanDatabaseMove> candidates, {
    required bool shuffling,
    required Random random,
  }) {
    assert(candidates.isNotEmpty, 'Candidate list must not be empty.');
    if (!shuffling) {
      return _bestScoreIndex(candidates);
    }
    final List<int> pool = _mainstreamPoolIndices(candidates);
    if (pool.isEmpty) {
      return _bestScoreIndex(candidates);
    }
    return _frequencyWeightedChoice(candidates, pool, random);
  }

  static int _bestScoreIndex(List<tgf.MillHumanDatabaseMove> candidates) {
    int best = 0;
    for (int i = 1; i < candidates.length; i++) {
      final tgf.MillHumanDatabaseMove a = candidates[i];
      final tgf.MillHumanDatabaseMove b = candidates[best];
      if (a.scoreDelta > b.scoreDelta ||
          (a.scoreDelta == b.scoreDelta && a.total > b.total)) {
        best = i;
      }
    }
    return best;
  }

  static List<int> _mainstreamPoolIndices(
    List<tgf.MillHumanDatabaseMove> candidates,
  ) {
    int maxTotal = 0;
    for (final tgf.MillHumanDatabaseMove move in candidates) {
      if (move.total > maxTotal) {
        maxTotal = move.total;
      }
    }
    final double threshold = max(
      _mainstreamMinSamples.toDouble(),
      maxTotal * _mainstreamRatio,
    );
    final List<int> pool = <int>[];
    for (int i = 0; i < candidates.length; i++) {
      if (candidates[i].total >= threshold) {
        pool.add(i);
      }
    }
    return pool;
  }

  static int _frequencyWeightedChoice(
    List<tgf.MillHumanDatabaseMove> candidates,
    List<int> pool,
    Random random,
  ) {
    int totalWeight = 0;
    for (final int i in pool) {
      totalWeight += candidates[i].total;
    }
    assert(totalWeight > 0, 'Mainstream pool weight must be positive.');
    int target = random.nextInt(totalWeight);
    for (final int i in pool) {
      target -= candidates[i].total;
      if (target < 0) {
        return i;
      }
    }
    // Defensive fallback; unreachable when weights sum to totalWeight.
    return pool.last;
  }

  bool _supportsCurrentRules() {
    return ruleSettings.isLikelyNineMensMorris() &&
        ruleSettings.flyPieceCount == 3 &&
        ruleSettings.mayFly &&
        !ruleSettings.mayRemoveMultiple &&
        !ruleSettings.mayRemoveFromMillsAlways;
  }

  bool _isRemoveTurn(NativeMillGameSession session) {
    return session.legalActions.any(
      (GameAction action) => action.type == MillActionTypes.remove,
    );
  }

  GameAction? _lookupPendingCapture(NativeMillGameSession session) {
    final String? captureMove = _pendingCapture;
    if (captureMove == null) {
      return null;
    }

    final GameAction? action = _findLegalAction(session, captureMove);
    assert(
      action != null || !_isRemoveTurn(session),
      'Human Database suggested capture $captureMove is not legal in the remove turn.',
    );
    lastStats = action == null ? null : _pendingStats;
    _pendingCapture = null;
    _pendingStats = null;
    return action;
  }

  GameAction? _findLegalAction(
    NativeMillGameSession session,
    String moveString,
  ) {
    for (final GameAction action in session.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == moveString) {
        return action;
      }
    }
    return null;
  }
}

class _HumanDbCandidate {
  const _HumanDbCandidate({
    required this.move,
    required this.parts,
    required this.action,
  });

  final tgf.MillHumanDatabaseMove move;
  final _HumanDbMoveParts parts;
  final GameAction action;
}

class _HumanDbMoveParts {
  const _HumanDbMoveParts({required this.baseMove, required this.captureMove});

  final String baseMove;
  final String? captureMove;

  static _HumanDbMoveParts parse(String notation) {
    final int captureIndex = notation.indexOf('x');
    if (captureIndex < 0) {
      return _HumanDbMoveParts(baseMove: notation, captureMove: null);
    }
    final String baseMove = notation.substring(0, captureIndex);
    final String captureMove = notation.substring(captureIndex);
    assert(
      baseMove.isNotEmpty,
      'Human Database move notation must include a base move.',
    );
    assert(
      captureMove.length > 1,
      'Human Database capture notation must include a target.',
    );
    return _HumanDbMoveParts(baseMove: baseMove, captureMove: captureMove);
  }
}
