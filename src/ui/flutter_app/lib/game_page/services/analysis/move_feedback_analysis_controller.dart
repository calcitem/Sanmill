// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../game_platform/game_session.dart';
import '../../../games/mill/mill_action_codec.dart';
import '../../../games/mill/native_mill_game_session.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../src/rust/api/simple.dart' as tgf;
import '../../services/import_export/pgn.dart';
import '../../services/mill.dart';
import 'move_feedback.dart';
import 'move_feedback_native_adapter.dart';

enum MoveFeedbackAnalysisStatus { idle, loading, ready, error }

@immutable
class MoveFeedbackLineMove {
  const MoveFeedbackLineMove({required this.move, required this.side});

  final String move;
  final PieceColor side;
}

@immutable
class MoveFeedbackAnalysisState {
  const MoveFeedbackAnalysisState({
    this.status = MoveFeedbackAnalysisStatus.idle,
    this.result,
    this.selectedNode,
    this.feedbackNode,
    this.bestLine = const <MoveFeedbackLineMove>[],
    this.error,
  });

  final MoveFeedbackAnalysisStatus status;
  final MoveFeedbackResult? result;
  final PgnNode<ExtMove>? selectedNode;
  final PgnNode<ExtMove>? feedbackNode;
  final List<MoveFeedbackLineMove> bestLine;
  final Object? error;
}

/// Owns cancellation, generation checks, and rule-fingerprint cache isolation.
class MoveFeedbackAnalysisController extends ChangeNotifier {
  static const int _searchDepth = 24;
  static const int _moveLimitMs = 200;
  static const int _maximumCacheEntries = 128;

  final LinkedHashMap<String, _CachedMoveFeedback> _cache =
      LinkedHashMap<String, _CachedMoveFeedback>();
  int _generation = 0;
  bool _searching = false;
  MoveFeedbackAnalysisState _state = const MoveFeedbackAnalysisState();

  MoveFeedbackAnalysisState get state => _state;

  Future<void> analyze({
    required GameRecorder recorder,
    required PgnNode<ExtMove> selectedNode,
    required RuleSettings rules,
    required GeneralSettings generalSettings,
  }) async {
    assert(selectedNode.data != null, 'Feedback requires a played move node.');
    if (selectedNode.data == null) {
      clear();
      return;
    }
    final int generation = ++_generation;
    final List<PgnNode<ExtMove>> selectedPath = _pathTo(selectedNode);
    final int selectedIndex = selectedPath.indexOf(selectedNode);
    assert(selectedIndex >= 0);
    final PieceColor side = selectedNode.data!.side;
    int turnStart = selectedIndex;
    while (turnStart > 0 && selectedPath[turnStart - 1].data?.side == side) {
      turnStart--;
    }
    final List<PgnNode<ExtMove>> turnNodes = selectedPath.sublist(turnStart);
    PgnNode<ExtMove> continuation = selectedNode;
    while (continuation.children.isNotEmpty &&
        continuation.children.first.data?.side == side) {
      continuation = continuation.children.first;
      turnNodes.add(continuation);
    }
    final List<PgnNode<ExtMove>> prefixNodes = selectedPath.sublist(
      0,
      turnStart,
    );
    final String cacheKey = _cacheKey(
      recorder: recorder,
      prefixNodes: prefixNodes,
      turnNodes: turnNodes,
      rules: rules,
      generalSettings: generalSettings,
    );
    final _CachedMoveFeedback? cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      _publish(
        MoveFeedbackAnalysisState(
          status: MoveFeedbackAnalysisStatus.ready,
          result: cached.result,
          selectedNode: selectedNode,
          feedbackNode: turnNodes[cached.feedbackNodeIndex],
          bestLine: cached.bestLine,
        ),
      );
      return;
    }

