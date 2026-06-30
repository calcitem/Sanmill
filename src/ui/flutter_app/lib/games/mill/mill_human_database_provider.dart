// SPDX-License-Identifier: AGPL-3.0-or-later
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

  // Skill -> minimum human games a move needs before it is played from the
  // database (otherwise the position falls through to the native search). Tied
  // to skill rather than a user knob: a stronger AI leans on its deep search
  // and only trusts well-supported human moves, so it requires more games; a
  // weaker AI uses the database more freely, including thinly sampled, more
  // human moves. Interpolated geometrically across the clamped skill range.
  static const int _minSamplesAtMinSkill = 3; // weak AI: permissive
  static const int _minSamplesAtMaxSkill = 30; // strong AI: selective

  // Skill -> softmax temperature for randomized ("Move randomly") selection over
  // each candidate's confidence-weighted score ([tgf.MillHumanDatabaseMove.
  // scoreDelta]). Low skill = high temperature = a broad, more varied and weaker
  // choice; high skill = low temperature = concentrate on the strongest human
  // move. Interpolated geometrically across the clamped skill range so the
  // change in concentration is smooth and perceptually even.
  static const double _minTemperature = 0.05; // _maxSkill: near-deterministic
  static const double _maxTemperature = 0.5; // _minSkill: broad
  static const double _temperatureFloor = 1e-3;
  static const int _minSkill = 1;
  static const int _maxSkill = 30;

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

  /// Per-move sample threshold used for the query, derived from
  /// [GeneralSettings.skillLevel] (see [minSamplesForSkill]). Positions whose
  /// only candidates fall short are left to the engine search, so a thin entry
  /// can no longer override calculated play; how thin is "too thin" scales with
  /// skill.
  int get _effectiveMinSamples =>
      minSamplesForSkill(generalSettings.skillLevel);

  /// Maps a skill level (clamped to [_minSkill]..[_maxSkill]) to the minimum
  /// number of human games a candidate must have. Geometric interpolation
  /// across the skill range: the minimum skill yields [_minSamplesAtMinSkill],
  /// the maximum skill [_minSamplesAtMaxSkill]. Shared with the opening
  /// explorer so advisory database rows use the same confidence floor.
  static int minSamplesForSkill(int skillLevel) {
    final int skill = skillLevel.clamp(_minSkill, _maxSkill);
    final double fraction = (skill - _minSkill) / (_maxSkill - _minSkill);
    final int samples =
        (_minSamplesAtMinSkill *
                pow(
                  _minSamplesAtMaxSkill / _minSamplesAtMinSkill,
                  fraction,
                ).toDouble())
            .round();
    if (samples < _minSamplesAtMinSkill) {
      return _minSamplesAtMinSkill;
    }
    if (samples > _minSamplesAtMaxSkill) {
      return _minSamplesAtMaxSkill;
    }
    return samples;
  }

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
      skillLevel: generalSettings.skillLevel,
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
      'shuffling=${generalSettings.shufflingEnabled} '
      'skill=${generalSettings.skillLevel}',
    );
    return chosen.action;
  }

  /// Selects the index of the Human Database candidate to play.
  ///
  /// With [shuffling] off the move with the highest confidence-weighted score
  /// is chosen (ties broken by the larger sample count) — the strongest human
  /// move, independent of skill.
  ///
  /// With [shuffling] on the move is drawn from a softmax over each candidate's
  /// [tgf.MillHumanDatabaseMove.scoreDelta], with the temperature derived from
  /// [skillLevel] (see [_temperatureForSkill]): a higher skill concentrates the
  /// draw on the best-scoring move, a lower skill spreads it toward weaker, more
  /// varied moves. Score (not raw popularity) drives the weighting, and
  /// `scoreDelta` already folds in a sample-size confidence factor, so thinly
  /// sampled flukes stay unlikely.
  @visibleForTesting
  static int selectCandidateIndex(
    List<tgf.MillHumanDatabaseMove> candidates, {
    required bool shuffling,
    required int skillLevel,
    required Random random,
  }) {
    assert(candidates.isNotEmpty, 'Candidate list must not be empty.');
    if (candidates.length == 1) {
      return 0;
    }
    if (!shuffling) {
      return _bestScoreIndex(candidates);
    }
    return _softmaxSampleIndex(
      candidates,
      _temperatureForSkill(skillLevel),
      random,
    );
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

  /// Maps a skill level (clamped to [_minSkill]..[_maxSkill]) to a softmax
  /// temperature in [_minTemperature].._maxTemperature]. The interpolation is
  /// geometric in the skill fraction, so each skill step changes the
  /// concentration by a roughly constant ratio: the minimum skill yields the
  /// broad [_maxTemperature], the maximum skill the sharp [_minTemperature].
  static double _temperatureForSkill(int skillLevel) {
    final int skill = skillLevel.clamp(_minSkill, _maxSkill);
    final double fraction = (skill - _minSkill) / (_maxSkill - _minSkill);
    return _maxTemperature *
        pow(_minTemperature / _maxTemperature, fraction).toDouble();
  }

  /// Numerically stable softmax over `scoreDelta`, then one weighted draw.
  static int _softmaxSampleIndex(
    List<tgf.MillHumanDatabaseMove> candidates,
    double temperature,
    Random random,
  ) {
    final double t = temperature < _temperatureFloor
        ? _temperatureFloor
        : temperature;
    double maxScore = candidates.first.scoreDelta;
    for (final tgf.MillHumanDatabaseMove move in candidates) {
      if (move.scoreDelta > maxScore) {
        maxScore = move.scoreDelta;
      }
    }
    final List<double> weights = <double>[
      for (final tgf.MillHumanDatabaseMove move in candidates)
        exp((move.scoreDelta - maxScore) / t),
    ];
    double totalWeight = 0;
    for (final double weight in weights) {
      totalWeight += weight;
    }
    assert(totalWeight > 0, 'Softmax weights must sum to a positive value.');
    double target = random.nextDouble() * totalWeight;
    for (int i = 0; i < weights.length; i++) {
      target -= weights[i];
      if (target < 0) {
        return i;
      }
    }
    // Defensive fallback for floating-point rounding; the loop normally returns.
    return candidates.length - 1;
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
