// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_service.dart

import 'package:flutter/material.dart';

import '../../../game_platform/game_session.dart';
import '../../../game_shell/game_session_scope.dart';
import '../../../games/mill/mill_perfect_database_support.dart';
import '../../../games/mill/native_mill_ai_turn_controller.dart';
import '../../../games/mill/native_mill_game_session.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/services/perfect_database_service.dart';
import '../../../src/rust/api/simple.dart' as tgf;
import '../analysis_mode.dart';

/// Drives the perfect-database analysis overlay.
///
/// [toggle] runs the analysis (or turns the overlay off when it is already
/// on) and is the single entry point shared by the toolbar button and the
/// on-board corner button.  All board access goes through the active
/// [NativeMillGameSession], so the analysis reflects exactly the position the
/// Rust kernel holds.
class AnalysisService {
  AnalysisService._();

  static const String _logTag = "[AnalysisService]";

  /// Toggle the analysis overlay for the position currently shown by the
  /// session in scope of [context].
  ///
  /// When the overlay is already enabled it is simply disabled.  Otherwise
  /// the perfect database is queried for every legal move and the overlay is
  /// enabled with the resulting verdicts.  User-facing reasons (unsupported
  /// rules, database disabled, no results) are surfaced via a snackbar.
  static Future<void> toggle(BuildContext context) async {
    if (AnalysisMode.isFullAnalysis) {
      AnalysisMode.disable();
      return;
    }

    if (!isRuleSupportingPerfectDatabase()) {
      _showSnackBar(context, S.of(context).currentRulesNoPerfectDatabase);
      return;
    }

    if (!DB().generalSettings.usePerfectDatabase) {
      _showSnackBar(context, S.of(context).perfectDatabaseNotEnabled);
      return;
    }

    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to analyze.");
      return;
    }

    AnalysisMode.setAnalyzing(true);
    try {
      // The overlay needs the database initialized; ensure copy + init has
      // run.  Idempotent after the first successful call.
      final bool ready = await ensurePerfectDatabaseReady();
      if (!ready) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).perfectDatabaseNotEnabled);
        }
        return;
      }

      final tgf.MillAnalysisReport report = session.analyzePerfectDb();
      if (report.moves.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).currentRulesNoPerfectDatabase);
        }
        return;
      }

      final List<MoveAnalysisResult> results = report.moves
          .map(_resultFromDto)
          .toList(growable: false);
      AnalysisMode.enable(results, trapMoves: report.traps);
    } catch (e, st) {
      logger.e("$_logTag Analysis failed: $e", stackTrace: st);
    } finally {
      AnalysisMode.setAnalyzing(false);
    }
  }

  /// Show a Lichess-style single best-move hint without applying the move.
  static Future<bool> showBestMoveHint(BuildContext context) async {
    assert(
      !AnalysisMode.isAnalyzing,
      'Cannot request a hint while another analysis pass is running.',
    );

    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to hint.");
      return false;
    }

    final GeneralSettings engineSettings = DB().generalSettings.copyWith(
      resignIfMostLose: false,
    );
    final NativeMillAiTurnController hintSearch = NativeMillAiTurnController(
      generalSettings: engineSettings,
    );

    AnalysisMode.disable();
    AnalysisMode.setAnalyzing(true);
    try {
      final GameAction? action = await session.searchBestAction(
        depth: hintSearch.searchDepthForSession(session),
        moveLimitMs: hintSearch.moveLimitMs,
        engineSettings: engineSettings,
      );
      if (action == null) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).noMoreHintsAvailable);
        }
        return false;
      }

      final Object? movePayload = action.payload['move'];
      assert(
        movePayload is String && movePayload.isNotEmpty,
        'Hint action must carry a non-empty move notation.',
      );
      final String move = movePayload! as String;

      final int? score = session.lastAiBestValue;
      AnalysisMode.enable(<MoveAnalysisResult>[
        MoveAnalysisResult(move: move, outcome: _hintOutcome(score)),
      ], mode: AnalysisOverlayMode.hint);
      return true;
    } catch (e, st) {
      logger.e("$_logTag Hint failed: $e", stackTrace: st);
      return false;
    } finally {
      AnalysisMode.setAnalyzing(false);
    }
  }

  static NativeMillGameSession? _activeNativeSession(BuildContext context) {
    final Object? session = GameSessionScope.sessionOf(context);
    return session is NativeMillGameSession ? session : null;
  }

  static AnalysisOutcome _hintOutcome(int? score) {
    if (score == null) {
      return AnalysisOutcome.unknown;
    }
    final AnalysisOutcome base = switch (score.sign) {
      1 => AnalysisOutcome.advantage,
      -1 => AnalysisOutcome.disadvantage,
      _ => AnalysisOutcome.draw,
    };
    return AnalysisOutcome.withValue(base, score.toString());
  }

  static MoveAnalysisResult _resultFromDto(tgf.MillMoveAnalysis dto) {
    final AnalysisOutcome base = switch (dto.outcome) {
      'win' => AnalysisOutcome.win,
      'loss' => AnalysisOutcome.loss,
      'draw' => AnalysisOutcome.draw,
      'advantage' => AnalysisOutcome.advantage,
      'disadvantage' => AnalysisOutcome.disadvantage,
      _ => AnalysisOutcome.unknown,
    };
    return MoveAnalysisResult(
      move: dto.mv,
      outcome: AnalysisOutcome.withValueAndSteps(
        base,
        dto.value.toString(),
        dto.steps >= 0 ? dto.steps : null,
      ),
    );
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
