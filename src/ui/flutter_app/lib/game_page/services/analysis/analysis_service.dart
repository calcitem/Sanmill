// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_service.dart

import 'dart:async';
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
  static const int _analysisSkillLevel = 30;

  static int _analysisSearchGeneration = 0;
  static Future<void>? _activeEngineAnalysis;

  @visibleForTesting
  static NativeMillGameSession Function(GeneralSettings engineSettings)?
  debugCreateTemporarySession;

  /// Toggle the analysis overlay for the position currently shown by the
  /// session in scope of [context].
  ///
  /// When the overlay is already enabled it is simply disabled.  Otherwise
  /// Perfect Database verdicts are shown when available.  The native engine
  /// still emits root MultiPV lines so enabled analysis sources can be shown
  /// together.
  static Future<void> toggle(BuildContext context) async {
    if (AnalysisMode.isFullAnalysis || AnalysisMode.isAnalyzing) {
      if (AnalysisMode.isAnalyzing) {
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

    final int refreshGeneration = ++_analysisSearchGeneration;
    _PerfectDatabaseAnalysis? perfectDatabaseAnalysis;
    if (isRuleSupportingPerfectDatabase() &&
        DB().generalSettings.usePerfectDatabase) {
      AnalysisMode.setAnalyzing(true);
      perfectDatabaseAnalysis = await _loadPerfectDatabaseAnalysis(
        context,
        session,
      );
      if (refreshGeneration != _analysisSearchGeneration) {
        return;
      }
      if (!context.mounted) {
        AnalysisMode.setAnalyzing(false);
        return;
      }
      if (perfectDatabaseAnalysis != null) {
        AnalysisMode.enable(
          perfectDatabaseAnalysis.results,
          lineResults: perfectDatabaseAnalysis.lineResults,
          trapMoves: perfectDatabaseAnalysis.trapMoves,
          source: AnalysisSource.perfectDatabase,
          isAnalyzing: true,
        );
      }
    }

    await _enableEngineMultiPvAnalysis(
      context,
      session,
      baseResults: perfectDatabaseAnalysis?.results,
      baseTrapMoves: perfectDatabaseAnalysis?.trapMoves ?? const <String>[],
    );
  }

  /// Restart analysis after the current analysis-board position changes.
  ///
  /// This mirrors Lichess' path-change evaluation flow: the previous search is
  /// stopped before the new position requests its enabled analysis sources.
  static Future<void> refreshForCurrentPosition(BuildContext context) async {
    if (AnalysisMode.isAnalyzing) {
      final Future<void>? activeEngineAnalysis = _activeEngineAnalysis;
      _stopCurrentEngineAnalysis();
      AnalysisMode.setAnalyzing(false);
      if (activeEngineAnalysis != null) {
        await activeEngineAnalysis;
      }
    }
    if (!context.mounted) {
      return;
    }
    await refresh(context);
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

    final bool preservePerfectDatabase =
        AnalysisMode.source == AnalysisSource.perfectDatabase ||
        AnalysisMode.source == AnalysisSource.perfectDatabaseAndEngine;
    String? fenOverride;
    final bool isThreatMode = AnalysisMode.isThreatMode;
    if (isThreatMode) {
      if (!canShowThreat(session)) {
        logger.w("$_logTag Threat mode is not available for deeper search.");
        return;
      }
      fenOverride = _fenWithOppositeSideToMove(session.getFen());
      if (fenOverride.isEmpty) {
        logger.w("$_logTag Could not build threat-mode FEN for deep search.");
        return;
      }
    }
    await _enableEngineMultiPvAnalysis(
      context,
      session,
      isDeepSearch: true,
      fenOverride: fenOverride,
      isThreatMode: isThreatMode,
      baseResults: preservePerfectDatabase
          ? AnalysisMode.analysisResults
          : null,
      baseTrapMoves: preservePerfectDatabase
          ? AnalysisMode.trapMoves
          : const <String>[],
    );
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

  static Future<_PerfectDatabaseAnalysis?> _loadPerfectDatabaseAnalysis(
    BuildContext context,
    NativeMillGameSession session,
  ) async {
    try {
      // The overlay needs the database initialized; ensure copy + init has
      // run.  Idempotent after the first successful call.
      final bool ready = await ensurePerfectDatabaseReady();
      if (!ready) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).perfectDatabaseNotEnabled);
        }
        return null;
      }

      final tgf.MillAnalysisReport report = session.analyzePerfectDb();
      if (report.moves.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, S.of(context).currentRulesNoPerfectDatabase);
        }
        return null;
      }

      final List<MoveAnalysisResult> results = report.moves
          .map(_resultFromDto)
          .toList(growable: false);
      return _PerfectDatabaseAnalysis(
        results,
        _rankedLineResults(results),
        report.traps,
      );
    } catch (e, st) {
      logger.e("$_logTag Analysis failed: $e", stackTrace: st);
      return null;
    }
  }

  static Future<void> _enableEngineMultiPvAnalysis(
    BuildContext context,
    NativeMillGameSession session, {
    bool isDeepSearch = false,
    String? fenOverride,
    bool isThreatMode = false,
    List<MoveAnalysisResult>? baseResults,
    List<String> baseTrapMoves = const <String>[],
  }) async {
    final int searchGeneration = ++_analysisSearchGeneration;
    final Completer<void> activeEngineAnalysis = Completer<void>();
    _activeEngineAnalysis = activeEngineAnalysis.future;
    final int requestedLineCount = math.max(1, AnalysisMode.engineLineCount);
    final GeneralSettings currentSettings = DB().generalSettings;
    assert(
      AnalysisMode.engineThreadOptions.contains(currentSettings.engineThreads),
      'Unsupported analysis engine thread count: '
      '${currentSettings.engineThreads}.',
    );
    final bool useAnalysisThreads =
        requestedLineCount == 1 && currentSettings.engineThreads > 1;
    final GeneralSettings engineSettings = _analysisEngineSettings(
      currentSettings,
      useAnalysisThreads: useAnalysisThreads,
    );
    const int searchDepth = _analysisSearchDepth;
    final int moveLimitMs = isDeepSearch
        ? AnalysisMode.maxEngineSearchTimeMs
        : AnalysisMode.engineSearchTimeMs;
    NativeMillGameSession? temporarySession;
    final NativeMillGameSession searchSession;
    if (fenOverride == null) {
      searchSession = session;
    } else {
      temporarySession =
          debugCreateTemporarySession?.call(engineSettings) ??
          NativeMillGameSession(
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
              _publishEngineVariations(
                current,
                isThreatMode: isThreatMode,
                isAnalyzing: true,
                baseResults: baseResults,
                baseTrapMoves: baseTrapMoves,
              );
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
      _publishEngineVariations(
        variations,
        isThreatMode: isThreatMode,
        baseResults: baseResults,
        baseTrapMoves: baseTrapMoves,
      );
    } catch (e, st) {
      if (searchGeneration == _analysisSearchGeneration) {
        logger.e("$_logTag Engine MultiPV analysis failed: $e", stackTrace: st);
      }
    } finally {
      temporarySession?.dispose();
      if (identical(_activeEngineAnalysis, activeEngineAnalysis.future)) {
        _activeEngineAnalysis = null;
      }
      if (!activeEngineAnalysis.isCompleted) {
        activeEngineAnalysis.complete();
      }
      if (searchGeneration == _analysisSearchGeneration) {
        AnalysisMode.setAnalyzing(false);
      }
    }
  }

  static GeneralSettings _analysisEngineSettings(
    GeneralSettings currentSettings, {
    required bool useAnalysisThreads,
  }) {
    // Analysis must not inherit weak play knobs such as Random, MCTS, lazy
    // search, or low skill levels. Lichess treats analysis as a full-strength
    // evaluation path while keeping user-selected line count, time, and
    // thread preferences.
    return currentSettings.copyWith(
      searchAlgorithm: SearchAlgorithm.pvs,
      aiIsLazy: false,
      skillLevel: _analysisSkillLevel,
      resignIfMostLose: false,
      shufflingEnabled: useAnalysisThreads,
      useLazySmp: useAnalysisThreads,
    );
  }

  static void _publishEngineVariations(
    List<NativeMillPrincipalVariation> variations, {
    required bool isThreatMode,
    bool isAnalyzing = false,
    List<MoveAnalysisResult>? baseResults,
    List<String> baseTrapMoves = const <String>[],
  }) {
    final List<MoveAnalysisResult> engineResults = variations
        .map(
          (NativeMillPrincipalVariation variation) => MoveAnalysisResult(
            move: variation.move,
            outcome: _engineOutcome(variation.score),
            rank: variation.rank,
            depth: variation.depth,
            nodes: variation.nodes,
            nodesPerSecond: variation.nodesPerSecond,
            line: variation.line,
          ),
        )
        .toList(growable: false);
    final bool hasBaseResults = baseResults != null;
    AnalysisMode.enable(
      baseResults ?? engineResults,
      lineResults: hasBaseResults ? engineResults : null,
      trapMoves: hasBaseResults ? baseTrapMoves : const <String>[],
      source: hasBaseResults
          ? AnalysisSource.perfectDatabaseAndEngine
          : AnalysisSource.engine,
      isThreatMode: isThreatMode,
      isAnalyzing: isAnalyzing,
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

class _PerfectDatabaseAnalysis {
  const _PerfectDatabaseAnalysis(
    this.results,
    this.lineResults,
    this.trapMoves,
  );

  final List<MoveAnalysisResult> results;
  final List<MoveAnalysisResult> lineResults;
  final List<String> trapMoves;
}
