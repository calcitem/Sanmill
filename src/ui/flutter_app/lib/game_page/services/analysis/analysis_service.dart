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
import '../mill.dart' show GameController;

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
  static const int _analysisSearchDepth = 64;
  static const int _analysisDefaultMoveLimitMs = 6000;
  static const int _analysisDeepMoveLimitMs = 60 * 60 * 1000;

  static int _analysisSearchGeneration = 0;

  /// Toggle the analysis overlay for the position currently shown by the
  /// session in scope of [context].
  ///
  /// When the overlay is already enabled it is simply disabled.  Otherwise
  /// Perfect Database verdicts are preferred when available.  Otherwise the
  /// native engine emits a lightweight root MultiPV list for the current
  /// position and the overlay shows those candidate moves.
  static Future<void> toggle(BuildContext context) async {
    if (AnalysisMode.isFullAnalysis) {
      if (AnalysisMode.isAnalyzing &&
          AnalysisMode.source == AnalysisSource.engine) {
        _stopCurrentEngineAnalysis();
      }
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

    await _enableEngineMultiPvAnalysis(context, session, isDeepSearch: true);
  }

  /// Whether threat mode can be requested without fabricating an impossible Mill
  /// turn state.
  static bool canShowThreat(NativeMillGameSession session) {
    if (session.outcome.isTerminal) {
      return false;
    }
    if (session.state.value.phase != 'placing' &&
        session.state.value.phase != 'moving') {
      return false;
    }
    final List<String> fields = session.getFen().trim().split(RegExp(r'\s+'));
    if (fields.length < 4) {
      assert(
        false,
        'Mill FEN must contain board, side, phase, and act fields.',
      );
      return false;
    }
    return fields[3] != 'r';
  }

  /// Toggle a Lichess-style threat search: analyse as if the opponent were to
  /// move from the current board position.
  static Future<void> toggleThreat(BuildContext context) async {
    assert(
      !AnalysisMode.isAnalyzing,
      'Cannot toggle threat mode while another analysis pass is running.',
    );
    if (AnalysisMode.isAnalyzing) {
      return;
    }
    if (AnalysisMode.isThreatMode) {
      await refresh(context);
      return;
    }

    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to show threat.");
      return;
    }
    if (!canShowThreat(session)) {
      logger.w("$_logTag Threat mode is not available for this position.");
      return;
    }

    final String threatFen = _fenWithOppositeSideToMove(session.getFen());
    if (threatFen.isEmpty) {
      logger.w("$_logTag Could not build threat-mode FEN.");
      return;
    }

    await _enableEngineMultiPvAnalysis(
      context,
      session,
      fenOverride: threatFen,
      isThreatMode: true,
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
      AnalysisMode.enable(
        results,
        lineResults: _rankedLineResults(results),
        trapMoves: report.traps,
        source: AnalysisSource.perfectDatabase,
      );
    } catch (e, st) {
      logger.e("$_logTag Analysis failed: $e", stackTrace: st);
    } finally {
      AnalysisMode.setAnalyzing(false);
    }
  }

  static Future<void> _enableEngineMultiPvAnalysis(
    BuildContext context,
    NativeMillGameSession session, {
    bool isDeepSearch = false,
    String? fenOverride,
    bool isThreatMode = false,
  }) async {
    final int searchGeneration = ++_analysisSearchGeneration;
    final int requestedLineCount = math.max(1, AnalysisMode.engineLineCount);
    final GeneralSettings currentSettings = DB().generalSettings;
    final GeneralSettings engineSettings = currentSettings.copyWith(
      resignIfMostLose: false,
      useLazySmp: false,
    );
    final NativeMillAiTurnController analysisSearch =
        NativeMillAiTurnController(generalSettings: engineSettings);
    const int searchDepth = _analysisSearchDepth;
    final int moveLimitMs = isDeepSearch
        ? _analysisDeepMoveLimitMs
        : math.max(analysisSearch.moveLimitMs, _analysisDefaultMoveLimitMs);
    NativeMillGameSession? temporarySession;
    final NativeMillGameSession searchSession;
    if (fenOverride == null) {
      searchSession = session;
    } else {
      temporarySession = NativeMillGameSession(
        rules: DB().ruleSettings,
        generalSettings: engineSettings,
      );
      final bool loaded = temporarySession.loadFen(fenOverride);
      assert(loaded, 'Threat-mode FEN must load into the temporary session.');
      if (!loaded) {
        temporarySession.dispose();
        return;
      }
      searchSession = temporarySession;
    }

    AnalysisMode.setAnalyzing(true);
    bool published = false;
    try {
      final List<NativeMillPrincipalVariation> variations = await searchSession
          .searchPrincipalVariations(
            depth: searchDepth,
            moveLimitMs: moveLimitMs,
            multiPv: requestedLineCount,
            engineSettings: engineSettings,
            onUpdate: (List<NativeMillPrincipalVariation> current) {
              if (searchGeneration != _analysisSearchGeneration) {
                return;
              }
              published = true;
              _publishEngineVariations(current, isThreatMode: isThreatMode);
            },
          );
      if (searchGeneration != _analysisSearchGeneration) {
        return;
      }
      if (variations.isEmpty) {
        if (!published && context.mounted) {
          _showSnackBar(context, S.of(context).noMoreHintsAvailable);
        }
        return;
      }
      _publishEngineVariations(variations, isThreatMode: isThreatMode);
    } catch (e, st) {
      if (searchGeneration == _analysisSearchGeneration) {
        logger.e("$_logTag Engine MultiPV analysis failed: $e", stackTrace: st);
      }
    } finally {
      temporarySession?.dispose();
      if (searchGeneration == _analysisSearchGeneration) {
        AnalysisMode.setAnalyzing(false);
      }
    }
  }

  static void _publishEngineVariations(
    List<NativeMillPrincipalVariation> variations, {
    required bool isThreatMode,
  }) {
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
      isThreatMode: isThreatMode,
    );
  }

  static void _stopCurrentEngineAnalysis() {
    _analysisSearchGeneration++;
    tgf.nativeMillSearchStop();
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
    if (session is NativeMillGameSession) {
      return session;
    }
    return GameController().activeNativeMillSession;
  }

  static String _fenWithOppositeSideToMove(String fen) {
    final List<String> fields = fen.trim().split(RegExp(r'\s+'));
    if (fields.length < 2) {
      assert(false, 'Mill FEN must contain a side-to-move field.');
      return '';
    }
    fields[1] = switch (fields[1]) {
      'w' => 'b',
      'b' => 'w',
      final String side => throw StateError(
        'Unsupported Mill FEN side-to-move token: $side',
      ),
    };
    return fields.join(' ');
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

  static List<MoveAnalysisResult> _rankedLineResults(
    List<MoveAnalysisResult> results,
  ) {
    final List<MoveAnalysisResult> ranked = List<MoveAnalysisResult>.from(
      results,
    );
    ranked.sort(_compareLineResults);
    return ranked;
  }

  static int _compareLineResults(MoveAnalysisResult a, MoveAnalysisResult b) {
    final int valueOrder = _lineSortValue(b).compareTo(_lineSortValue(a));
    if (valueOrder != 0) {
      return valueOrder;
    }

    final int stepOrder = _compareStepTie(a, b);
    if (stepOrder != 0) {
      return stepOrder;
    }

    const int noRank = 1 << 30;
    final int rankOrder = (a.rank ?? noRank).compareTo(b.rank ?? noRank);
    if (rankOrder != 0) {
      return rankOrder;
    }

    return a.move.compareTo(b.move);
  }

  static int _compareStepTie(MoveAnalysisResult a, MoveAnalysisResult b) {
    final int? aSteps = a.outcome.stepCount;
    final int? bSteps = b.outcome.stepCount;
    if (aSteps == null && bSteps == null) {
      return 0;
    }
    if (aSteps == null) {
      return 1;
    }
    if (bSteps == null) {
      return -1;
    }

    final double value = _lineSortValue(a);
    if (value < 0) {
      return bSteps.compareTo(aSteps);
    }
    return aSteps.compareTo(bSteps);
  }

  static double _lineSortValue(MoveAnalysisResult result) {
    final String? value = result.outcome.valueStr;
    if (value != null && value.isNotEmpty) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return switch (result.outcome.name) {
      'win' => 1.0,
      'advantage' => 0.5,
      'draw' => 0.0,
      'disadvantage' => -0.5,
      'loss' => -1.0,
      _ => double.negativeInfinity,
    };
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