    _publish(
      MoveFeedbackAnalysisState(
        status: MoveFeedbackAnalysisStatus.loading,
        selectedNode: selectedNode,
      ),
    );
    final NativeMillGameSession session = NativeMillGameSession(
      rules: rules,
      generalSettings: _engineSettings(generalSettings),
    );
    try {
      final String? setupFen = recorder.setupPosition?.trim();
      if (setupFen != null &&
          setupFen.isNotEmpty &&
          !session.loadFen(setupFen)) {
        throw StateError('Analysis recorder carries an invalid initial FEN.');
      }
      for (final PgnNode<ExtMove> prefix in prefixNodes) {
        if (!session.applyMoveString(prefix.data!.move)) {
          throw StateError('Cannot replay analysis move ${prefix.data!.move}.');
        }
      }

      final List<MoveFeedbackResult> atomicResults = <MoveFeedbackResult>[];
      final List<List<MoveFeedbackLineMove>> atomicBestLines =
          <List<MoveFeedbackLineMove>>[];
      for (final PgnNode<ExtMove> turnNode in turnNodes) {
        if (generation != _generation) {
          return;
        }
        final String playedMove = turnNode.data!.move;
        final int legalCount = session.legalActions.length;
        if (legalCount == 0 ||
            legalCount > tgf.nativeMillSearchActionCapacity()) {
          throw StateError('Feedback root action count is unsupported.');
        }
        _searching = true;
        final List<NativeMillPrincipalVariation> variations = await session
            .searchPrincipalVariations(
              depth: _searchDepth,
              moveLimitMs: _moveLimitMs,
              multiPv: legalCount,
              engineSettings: _engineSettings(generalSettings),
            );
        _searching = false;
        if (generation != _generation) {
          return;
        }
        if (variations.isEmpty) {
          throw StateError('The feedback engine returned no candidates.');
        }
        final NativeMillPrincipalVariation played = variations.firstWhere(
          (NativeMillPrincipalVariation variation) =>
              variation.move == playedMove,
          orElse: () => throw StateError(
            'Played move is not present in feedback MultiPV: $playedMove',
          ),
        );
        final int perspective =
            session.state.value.activeSeat == PlayerSeat.first ? 1 : -1;
        final List<NativeMillPrincipalVariation> ordered =
            List<NativeMillPrincipalVariation>.from(variations)..sort(
              (
                NativeMillPrincipalVariation a,
                NativeMillPrincipalVariation b,
              ) => a.rank.compareTo(b.rank),
            );
        final MoveFeedbackExactScores? exact = moveFeedbackExactScores(
          session.analyzePerfectDb(),
          playedMove: playedMove,
          legalActionCount: legalCount,
        );
        final NativeMillPrincipalVariation bestVariation = exact == null
            ? ordered.first
            : ordered.firstWhere(
                (NativeMillPrincipalVariation variation) =>
                    exact.bestMoves.contains(variation.move),
                orElse: () => ordered.first,
              );
        final int bestScore =
            exact?.bestScore ?? ordered.first.score * perspective;
        final int playedScore =
            exact?.playedScore ?? played.score * perspective;
        final MoveFeedbackEvidence evidence = moveFeedbackEvidenceFromNative(
          session.feedbackEvidenceForMove(playedMove, variations),
        );
        final MoveFeedbackResult result =
            MoveFeedbackClassifier.classify(
              MoveFeedbackInput(
                bestScore: bestScore,
                playedScore: playedScore,
                playedRank: played.rank,
                legalRootActionCount: legalCount,
                depth: played.depth,
                runnerUpScore:
                    exact?.runnerUpScore ??
                    (ordered.length > 1
                        ? ordered[1].score * perspective
                        : null),
                searchStable: variations.every(
                  (NativeMillPrincipalVariation variation) =>
                      variation.depth == played.depth,
                ),
                candidateCoverageComplete: variations.length == legalCount,
                allCandidatesLosing:
                    exact?.allCandidatesLosing ??
                    variations.every(
                      (NativeMillPrincipalVariation variation) =>
                          variation.score * perspective <=
                          -MoveQualityThresholds.engineTerminalScore,
                    ),
                source: exact == null
                    ? MoveFeedbackSource.engine
                    : MoveFeedbackSource.perfectDatabase,
                evidence: evidence,
                strategicReasons: moveFeedbackStrategicReasons(evidence),
              ),
            ).copyWith(
              bestMove: bestVariation.move,
              principalVariation: List<String>.unmodifiable(bestVariation.line),
            );
        atomicResults.add(result);
        atomicBestLines.add(
          _lineWithSides(
            rootFen: session.getFen(),
            line: bestVariation.line.isEmpty
                ? <String>[bestVariation.move]
                : bestVariation.line,
            rules: rules,
            generalSettings: generalSettings,
          ),
        );
        if (!session.applyMoveString(playedMove)) {
          throw StateError('Cannot apply feedback move $playedMove.');
        }
      }

      if (generation != _generation) {
        return;
      }
      final MoveFeedbackResult aggregate = MoveFeedbackClassifier.aggregateTurn(
        atomicResults,
      );
      final int aggregateIndex = atomicResults.indexOf(aggregate);
      final int feedbackNodeIndex = aggregateIndex >= 0 ? aggregateIndex : 0;
      final List<MoveFeedbackLineMove> bestLine =
          atomicBestLines[feedbackNodeIndex];
      final _CachedMoveFeedback value = _CachedMoveFeedback(
        result: aggregate,
        feedbackNodeIndex: feedbackNodeIndex,
        bestLine: bestLine,
      );
      _cache[cacheKey] = value;
      while (_cache.length > _maximumCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      _publish(
        MoveFeedbackAnalysisState(
          status: MoveFeedbackAnalysisStatus.ready,
          result: aggregate,
          selectedNode: selectedNode,
          feedbackNode: turnNodes[feedbackNodeIndex],
          bestLine: bestLine,
        ),
      );
    } on Object catch (error) {
      if (generation == _generation) {
        _publish(
          MoveFeedbackAnalysisState(
            status: MoveFeedbackAnalysisStatus.error,
            selectedNode: selectedNode,
            error: error,
          ),
        );
      }
    } finally {
      _searching = false;
      session.dispose();
    }
  }

