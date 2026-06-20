// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
  });

  static const int _maxCandidates = 24;
  static const int _minSamples = 3;

  final RuleSettings ruleSettings;
  final GeneralSettings generalSettings;

  String? _pendingCapture;
  HumanDatabaseMoveStats? _pendingStats;
  HumanDatabaseMoveStats? lastStats;

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
      minSamples: _minSamples,
    );
    if (!query.available) {
      logger.w(
        '[MillHumanDatabaseProvider] Human Database query unavailable: ${query.error}',
      );
      return null;
    }

    for (final tgf.MillHumanDatabaseMove candidate in query.moves) {
      final _HumanDbMoveParts parts = _HumanDbMoveParts.parse(
        candidate.notation,
      );
      final GameAction? action = _findLegalAction(session, parts.baseMove);
      if (action == null) {
        continue;
      }
      final HumanDatabaseMoveStats stats = HumanDatabaseMoveStats(
        notation: candidate.notation,
        wins: candidate.wins,
        losses: candidate.losses,
        draws: candidate.draws,
        total: candidate.total,
        scoreDelta: candidate.scoreDelta,
      );
      _pendingCapture = parts.captureMove;
      _pendingStats = parts.captureMove == null ? null : stats;
      lastStats = stats;
      logger.t(
        '[MillHumanDatabaseProvider] selected ${candidate.notation} '
        'score=${candidate.scoreDelta.toStringAsFixed(3)} '
        'samples=${candidate.total}',
      );
      return action;
    }

    return null;
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
