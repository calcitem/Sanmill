// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../game_shell/game_session_scope.dart';
import '../../../games/mill/mill_perfect_database_support.dart';
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
  static const int _hintSearchDepth = 32;
  static const int _hintSearchTimeMs = 10 * 60 * 1000;

  static int _analysisSearchGeneration = 0;
  static Future<void>? _activeEngineAnalysis;
  static AnalysisOverlayMode? _activeEngineAnalysisMode;
  static bool _isBestMoveHintSearching = false;
  static _BestMoveHintCacheEntry? _bestMoveHintCache;

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
    final bool wasAnalyzing = AnalysisMode.isAnalyzing;
    final Future<void>? activeEngineAnalysis = _activeEngineAnalysis;
    if (wasAnalyzing) {
      _stopCurrentEngineAnalysis();
      AnalysisMode.setAnalyzing(false);
    }
    if (AnalysisMode.isThreatMode) {
      AnalysisMode.disable();
    }
    // The previous engine pass keeps draining after its stop request (the
    // Rust-side abort is asynchronous) and `isAnalyzing` may already have
    // been cleared by a concurrent refresh, so gate the wait on the pass
    // future itself rather than on the `wasAnalyzing` flag.
    if (activeEngineAnalysis != null) {
      await activeEngineAnalysis;
    }
    if (!context.mounted) {
      return;
    }
    if (AnalysisMode.isAnalyzing) {
      // A newer analysis request restarted while this one waited for the
      // old pass to drain; it already covers the current position.
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
    if (AnalysisMode.isEngineAnalysisDeep) {
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
    final List<MoveAnalysisResult> previousEngineLines =
        AnalysisMode.hasEngineLinesSource
        ? AnalysisMode.analysisLineResults
        : const <MoveAnalysisResult>[];
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
      previousEngineLines: previousEngineLines,
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

  static Future<bool> _enableEngineMultiPvAnalysis(
    BuildContext context,
    NativeMillGameSession session, {
    bool isDeepSearch = false,
    String? fenOverride,
    bool isThreatMode = false,
    AnalysisOverlayMode mode = AnalysisOverlayMode.analysis,
    int? requestedLineCountOverride,
    int? searchDepthOverride,
    int? moveLimitMsOverride,
    List<MoveAnalysisResult>? baseResults,
    List<String> baseTrapMoves = const <String>[],
    List<MoveAnalysisResult> previousEngineLines = const <MoveAnalysisResult>[],
    _BestMoveHintCacheKey? hintCacheKey,
    MoveAnalysisResult? cachedHintResult,
  }) async {
    assert(
      mode == AnalysisOverlayMode.hint ||
          (hintCacheKey == null && cachedHintResult == null),
      'Only hint searches may use the best-move hint cache.',
    );
    assert(
      cachedHintResult == null || hintCacheKey != null,
      'A cached hint result needs a cache key.',
    );
    final int searchGeneration = ++_analysisSearchGeneration;
    if (mode == AnalysisOverlayMode.hint) {
      AnalysisMode.enable(
        cachedHintResult == null
            ? const <MoveAnalysisResult>[]
            : <MoveAnalysisResult>[cachedHintResult],
        mode: AnalysisOverlayMode.hint,
        source: AnalysisSource.engine,
        isAnalyzing: true,
      );
    }
    // Exactly one engine search may run at a time (see the
    // NativeMillGameSession `_searchInFlight` tripwire).  A previous pass
    // keeps draining after `nativeMillSearchStop()` because the Rust-side
    // abort is asynchronous, so request a stop and wait for it to fully
    // unwind before starting this pass.  The generation bump above already
    // detaches the draining pass from publishing.  When several requests
    // pile up here, the newest generation wins and older ones return.
    while (_activeEngineAnalysis != null) {
      if (searchGeneration != _analysisSearchGeneration) {
        return false;
      }
      final Future<void> drainingPass = _activeEngineAnalysis!;
      tgf.nativeMillSearchStop();
      await drainingPass;
    }
    if (searchGeneration != _analysisSearchGeneration) {
      return false;
    }
    final int requestedLineCount = math.max(
      1,
      requestedLineCountOverride ?? AnalysisMode.engineLineCount,
    );
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
    final int searchDepth = searchDepthOverride ?? _analysisSearchDepth;
    final int moveLimitMs =
        moveLimitMsOverride ??
        (isDeepSearch
            ? AnalysisMode.maxEngineSearchTimeMs
            : AnalysisMode.engineSearchTimeMs);
    final bool isDeepEngineAnalysis =
        mode == AnalysisOverlayMode.analysis &&
        moveLimitMs == AnalysisMode.maxEngineSearchTimeMs;
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
        return false;
      }
      searchSession = temporarySession;
    }

    final Completer<void> activeEngineAnalysis = Completer<void>();
    _activeEngineAnalysis = activeEngineAnalysis.future;
    _activeEngineAnalysisMode = mode;
    if (mode != AnalysisOverlayMode.hint) {
      AnalysisMode.setAnalyzing(true);
    }
    bool published = false;
    MoveAnalysisResult? protectedCachedHintResult = cachedHintResult;

    bool publishVariations(
      List<NativeMillPrincipalVariation> variations, {
      bool isAnalyzing = false,
    }) {
      if (variations.isEmpty) {
        return false;
      }
      if (mode == AnalysisOverlayMode.hint) {
        assert(hintCacheKey != null, 'Hint search needs a cache key.');
        final NativeMillPrincipalVariation bestVariation = variations
            .firstWhere(
              (NativeMillPrincipalVariation variation) => variation.rank == 1,
              orElse: () => variations.first,
            );
        final MoveAnalysisResult currentHint = _resultFromVariation(
          bestVariation,
        );
        final MoveAnalysisResult? protectedHint = protectedCachedHintResult;
        if (protectedHint != null &&
            currentHint.move == protectedHint.move &&
            _isDeeperEngineResult(protectedHint, currentHint)) {
          return false;
        }
        // A changed best move is useful immediately, even at a shallower
        // depth. If the move is unchanged, reaching the cached depth releases
        // the protection and normal progressive updates resume.
        protectedCachedHintResult = null;
        _bestMoveHintCache = _BestMoveHintCacheEntry(
          hintCacheKey!,
          currentHint,
        );
      }
      _publishEngineVariations(
        variations,
        isThreatMode: isThreatMode,
        mode: mode,
        isAnalyzing: isAnalyzing,
        baseResults: baseResults,
        baseTrapMoves: baseTrapMoves,
        previousEngineLines: previousEngineLines,
        isDeepEngineAnalysis: isDeepEngineAnalysis,
      );
      return true;
    }

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
              published =
                  publishVariations(current, isAnalyzing: true) || published;
            },
          );
      if (searchGeneration != _analysisSearchGeneration) {
        return false;
      }
      if (variations.isEmpty) {
        if (!published && cachedHintResult == null && context.mounted) {
          _showSnackBar(context, S.of(context).noMoreHintsAvailable);
        }
        if (mode == AnalysisOverlayMode.hint && cachedHintResult == null) {
          AnalysisMode.disable();
        }
        return cachedHintResult != null;
      }
      publishVariations(variations);
      return true;
    } catch (e, st) {
      if (searchGeneration == _analysisSearchGeneration) {
        logger.e("$_logTag Engine MultiPV analysis failed: $e", stackTrace: st);
        if (mode == AnalysisOverlayMode.hint &&
            !published &&
            cachedHintResult == null) {
          AnalysisMode.disable();
        }
      }
      return mode == AnalysisOverlayMode.hint &&
          (published || cachedHintResult != null);
    } finally {
      temporarySession?.dispose();
      if (identical(_activeEngineAnalysis, activeEngineAnalysis.future)) {
        _activeEngineAnalysis = null;
        _activeEngineAnalysisMode = null;
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
    AnalysisOverlayMode mode = AnalysisOverlayMode.analysis,
    bool isAnalyzing = false,
    List<MoveAnalysisResult>? baseResults,
    List<String> baseTrapMoves = const <String>[],
    List<MoveAnalysisResult> previousEngineLines = const <MoveAnalysisResult>[],
    required bool isDeepEngineAnalysis,
  }) {
    final List<MoveAnalysisResult> currentEngineResults = variations
        .map(_resultFromVariation)
        .toList(growable: false);
    final List<MoveAnalysisResult> engineResults = _preferDeeperEngineResults(
      currentEngineResults,
      previousEngineLines,
    );
    final bool hasBaseResults = baseResults != null;
    AnalysisMode.enable(
      baseResults ?? engineResults,
      lineResults: hasBaseResults ? engineResults : null,
      trapMoves: hasBaseResults ? baseTrapMoves : const <String>[],
      source: hasBaseResults
          ? AnalysisSource.perfectDatabaseAndEngine
          : AnalysisSource.engine,
      mode: mode,
      isThreatMode: isThreatMode,
      isEngineAnalysisDeep: isDeepEngineAnalysis,
      isAnalyzing: isAnalyzing,
    );
  }

  static List<MoveAnalysisResult> _preferDeeperEngineResults(
    List<MoveAnalysisResult> currentResults,
    List<MoveAnalysisResult> previousResults,
  ) {
    if (previousResults.isEmpty) {
      return currentResults;
    }
    if (currentResults.isEmpty) {
      return previousResults;
    }
    final Map<int, MoveAnalysisResult> previousByRank =
        <int, MoveAnalysisResult>{};
    final Map<String, MoveAnalysisResult> previousByMove =
        <String, MoveAnalysisResult>{};
    for (final MoveAnalysisResult previous in previousResults) {
      final int? rank = previous.rank;
      if (rank != null) {
        previousByRank[rank] = previous;
      }
      previousByMove[previous.move] = previous;
    }

    final Set<int> currentRanks = <int>{};
    final List<MoveAnalysisResult> merged = <MoveAnalysisResult>[];
    for (final MoveAnalysisResult current in currentResults) {
      final int? rank = current.rank;
      if (rank != null) {
        currentRanks.add(rank);
      }
      final MoveAnalysisResult? previous = rank == null
          ? previousByMove[current.move]
          : previousByRank[rank];
      merged.add(
        _isDeeperEngineResult(previous, current) ? previous! : current,
      );
    }

    for (final MoveAnalysisResult previous in previousResults) {
      final int? rank = previous.rank;
      if (rank != null && !currentRanks.contains(rank)) {
        merged.add(previous);
      }
    }
    merged.sort(_compareEngineLineResults);
    return merged;
  }

  static int _compareEngineLineResults(
    MoveAnalysisResult a,
    MoveAnalysisResult b,
  ) {
    const int noRank = 1 << 30;
    final int rankOrder = (a.rank ?? noRank).compareTo(b.rank ?? noRank);
    if (rankOrder != 0) {
      return rankOrder;
    }
    return a.move.compareTo(b.move);
  }

  static bool _isDeeperEngineResult(
    MoveAnalysisResult? previous,
    MoveAnalysisResult current,
  ) {
    if (previous == null) {
      return false;
    }
    final int previousDepth = previous.depth ?? 0;
    final int currentDepth = current.depth ?? 0;
    if (previousDepth != currentDepth) {
      return previousDepth > currentDepth;
    }
    final int previousNodes = previous.nodes ?? 0;
    final int currentNodes = current.nodes ?? 0;
    return previousNodes > currentNodes;
  }

  static MoveAnalysisResult _resultFromVariation(
    NativeMillPrincipalVariation variation,
  ) {
    return MoveAnalysisResult(
      move: variation.move,
      outcome: _engineOutcome(variation.score),
      rank: variation.rank,
      depth: variation.depth,
      nodes: variation.nodes,
      nodesPerSecond: variation.nodesPerSecond,
      line: variation.line,
    );
  }

  static void _stopCurrentEngineAnalysis() {
    _analysisSearchGeneration++;
    tgf.nativeMillSearchStop();
  }

  /// Whether a continuously deepening best-move hint is still searching.
  static bool get isBestMoveHintSearching => _isBestMoveHintSearching;

  /// Stop any engine pass owned by the current analysis view.
  ///
  /// Full-analysis results stay visible, but their in-progress state is
  /// cleared. Hint results are removed because a hint belongs to the board
  /// position and view that requested it.
  static void stopActiveEngineAnalysis() {
    final bool isHintSearch =
        _isBestMoveHintSearching ||
        AnalysisMode.isHint ||
        _activeEngineAnalysisMode == AnalysisOverlayMode.hint;
    if (isHintSearch) {
      stopBestMoveHint();
      return;
    }
    if (_activeEngineAnalysis != null || AnalysisMode.isAnalyzing) {
      _stopCurrentEngineAnalysis();
    }
    AnalysisMode.setAnalyzing(false);
  }

  /// Stop any current engine pass and wait for the native session to drain.
  static Future<void> stopActiveEngineAnalysisAndWait() async {
    final Future<void>? activeSearch = _activeEngineAnalysis;
    stopActiveEngineAnalysis();
    if (activeSearch != null) {
      await activeSearch;
    }
  }

  /// Stop a running hint search and remove its board overlay.
  static void stopBestMoveHint() {
    final bool hasPendingHintRequest = _isBestMoveHintSearching;
    final bool hasActiveHintSearch =
        _activeEngineAnalysisMode == AnalysisOverlayMode.hint;
    if (!hasPendingHintRequest &&
        !AnalysisMode.isHint &&
        !hasActiveHintSearch) {
      return;
    }
    if (hasPendingHintRequest) {
      _isBestMoveHintSearching = false;
      AnalysisMode.stateNotifier.removeListener(
        _stopHintSearchWhenOverlayIsCleared,
      );
    }
    if (hasPendingHintRequest || hasActiveHintSearch) {
      _stopCurrentEngineAnalysis();
    }
    AnalysisMode.disable();
  }

  /// Forget the reusable hint for the previous position.
  ///
  /// Turning the lamp off deliberately does not call this method: pressing it
  /// again on the unchanged position should display the last deepest result
  /// immediately. Position/session owners must invalidate after a move, reset,
  /// or disposal so returning to an old FEN does not resurrect stale advice.
  static void invalidateBestMoveHintCache() {
    _bestMoveHintCache = null;
  }

  /// Stop the hint and wait until its native search releases the session.
  ///
  /// Call this before another action starts an engine search or mutates the
  /// current position. The Rust abort signal is asynchronous, so clearing the
  /// overlay alone is not enough to make a second search safe.
  static Future<void> stopBestMoveHintAndWait() async {
    final bool hasHintRequest =
        _isBestMoveHintSearching ||
        AnalysisMode.isHint ||
        _activeEngineAnalysisMode == AnalysisOverlayMode.hint;
    final Future<void>? activeSearch = hasHintRequest
        ? _activeEngineAnalysis
        : null;
    stopBestMoveHint();
    if (activeSearch != null) {
      await activeSearch;
    }
  }

  static void _stopHintSearchWhenOverlayIsCleared() {
    if (!_isBestMoveHintSearching || AnalysisMode.isHint) {
      return;
    }
    _isBestMoveHintSearching = false;
    AnalysisMode.stateNotifier.removeListener(
      _stopHintSearchWhenOverlayIsCleared,
    );
    _stopCurrentEngineAnalysis();
  }

  /// Continuously deepen a single best-move hint without applying the move.
  static Future<bool> showBestMoveHint(BuildContext context) async {
    assert(
      !AnalysisMode.isAnalyzing,
      'Cannot request a hint while another analysis pass is running.',
    );
    if (AnalysisMode.isAnalyzing || _isBestMoveHintSearching) {
      return false;
    }

    final NativeMillGameSession? session = _activeNativeSession(context);
    if (session == null) {
      logger.w("$_logTag No active native Mill session to hint.");
      return false;
    }

    final _BestMoveHintCacheKey hintCacheKey = _bestMoveHintCacheKey(session);
    final _BestMoveHintCacheEntry? cacheEntry = _bestMoveHintCache;
    final MoveAnalysisResult? cachedHintResult =
        cacheEntry != null && cacheEntry.key == hintCacheKey
        ? cacheEntry.result
        : null;
    if (cacheEntry != null && cachedHintResult == null) {
      invalidateBestMoveHintCache();
    }

    _isBestMoveHintSearching = true;
    AnalysisMode.stateNotifier.addListener(_stopHintSearchWhenOverlayIsCleared);
    try {
      return await _enableEngineMultiPvAnalysis(
        context,
        session,
        mode: AnalysisOverlayMode.hint,
        requestedLineCountOverride: 1,
        searchDepthOverride: _hintSearchDepth,
        moveLimitMsOverride: _hintSearchTimeMs,
        hintCacheKey: hintCacheKey,
        cachedHintResult: cachedHintResult,
      );
    } finally {
      if (_isBestMoveHintSearching) {
        _isBestMoveHintSearching = false;
        AnalysisMode.stateNotifier.removeListener(
          _stopHintSearchWhenOverlayIsCleared,
        );
      }
    }
  }

  static NativeMillGameSession? _activeNativeSession(BuildContext context) {
    final Object? session = GameSessionScope.sessionOf(context);
    if (session is NativeMillGameSession) {
      return session;
    }
    return GameController().activeNativeMillSession;
  }

  static _BestMoveHintCacheKey _bestMoveHintCacheKey(
    NativeMillGameSession session,
  ) {
    final GeneralSettings settings = DB().generalSettings;
    return _BestMoveHintCacheKey(
      fen: session.getFen().trim(),
      positionSnapshot: session.state.value,
      ruleSettingsJson: jsonEncode(DB().ruleSettings.toJson()),
      usePerfectDatabase: settings.usePerfectDatabase,
      patchMakeTraps: settings.patchMakeTraps,
      considerMobility: settings.considerMobility,
      focusOnBlockingPaths: settings.focusOnBlockingPaths,
      engineThreads: settings.engineThreads,
    );
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

@immutable
class _BestMoveHintCacheKey {
  const _BestMoveHintCacheKey({
    required this.fen,
    required this.positionSnapshot,
    required this.ruleSettingsJson,
    required this.usePerfectDatabase,
    required this.patchMakeTraps,
    required this.considerMobility,
    required this.focusOnBlockingPaths,
    required this.engineThreads,
  });

  final String fen;
  final Object positionSnapshot;
  final String ruleSettingsJson;
  final bool usePerfectDatabase;
  final bool patchMakeTraps;
  final bool considerMobility;
  final bool focusOnBlockingPaths;
  final int engineThreads;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _BestMoveHintCacheKey &&
            other.fen == fen &&
            identical(other.positionSnapshot, positionSnapshot) &&
            other.ruleSettingsJson == ruleSettingsJson &&
            other.usePerfectDatabase == usePerfectDatabase &&
            other.patchMakeTraps == patchMakeTraps &&
            other.considerMobility == considerMobility &&
            other.focusOnBlockingPaths == focusOnBlockingPaths &&
            other.engineThreads == engineThreads;
  }

  @override
  int get hashCode => Object.hash(
    fen,
    positionSnapshot,
    ruleSettingsJson,
    usePerfectDatabase,
    patchMakeTraps,
    considerMobility,
    focusOnBlockingPaths,
    engineThreads,
  );
}

@immutable
class _BestMoveHintCacheEntry {
  const _BestMoveHintCacheEntry(this.key, this.result);

  final _BestMoveHintCacheKey key;
  final MoveAnalysisResult result;
}