  void cancel() {
    _generation++;
    if (_searching) {
      tgf.nativeMillSearchStop();
    }
    _searching = false;
  }

  void clear() {
    cancel();
    _publish(const MoveFeedbackAnalysisState());
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void _publish(MoveFeedbackAnalysisState state) {
    _state = state;
    notifyListeners();
  }

  static List<PgnNode<ExtMove>> _pathTo(PgnNode<ExtMove> node) {
    final List<PgnNode<ExtMove>> path = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? current = node;
    while (current != null && current.data != null) {
      path.insert(0, current);
      current = current.parent;
    }
    return path;
  }

  static GeneralSettings _engineSettings(GeneralSettings settings) =>
      settings.copyWith(
        searchAlgorithm: SearchAlgorithm.pvs,
        aiIsLazy: false,
        skillLevel: 30,
        resignIfMostLose: false,
        shufflingEnabled: false,
        useLazySmp: false,
        engineThreads: 1,
      );

  static String _cacheKey({
    required GameRecorder recorder,
    required List<PgnNode<ExtMove>> prefixNodes,
    required List<PgnNode<ExtMove>> turnNodes,
    required RuleSettings rules,
    required GeneralSettings generalSettings,
  }) => jsonEncode(<String, Object?>{
    'setup': recorder.setupPosition ?? '',
    'prefix': prefixNodes
        .map((PgnNode<ExtMove> node) => node.data!.move)
        .toList(),
    'turn': turnNodes.map((PgnNode<ExtMove> node) => node.data!.move).toList(),
    'rules': rules.toJson(),
    'engine': tgf.tgfVersion(),
    'mobility': generalSettings.considerMobility,
    'blocking': generalSettings.focusOnBlockingPaths,
  });

  static List<MoveFeedbackLineMove> _lineWithSides({
    required String rootFen,
    required List<String> line,
    required RuleSettings rules,
    required GeneralSettings generalSettings,
  }) {
    final NativeMillGameSession replay = NativeMillGameSession(
      rules: rules,
      generalSettings: _engineSettings(generalSettings),
    );
    try {
      if (!replay.loadFen(rootFen)) {
        return const <MoveFeedbackLineMove>[];
      }
      final List<MoveFeedbackLineMove> moves = <MoveFeedbackLineMove>[];
      for (final String move in line) {
        final PieceColor side =
            replay.state.value.activeSeat == PlayerSeat.first
            ? PieceColor.white
            : PieceColor.black;
        final bool legal = replay.legalActions.any(
          (GameAction action) => MillActionCodec.moveStringFrom(action) == move,
        );
        if (!legal || !replay.applyMoveString(move)) {
          break;
        }
        moves.add(MoveFeedbackLineMove(move: move, side: side));
      }
      return List<MoveFeedbackLineMove>.unmodifiable(moves);
    } finally {
      replay.dispose();
    }
  }
}

@immutable
class _CachedMoveFeedback {
  const _CachedMoveFeedback({
    required this.result,
    required this.feedbackNodeIndex,
    required this.bestLine,
  });

  final MoveFeedbackResult result;
  final int feedbackNodeIndex;
  final List<MoveFeedbackLineMove> bestLine;
}
