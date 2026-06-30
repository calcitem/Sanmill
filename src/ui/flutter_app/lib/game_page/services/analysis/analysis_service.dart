// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_service.dart

import 'dart:math' as math;

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

/// Drives the analysis overlay.
///
/// [toggle] runs the analysis (or turns the overlay off when it is already
/// on) and is the single entry point shared by the toolbar button and the
/// on-board corner button.  All board access goes through the active
/// [NativeMillGameSession], so the analysis reflects exactly the position the
/// Rust kernel holds.
class AnalysisService {
  AnalysisService._();

  static const String _logTag = "[AnalysisService]";
  static const int _goDeeperDepthStep = 2;

  /// Toggle the analysis overlay for the position currently shown by the
  /// session in scope of [context].
  ///
  /// When the overlay is already enabled it is simply disabled.  Otherwise
  /// Perfect Database verdicts are preferred when available.  Otherwise the
  /// native engine emits a lightweight root MultiPV list for the current
  /// position and the overlay shows those candidate moves.
  static Future<void> toggle(BuildContext context) async {
    if (AnalysisMode.isFullAnalysis) {
      AnalysisMode.disable();
      return;
    }
    await refresh(context);
  }

  /// Re-run analysis for the position currently shown by the active session.
  static Future<void> refresh(BuildContext context) async {
    assert(
      !AnalysisMode.isAnalyzing,
      'Cannot refresh analysis while another analysis pass is running.',
    );
    if (AnalysisMode.isAnalyzing) {
      return;
    }
    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to analyze.");
      return;
    }

    if (isRuleSupportingPerfectDatabase() &&
        DB().generalSettings.usePerfectDatabase) {
      await _enablePerfectDatabaseAnalysis(context, session);
      return;
    }

    await _enableEngineMultiPvAnalysis(context, session);
  }

  /// Request a deeper local engine MultiPV pass for the current analysis
  /// position.
  static Future<void> goDeeper(BuildContext context) async {
    assert(
      !AnalysisMode.isAnalyzing,
      'Cannot deepen analysis while another analysis pass is running.',
    );
    if (AnalysisMode.isAnalyzing) {
      return;
    }

    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to deepen.");
      return;
    }

    final int requestedDepth =
        (_currentEngineDepth() ?? _defaultEngineDepth(session)) +
        _goDeeperDepthStep;
    await _enableEngineMultiPvAnalysis(
      context,
      session,
      requestedDepth: requestedDepth,
    );
  }

  static Future<void> _enablePerfectDatabaseAnalysis(
    BuildContext context,
    NativeMillGameSession session,
  ) async {
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

  static Future<void> _enableEngineMultiPvAnalysis(
    BuildContext context,
    NativeMillGameSession session, {
    int? requestedDepth,
  }) async {
    final GeneralSettings engineSettings = DB().generalSettings.copyWith(
      resignIfMostLose: false,
      useLazySmp: false,
    );
    final NativeMillAiTurnController analysisSearch =
        NativeMillAiTurnController(generalSettings: engineSettings);
    final int defaultDepth = analysisSearch.searchDepthForSession(session);
    final int searchDepth = requestedDepth == null
        ? defaultDepth
        : math.min(64, math.max(defaultDepth, requestedDepth));
    final int requestedLineCount = AnalysisMode.showEngineLines
        ? math.max(1, AnalysisMode.engineLineCount)
        : 1;

    AnalysisMode.setAnalyzing(true);
    try {
      final List<NativeMillPrincipalVariation> variations = await session
          .searchPrincipalVariations(
            depth: searchDepth,
            moveLimitMs: analysisSearch.moveLimitMs,
            multiPv: requestedLineCount,
            engineSettings: engineSettings,
          );
      if (variations.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).noMoreHintsAvailable);
        }
        return;
      }
      AnalysisMode.enable(
        variations
            .map(
              (NativeMillPrincipalVariation variation) => MoveAnalysisResult(
                move: variation.move,
                outcome: _engineOutcome(variation.score),
                rank: variation.rank,
                depth: variation.depth,
                nodes: variation.nodes,
                line: variation.line,
              ),
            )
            .toList(growable: false),
        source: AnalysisSource.engine,
      );
    } catch (e, st) {
      logger.e("$_logTag Engine MultiPV analysis failed: $e", stackTrace: st);
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
      AnalysisMode.enable(
        <MoveAnalysisResult>[
          MoveAnalysisResult(move: move, outcome: _hintOutcome(score)),
        ],
        mode: AnalysisOverlayMode.hint,
        source: AnalysisSource.engine,
      );
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

  static int _defaultEngineDepth(NativeMillGameSession session) {
    final GeneralSettings engineSettings = DB().generalSettings.copyWith(
      resignIfMostLose: false,
      useLazySmp: false,
    );
    return NativeMillAiTurnController(
      generalSettings: engineSettings,
    ).searchDepthForSession(session);
  }

  static int? _currentEngineDepth() {
    if (AnalysisMode.source != AnalysisSource.engine) {
      return null;
    }
    int? depth;
    for (final MoveAnalysisResult result in AnalysisMode.analysisResults) {
      final int? candidate = result.depth;
      if (candidate == null || candidate <= 0) {
        continue;
      }
      depth = depth == null ? candidate : math.max(depth, candidate);
    }
    return depth;
  }

  static AnalysisOutcome _hintOutcome(int? score) {
    if (score == null) {
      return AnalysisOutcome.unknown;
    }
    return _engineOutcome(score);
  }

  static AnalysisOutcome _engineOutcome(int score) {
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
