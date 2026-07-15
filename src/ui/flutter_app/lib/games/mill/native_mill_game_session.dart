// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Rust-native Mill GameSession.
//
// This is the production Mill session backed by `NativeMillRulesPort` and
// therefore by `crates/tgf-mill` through the typed FRB `TgfKernel`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_page/services/mill.dart' show ExtMove, PieceColor;
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
// #region agent log
import '../../shared/services/debug_instrumentation_bb5e74.dart';
// #endregion
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../src/rust/api/kernel.dart' as tgf_kernel;
import '../../src/rust/api/simple.dart' as tgf;
import 'lan_session_meta.dart';
import 'mill_action_codec.dart';
import 'mill_marked_pieces_codec.dart';
import 'mill_remote_session_meta.dart';
import 'mill_types.dart';
import 'native_mill_rules_port.dart';
import 'native_mill_snapshot_board_view.dart';

const String _logTag = '[NativeMillGameSession]';

@immutable
class NativeMillPrincipalVariation {
  const NativeMillPrincipalVariation({
    required this.rank,
    required this.move,
    required this.score,
    required this.nodes,
    required this.depth,
    this.nodesPerSecond,
    this.line = const <String>[],
  });

  final int rank;
  final String move;
  final int score;
  final int nodes;
  final int depth;
  final int? nodesPerSecond;
  final List<String> line;
}

class NativeMillGameSession implements GameSessionHandle {
  factory NativeMillGameSession({
    NativeMillRulesPort? rulesPort,
    RuleSettings? rules,
    GeneralSettings? generalSettings,
    LanSessionMeta? lanMeta,
  }) {
    final NativeMillRulesPort port =
        rulesPort ??
        NativeMillRulesPort(
          ruleSettings: rules ?? const RuleSettings(),
          generalSettings: generalSettings,
        );
    return NativeMillGameSession.fromPort(port, lanMeta: lanMeta);
  }

  // Named constructor for subclasses; callers outside this class should use
  // the factory constructor or this named form when subclassing.
  NativeMillGameSession.fromPort(this.rulesPort, {LanSessionMeta? lanMeta})
    : remoteMeta = lanMeta,
      activeRuleSettings = rulesPort.ruleSettings,
      _state = ValueNotifier<GameStateSnapshot>(rulesPort.snapshot);

  NativeMillRulesPort rulesPort;
  MillRemoteSessionMeta? remoteMeta;
  RuleSettings activeRuleSettings;

  LanSessionMeta? get lanMeta {
    final MillRemoteSessionMeta? meta = remoteMeta;
    return meta is LanSessionMeta ? meta : null;
  }

  set lanMeta(LanSessionMeta? value) {
    remoteMeta = value;
  }

  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast(sync: true);
  bool _disposed = false;
  GameAction? _lastSearchLegalAction;

  /// FEN / native Zobrist captured the moment the most recent engine
  /// `bestMove` was validated as legal in [_legalActionForBestMove].  These
  /// are compared against the live kernel state if a later apply is rejected,
  /// so the release-visible engine-failure report can show whether the
  /// position changed under the in-flight search (the stale-snapshot race)
  /// rather than only reporting a generic "no best move".
  String? _lastSearchValidatedFen;
  int? _lastSearchValidatedZobrist;

  /// Precise, release-visible diagnostics for the most recent engine-move
  /// rejection (illegal at validation time, or rejected by the kernel on
  /// apply).  Surfaced verbatim by [EngineFailureDialog] so a crash report
  /// pinpoints the cause instead of the generic
  /// "AI engine failed to produce a move".  Reset at the start of every
  /// [searchBestAction] so stale diagnostics never leak into a later report.
  String? _lastEngineFailureDetails;

  /// True while a [searchBestAction] call is in flight on this session.
  /// Exactly one engine search may run at a time; see the assert in
  /// [searchBestAction] for the rationale.
  bool _searchInFlight = false;

  /// True while a session-level terminal result (resignation / timeout /
  /// abandonment) is overlaid on top of the Rust kernel state.  Cleared by
  /// the next real kernel transition (every [_setState] call that is not a
  /// forced terminal).  See [forceTerminal].
  bool _forcedTerminal = false;

  AiMoveType lastAiMoveType = AiMoveType.unknown;
  int? lastAiBestValue;
  HumanDatabaseMoveStats? lastHumanDatabaseMoveStats;

  static final RegExp _aimovetypePattern = RegExp(
    r'(?:^|\s)aimovetype=(\w+)(?:\s|$)',
  );

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions {
    if (_disposed || outcome.isTerminal) {
      return const <GameAction>[];
    }
    return rulesPort.legalActions;
  }

  /// Precise diagnostics for the most recent engine-move rejection on this
  /// session, or null if none has occurred since the last search.  Shown in
  /// the release engine-failure dialog / crash report via
  /// [GameController.buildEngineFailureDiagnosticContext] so the stale-snapshot
  /// race can be confirmed from a user-submitted report.
  String? get lastEngineFailureDetails => _lastEngineFailureDetails;

  @override
  GameOutcome get outcome => _state.value.outcome;

  int get undoDepth => rulesPort.undoDepth;

  int get redoDepth => rulesPort.redoDepth;

  // -------------------------------------------------------- setup-position API

  /// Reset the game to the initial state (all pieces in hand, empty board,
  /// White to move).  Called by [GameController.reset] when "New Game" is
  /// triggered so that the native Rust kernel is in sync with the UI facade.
  void resetGame({RuleSettings? rules, GeneralSettings? generalSettings}) {
    if (_disposed) {
      return;
    }
    lastAiMoveType = AiMoveType.unknown;
    lastAiBestValue = null;
    lastHumanDatabaseMoveStats = null;
    if (rules != null) {
      final NativeMillRulesPort nextPort = NativeMillRulesPort(
        ruleSettings: rules,
        generalSettings: generalSettings,
      );
      rulesPort.dispose();
      rulesPort = nextPort;
      activeRuleSettings = rules;
      _setState(rulesPort.snapshot);
      return;
    }
    // setupClear resets the kernel to an empty board with all pieces in hand.
    // setupFinish transitions that state to a playable placing-phase position.
    rulesPort.setupClear();
    final GameStateSnapshot next = rulesPort.setupFinish();
    _setState(next);
  }

  /// Clear the board for setup-position editing.
  void setupClear() {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupClear();
    _setState(next);
  }

  /// Place or clear one piece at [node] during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  void setupSetPiece(int node, int owner) {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupSetPiece(node, owner);
    _setState(next);
  }

  /// Set the side to move during setup editing. [side]: 0 or 1.
  void setupSetSide(int side) {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupSetSide(side);
    _setState(next);
  }

  /// Finish setup editing and transition to a playable game state.
  void setupFinish() {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupFinish();
    _setState(next);
  }

  /// Load a board position from a Mill FEN string via the native Rust kernel.
  ///
  /// Returns true if the FEN was valid and loaded; false otherwise.
  bool loadFen(String fen) {
    if (_disposed) {
      return false;
    }
    try {
      final GameStateSnapshot next = rulesPort.setFromFen(fen);
      _setState(next);
      return true;
    } on Object {
      return false;
    }
  }

  /// The legacy `Position`-backed FEN parser used to provide a
  /// fallback when the Rust kernel rejected an extended FEN.  The
  /// rule-machine cleanup deleted the legacy parser; the Rust
  /// kernel is the only path now.  This stub is kept for compat
  /// with any caller that still references it; it always returns
  /// false (i.e. "no fallback succeeded").
  bool loadFenLegacyFallback(String fen) {
    return false;
  }

  /// Export the current kernel state as a Mill FEN string.
  String getFen() {
    if (_disposed) {
      return '';
    }
    return rulesPort.exportFen();
  }

  /// Overlay a session-level terminal result that the Rust rule machine
  /// cannot derive on its own (resignation, human-clock timeout, or other
  /// abandonment).
  ///
  /// Mirrors the legacy `Position.setGameOver(winner, reason)` override:
  /// the board payload is left untouched, only the reported [outcome] and
  /// the [millOutcomeReasonPayloadKey] entry change, so shared UI (result
  /// dialog, score tally, ELO) observes a terminal state.  The board view
  /// keeps rendering the real position underneath.
  ///
  /// The override is cleared automatically by the next real kernel
  /// transition (apply / undo / redo / reset / setup / loadFen): all of
  /// those route through [_setState] without the forced-terminal flag.
  void forceTerminal(GameOutcome outcome, {String? reason}) {
    if (_disposed) {
      return;
    }
    assert(
      outcome.isTerminal,
      'forceTerminal requires a terminal outcome; got ${outcome.kind}.',
    );
    final GameStateSnapshot current = _state.value;
    _setState(
      GameStateSnapshot(
        gameId: current.gameId,
        activeSeat: current.activeSeat,
        outcome: outcome,
        phase: current.phase,
        lastAction: current.lastAction,
        payload: <String, Object?>{
          ...current.payload,
          millOutcomeReasonPayloadKey: ?reason,
        },
      ),
      forcedTerminal: true,
    );
  }

  /// Analyse the current position, returning one verdict per legal move plus
  /// detected trap moves (empty when the session is terminal/disposed or the
  /// active rule variant is unsupported).  Backs the analysis overlay.
  tgf.MillAnalysisReport analyzePerfectDb() {
    if (_disposed || outcome.isTerminal) {
      return const tgf.MillAnalysisReport(
        moves: <tgf.MillMoveAnalysis>[],
        traps: <String>[],
      );
    }
    return rulesPort.analyzePerfectDb();
  }

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  /// The side to move in the current snapshot, as a Mill [PieceColor].
  PieceColor get sideToMove => switch (_state.value.activeSeat) {
    PlayerSeat.first => PieceColor.white,
    PlayerSeat.second => PieceColor.black,
    PlayerSeat.none => PieceColor.nobody,
  };

  /// Applies the legal move identified by [move] (notation form, e.g. "d6",
  /// "d6-e5", "xd6") if it is currently legal.
  ///
  /// Recording is handled by [MillSessionRecorderBridge] which listens for the
  /// emitted `moveApplied` event, so callers do not append to the recorder.
  /// Returns true when a legal move matched and was applied.
  bool applyMoveString(String move) {
    if (_disposed) {
      return false;
    }
    for (final GameAction action in legalActions) {
      if (action.payload['move'] == move) {
        return _applyNow(action);
      }
    }
    return false;
  }

  @override
  Future<void> apply(GameAction action) async {
    _applyNow(action);
  }

  bool _applyNow(GameAction action) {
    if (_disposed || _forcedTerminal) {
      // A forced terminal (resignation / timeout) has ended the game;
      // reject further moves until a real transition (reset / undo /
      // setup / loadFen) clears the override.
      return false;
    }
    lastHumanDatabaseMoveStats = null;
    final bool alreadyMatchedLegalSearchAction = identical(
      action,
      _lastSearchLegalAction,
    );
    _lastSearchLegalAction = null;
    if (!alreadyMatchedLegalSearchAction && !rulesPort.isLegal(action)) {
      _emit(MillEventTypes.moveRejected, <String, Object?>{
        'type': action.type,
        ...action.payload,
      });
      return false;
    }
    final PlayerSeat mover = _state.value.activeSeat;
    final GameStateSnapshot next;
    try {
      next = rulesPort.apply(action);
    } catch (e) {
      // The kernel rejected an action that already passed validation at
      // search time (its isLegal re-check was skipped because it matched the
      // cached search action).  Capture the live-vs-searched state so the
      // release-visible report shows whether the position changed under the
      // in-flight search.  Re-throw: the failure must still surface as an
      // EngineNoBestMove dialog -- this enriches the report, it does not mask.
      _recordEngineFailure(
        stage: 'kernelApply',
        chosenMove: MillActionCodec.moveStringFrom(action) ?? '(unknown)',
        actionType: action.type,
        rejectReason: e.toString(),
        matchedSearchAction: alreadyMatchedLegalSearchAction,
      );
      rethrow;
    }
    final String? boardLayout = _boardLayoutFromSnapshot(next);
    assert(
      boardLayout != null,
      'Native Mill snapshots must carry a tgfPayload board layout.',
    );
    _setState(next);
    _emit(MillEventTypes.moveApplied, <String, Object?>{
      'type': action.type,
      'mover': mover.name,
      'boardLayout': ?boardLayout,
      ...action.payload,
    });
    return true;
  }

  @override
  Future<void> undo() async {
    if (_disposed) {
      return;
    }
    try {
      lastHumanDatabaseMoveStats = null;
      _setState(rulesPort.undo());
      _emit(MillEventTypes.undoApplied, const <String, Object?>{});
    } on Object catch (e) {
      _emit(MillEventTypes.actionIgnored, <String, Object?>{'reason': '$e'});
    }
  }

  @override
  Future<void> redo() async {
    if (_disposed) {
      return;
    }
    try {
      lastHumanDatabaseMoveStats = null;
      _setState(rulesPort.redo());
      _emit(MillEventTypes.redoApplied, const <String, Object?>{});
    } on Object catch (e) {
      _emit(MillEventTypes.actionIgnored, <String, Object?>{'reason': '$e'});
    }
  }

  /// Search from the current Rust kernel state backing this session.  Exposed
  /// as a concrete method (not on [GameSession]) while phase 6 moves
  /// `engine.dart` toward EngineEvent streams.
  ///
  /// When [moveLimitMs] is greater than zero the search is time-bounded.
  Stream<tgf.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
    int multiPv = 1,
  }) {
    return rulesPort.millSearchEvents(
      depth: depth,
      moveLimitMs: moveLimitMs,
      engineSettings: engineSettings,
      multiPv: multiPv,
    );
  }

  /// Search the current kernel state and map the final bestMove event back to
  /// one of this session's current legal actions.  Matching uses the full
  /// UCI notation carried in the event's `reason` field, so place, move, and
  /// removal searches are all unambiguous (see [_legalActionForBestMove]).
  ///
  /// [moveLimitMs]: when > 0, the search is time-bounded (mirrors the legacy
  /// C++ `MoveTime` UCI option).  When 0, depth alone drives termination.
  Future<GameAction?> searchBestAction({
    int depth = 1,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
  }) async {
    if (_disposed || outcome.isTerminal) {
      return null;
    }

    // Serialization tripwire (fail-fast, not a fallback): exactly one engine
    // search may run on a session at a time.  Concurrent searches read the
    // same pre-move snapshot, so the first applies its move and the second's
    // identical bestMove is then rejected by isLegal -- the spurious
    // EngineNoBestMove root cause.  The entry-point guards (TapHandler and
    // GameController.engineToGo isEngineRunning serialization) must prevent
    // this; assert here so any caller that bypasses them fails loudly in
    // debug and tests instead of silently masking a stale move in release.
    assert(
      !_searchInFlight,
      'Concurrent searchBestAction: a second engine search started while one '
      'was already in flight. A caller is missing the isEngineRunning guard.',
    );
    _searchInFlight = true;

    if (EnvironmentConfig.devMode) {
      logger.d(
        '$_logTag searchBestAction: depth=$depth '
        'moveLimitMs=$moveLimitMs phase=${state.value.phase}',
      );
    }

    _lastSearchLegalAction = null;
    _lastEngineFailureDetails = null;
    lastAiBestValue = null;
    GameAction? bestAction;
    int eventCount = 0;
    try {
      await for (final tgf.EngineEvent event in millSearchEvents(
        depth: depth,
        moveLimitMs: moveLimitMs,
        engineSettings: engineSettings,
      )) {
        eventCount++;
        if (EnvironmentConfig.devMode) {
          logger.i(
            '$_logTag search event #$eventCount: kind=${event.kind} '
            'toNode=${event.toNode} score=${event.score} '
            'reason=${event.reason}',
          );
        }
        if (event.kind != 'bestMove' || event.toNode < 0) {
          continue;
        }
        if (_shouldResignFromSearch(event, engineSettings)) {
          final PlayerSeat loser = state.value.activeSeat;
          final PlayerSeat winner = _opponentSeat(loser);
          assert(
            winner != PlayerSeat.none,
            'ResignIfMostLose requires an active player seat.',
          );
          forceTerminal(GameOutcome.win(winner), reason: 'loseResign');
          bestAction = null;
          _lastSearchLegalAction = null;
          continue;
        }
        lastAiMoveType = _aiMoveTypeFromReason(event.reason);
        lastAiBestValue = event.score;
        bestAction = _legalActionForBestMove(event);
        _lastSearchLegalAction = bestAction;
        if (EnvironmentConfig.devMode) {
          logger.i(
            '$_logTag bestMove mapped: toNode=${event.toNode} -> '
            '${bestAction?.payload["move"] ?? "(no legal action found)"}',
          );
        }
      }
    } catch (e) {
      // Stream error (e.g. Rust search panicked); treat as no best action.
      logger.e('$_logTag searchBestAction stream error: $e');
      return null;
    } finally {
      // The stream has ended (success or error), so the search is complete;
      // release the in-flight latch before the post-loop diagnostics/return.
      _searchInFlight = false;
    }
    if (eventCount == 0) {
      logger.w(
        '$_logTag searchBestAction: stream emitted 0 events '
        '(depth=$depth, moveLimitMs=$moveLimitMs)',
      );
    }
    if (EnvironmentConfig.devMode) {
      logger.d(
        '$_logTag searchBestAction done: '
        'bestAction=${bestAction?.payload["move"] ?? "(none)"}',
      );
    }
    return bestAction;
  }

  /// Search the current kernel state and return the requested root candidate
  /// lines without mutating the game.
  Future<List<NativeMillPrincipalVariation>> searchPrincipalVariations({
    int depth = 1,
    int moveLimitMs = 0,
    required int multiPv,
    GeneralSettings? engineSettings,
    void Function(List<NativeMillPrincipalVariation> variations)? onUpdate,
  }) async {
    if (_disposed || outcome.isTerminal) {
      return const <NativeMillPrincipalVariation>[];
    }
    assert(
      multiPv >= 1,
      'searchPrincipalVariations needs at least one candidate line.',
    );
    assert(
      !_searchInFlight,
      'Concurrent searchPrincipalVariations: a second engine search started '
      'while one was already in flight.',
    );
    _searchInFlight = true;

    final Map<int, NativeMillPrincipalVariation> variationsByRank =
        <int, NativeMillPrincipalVariation>{};
    final Map<int, NativeMillPrincipalVariation> currentBatchByRank =
        <int, NativeMillPrincipalVariation>{};
    int? currentBatchDepth;
    int? lastInfoDepth;
    bool currentBatchPublished = false;

    void publishBatch() {
      if (currentBatchByRank.isEmpty) {
        return;
      }
      variationsByRank
        ..clear()
        ..addAll(currentBatchByRank);
      currentBatchPublished = true;
      onUpdate?.call(_sortedPrincipalVariations(variationsByRank));
    }

    try {
      await for (final tgf.EngineEvent event in millSearchEvents(
        depth: depth,
        moveLimitMs: moveLimitMs,
        engineSettings: engineSettings,
        multiPv: multiPv,
      )) {
        if (event.kind == 'pv') {
          final NativeMillPrincipalVariation variation =
              _principalVariationFromEvent(event);
          if (currentBatchDepth != variation.depth) {
            if (!currentBatchPublished) {
              publishBatch();
            }
            currentBatchDepth = variation.depth;
            currentBatchByRank.clear();
            currentBatchPublished = false;
          }
          currentBatchByRank[variation.rank] = variation;
          currentBatchPublished = false;
          if (currentBatchByRank.length >= multiPv) {
            publishBatch();
          }
        } else if (event.kind == 'info' && event.depth > 0) {
          lastInfoDepth = event.depth;
        } else if (event.kind == 'bestMove' &&
            multiPv == 1 &&
            event.toNode >= 0) {
          final NativeMillPrincipalVariation variation =
              _principalVariationFromBestMoveEvent(
                event,
                lastInfoDepth ?? depth,
              );
          final NativeMillPrincipalVariation? existing =
              variationsByRank[variation.rank];
          if (_shouldUseBestMoveFallback(existing, variation)) {
            variationsByRank[variation.rank] = variation;
            onUpdate?.call(_sortedPrincipalVariations(variationsByRank));
          }
        }
      }
      if (!currentBatchPublished) {
        publishBatch();
      }
    } catch (e) {
      logger.e('$_logTag searchPrincipalVariations stream error: $e');
      rethrow;
    } finally {
      _searchInFlight = false;
    }
    return _sortedPrincipalVariations(variationsByRank);
  }

  /// Query the perfect database for the current position without running
  /// search or mutating the session.
  GameAction? perfectDatabaseBestAction({GeneralSettings? engineSettings}) {
    if (_disposed || outcome.isTerminal) {
      return null;
    }
    return rulesPort.perfectDatabaseBestAction(engineSettings: engineSettings);
  }

  /// "Avoid traps": correct [chosen] via the bundled lightweight error patch
  /// if it throws away value at the current position. See
  /// [NativeMillRulesPort.patchCorrectAction].
  GameAction? patchCorrectAction(
    GameAction chosen, {
    GeneralSettings? engineSettings,
  }) {
    if (_disposed || outcome.isTerminal) {
      return null;
    }
    return rulesPort.patchCorrectAction(chosen, engineSettings: engineSettings);
  }

  /// "Make traps": trap score of the position reached by [action]. See
  /// [NativeMillRulesPort.patchTrapScoreAfter].
  int? patchTrapScoreAfter(
    GameAction action, {
    GeneralSettings? engineSettings,
  }) {
    if (_disposed || outcome.isTerminal) {
      return null;
    }
    return rulesPort.patchTrapScoreAfter(
      action,
      engineSettings: engineSettings,
    );
  }

  /// Database-free "make traps": re-order [chosen] onto the proven sibling
  /// with the highest trap score, when the patch proves one exists. See
  /// [NativeMillRulesPort.patchMakeTrapsAction].
  GameAction? patchMakeTrapsAction(
    GameAction chosen, {
    GeneralSettings? engineSettings,
  }) {
    if (_disposed || outcome.isTerminal) {
      return null;
    }
    return rulesPort.patchMakeTrapsAction(
      chosen,
      engineSettings: engineSettings,
    );
  }

  /// Run Rust search from the current session, apply the best action if
  /// available, and return it to the caller for recording / UI feedback.
  ///
  /// [moveLimitMs]: when > 0, the search is time-bounded.
  Future<GameAction?> searchAndApplyBestAction({
    int depth = 1,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
  }) async {
    final GameAction? action = await searchBestAction(
      depth: depth,
      moveLimitMs: moveLimitMs,
      engineSettings: engineSettings,
    );
    if (action == null) {
      return null;
    }
    try {
      await apply(action);
    } catch (e) {
      // The apply failed (e.g. the Rust kernel rejected the action as
      // illegal after a concurrent state change).  Return null so the
      // caller can retry or surface an error.
      logger.e('$_logTag searchAndApplyBestAction apply failed: $e');
      return null;
    }
    return action;
  }

  static bool _shouldResignFromSearch(
    tgf.EngineEvent event,
    GeneralSettings? engineSettings,
  ) {
    const int valueMate = 80;
    return (engineSettings?.resignIfMostLose ?? false) &&
        event.score <= -valueMate;
  }

  static NativeMillPrincipalVariation _principalVariationFromEvent(
    tgf.EngineEvent event,
  ) {
    assert(event.kind == 'pv', 'Expected a pv event, got ${event.kind}.');
    final String notation = event.reason.split(' ').first;
    if (notation.isEmpty) {
      throw StateError('pv event carries no move notation: ${event.reason}');
    }
    final int? rank = _integerAnnotationFromReason(event.reason, 'rank');
    if (rank == null) {
      throw StateError('pv event carries no rank: ${event.reason}');
    }
    return NativeMillPrincipalVariation(
      rank: rank,
      move: notation,
      score: event.score,
      nodes: event.nodes.toInt(),
      depth: event.depth,
      nodesPerSecond: _integerAnnotationFromReason(event.reason, 'nps'),
      line: _pvLineFromReason(event.reason, fallbackMove: notation),
    );
  }

  static NativeMillPrincipalVariation _principalVariationFromBestMoveEvent(
    tgf.EngineEvent event,
    int depth,
  ) {
    assert(
      event.kind == 'bestMove',
      'Expected a bestMove event, got ${event.kind}.',
    );
    final String notation = event.reason.split(' ').first;
    if (notation.isEmpty) {
      throw StateError(
        'bestMove event carries no move notation: ${event.reason}',
      );
    }
    return NativeMillPrincipalVariation(
      rank: 1,
      move: notation,
      score: event.score,
      nodes: event.nodes.toInt(),
      depth: depth,
      line: <String>[notation],
    );
  }

  static bool _shouldUseBestMoveFallback(
    NativeMillPrincipalVariation? existing,
    NativeMillPrincipalVariation fallback,
  ) {
    if (existing == null) {
      return true;
    }
    if (fallback.depth > existing.depth) {
      return true;
    }
    if (fallback.depth < existing.depth) {
      return false;
    }
    if (fallback.move != existing.move) {
      return true;
    }
    return existing.line.length <= 1 && fallback.nodes > existing.nodes;
  }

  static List<NativeMillPrincipalVariation> _sortedPrincipalVariations(
    Map<int, NativeMillPrincipalVariation> variationsByRank,
  ) {
    final List<NativeMillPrincipalVariation> variations = variationsByRank
        .values
        .toList(growable: false);
    variations.sort(
      (NativeMillPrincipalVariation a, NativeMillPrincipalVariation b) =>
          a.rank.compareTo(b.rank),
    );
    return variations;
  }

  static List<String> _pvLineFromReason(
    String reason, {
    required String fallbackMove,
  }) {
    final RegExpMatch? pvMatch = RegExp(
      r'(?:^|\s)pv=([^\s]+)(?:\s|$)',
    ).firstMatch(reason);
    if (pvMatch == null) {
      return <String>[fallbackMove];
    }
    final List<String> line = pvMatch
        .group(1)!
        .split(',')
        .where((String move) => move.isNotEmpty)
        .toList(growable: false);
    return line.isEmpty ? <String>[fallbackMove] : line;
  }

  static int? _integerAnnotationFromReason(String reason, String name) {
    final RegExpMatch? match = RegExp(
      '(?:^|\\s)${RegExp.escape(name)}=(\\d+)(?:\\s|\$)',
    ).firstMatch(reason);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static PlayerSeat _opponentSeat(PlayerSeat seat) {
    return switch (seat) {
      PlayerSeat.first => PlayerSeat.second,
      PlayerSeat.second => PlayerSeat.first,
      PlayerSeat.none => PlayerSeat.none,
    };
  }

  /// Undo back to the root, then replay [moves] through this native session.
  ///
  /// Returns false if any replayed move is illegal in the Rust session.  The
  /// caller remains responsible for keeping any external PGN active-node
  /// pointer in sync with its chosen target node.
  Future<bool> replayMainline(Iterable<ExtMove> moves) async {
    // #region agent log
    final List<ExtMove> movesList = moves.toList(growable: false);
    agentDbg(
      'native_mill_game_session.dart:replayMainline:enter',
      'replayMainline enter',
      <String, Object?>{
        'session': identityHashCode(this),
        'moves': movesList.map((ExtMove m) => m.move).toList(),
        'undoDepthAtEntry': undoDepth,
      },
      hypothesisId: 'RACE,STALE,NOTATION',
    );
    // #endregion
    while (undoDepth > 0) {
      await undo();
    }
    // #region agent log
    if (undoDepth != 0) {
      agentDbg(
        'native_mill_game_session.dart:replayMainline:undoLoopExit',
        'undoDepth not zero after undo loop',
        <String, Object?>{
          'session': identityHashCode(this),
          'undoDepthAfterLoop': undoDepth,
        },
        hypothesisId: 'RACE',
      );
    }
    // #endregion
    int ply = 0;
    for (final ExtMove move in movesList) {
      final String moveString = move.move;
      GameAction? action;
      for (final GameAction legal in legalActions) {
        if (MillActionCodec.moveStringFrom(legal) == moveString) {
          action = legal;
          break;
        }
      }
      if (action == null) {
        // #region agent log
        agentDbg(
          'native_mill_game_session.dart:replayMainline:mismatch',
          'replayMainline notation mismatch',
          <String, Object?>{
            'session': identityHashCode(this),
            'ply': ply,
            'wantedMove': moveString,
            'legalActionNotations': legalActions
                .map((GameAction a) => MillActionCodec.moveStringFrom(a))
                .toList(),
            'phase': state.value.phase,
            'activeSeat': state.value.activeSeat.toString(),
            'undoDepth': undoDepth,
            'fen': getFen(),
          },
          hypothesisId: 'RACE,STALE,NOTATION',
        );
        // #endregion
        return false;
      }
      await apply(action);
      ply++;
    }
    return true;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    rulesPort.dispose();
    _state.dispose();
    _events.close();
  }

  void _setState(GameStateSnapshot next, {bool forcedTerminal = false}) {
    // Any real kernel transition supersedes a prior forced terminal; only
    // forceTerminal sets the flag.
    _forcedTerminal = forcedTerminal;
    _state.value = next;
    _emit(MillEventTypes.stateChanged, <String, Object?>{
      'phase': next.phase,
      'activeSeat': next.activeSeat.name,
      'outcome': next.outcome.kind.name,
    });
  }

  void _emit(String type, Map<String, Object?> payload) {
    if (!_events.isClosed) {
      _events.add(GameSessionEvent(type, payload: payload));
    }
  }

  static String? _boardLayoutFromSnapshot(GameStateSnapshot snapshot) {
    return NativeMillSnapshotBoardView.fromSnapshot(snapshot)?.toBoardLayout();
  }

  /// Map a Rust `bestMove` event back to one checked action for this session.
  ///
  /// The event's `reason` field starts with the full UCI notation of the
  /// searched action ("a4", "a1-a4", "xa4"), produced by the Rust
  /// `MillUciCodec` from the same node-label table that
  /// [MillActionCodec.moveStringFromTgfAction] uses.  Parse that one notation
  /// directly, then ask the live kernel whether the action is still legal.
  ///
  /// This preserves the old stale-search guard without materialising and
  /// string-scanning the full legal-action list on every AI move.  Matching by
  /// `toNode` alone is NOT sufficient: in the moving phase two pieces can
  /// converge on the same destination square, and in `mayMoveInPlacingPhase`
  /// variants a place and a move can share a destination.
  GameAction? _legalActionForBestMove(tgf.EngineEvent event) {
    // Capture the exact position the engine result is validated against, so a
    // later apply rejection can be diagnosed as a stale snapshot (the state
    // changed between here and apply) versus a genuinely illegal engine move.
    _lastSearchValidatedFen = _safeExportFen();
    _lastSearchValidatedZobrist = _zobristOf(_state.value);

    final String notation = event.reason.split(' ').first;
    assert(
      notation.isNotEmpty,
      'bestMove event (toNode=${event.toNode}) carries no notation in '
      'reason="${event.reason}".',
    );
    final tgf_kernel.TgfAction? tgfAction =
        MillActionCodec.tgfActionFromMoveString(notation);
    if (tgfAction == null) {
      logger.w(
        '$_logTag bestMove "$notation" (toNode=${event.toNode}) cannot be '
        'parsed as a Mill action; treating as no best move.',
      );
      _recordEngineFailure(
        stage: 'notationParse',
        chosenMove: notation.isEmpty ? '(empty)' : notation,
        actionType: '(unparsed)',
        rejectReason:
            'engine bestMove notation could not be parsed into an action',
      );
      return null;
    }
    assert(
      tgfAction.toNode == event.toNode,
      'Parsed bestMove "$notation" has toNode=${tgfAction.toNode} '
      'but the engine reported toNode=${event.toNode}.',
    );
    final GameAction action = MillActionCodec.fromTgfAction(tgfAction);
    if (rulesPort.isLegal(action)) {
      return action;
    }
    logger.w(
      '$_logTag bestMove "$notation" (toNode=${event.toNode}) is no longer '
      'legal in the current session; treating as no best move.',
    );
    _recordEngineFailure(
      stage: 'searchValidation',
      chosenMove: notation,
      actionType: action.type,
      rejectReason: 'engine bestMove rejected by isLegal at validation time',
    );
    return null;
  }

  /// Native Zobrist key carried by a session snapshot, or null if absent.
  static int? _zobristOf(GameStateSnapshot snapshot) {
    final Object? z = snapshot.payload['tgfZobrist'];
    return z is int ? z : null;
  }

  /// FEN of the live kernel state; never throws (diagnostic-only path).
  String _safeExportFen() {
    try {
      return rulesPort.exportFen();
    } catch (e) {
      return '(exportFen failed: $e)';
    }
  }

  /// Record a precise, release-visible explanation for an engine-move
  /// rejection in [_lastEngineFailureDetails].  This never swallows the
  /// failure (the EngineNoBestMove still propagates and the dialog still
  /// shows); it only enriches the report so the stale-snapshot race -- where
  /// the position changes between search validation and apply -- can be
  /// confirmed from a user-submitted crash report instead of guessed at.
  void _recordEngineFailure({
    required String stage,
    required String chosenMove,
    required String actionType,
    required String rejectReason,
    bool matchedSearchAction = false,
  }) {
    final String liveFen = _safeExportFen();
    final int? liveZobrist = _zobristOf(_state.value);
    final bool stateChanged =
        _lastSearchValidatedZobrist != null &&
        liveZobrist != null &&
        _lastSearchValidatedZobrist != liveZobrist;
    String liveLegal;
    try {
      liveLegal = legalActions
          .map((GameAction a) => MillActionCodec.moveStringFrom(a) ?? '?')
          .join(' ');
    } catch (e) {
      liveLegal = '(legalActions failed: $e)';
    }
    final StringBuffer buf = StringBuffer()
      ..writeln('EngineMoveRejected: stage=$stage')
      ..writeln('chosenMove=$chosenMove type=$actionType')
      ..writeln('matchedCachedSearchAction=$matchedSearchAction')
      ..writeln('searchValidatedFen=${_lastSearchValidatedFen ?? "(none)"}')
      ..writeln(
        'searchValidatedZobrist=${_lastSearchValidatedZobrist ?? "(none)"}',
      )
      ..writeln('liveFen=$liveFen')
      ..writeln('liveZobrist=${liveZobrist ?? "(none)"}')
      ..writeln('stateChangedDuringSearch=$stateChanged')
      ..writeln('liveLegalMoves=${liveLegal.isEmpty ? "(none)" : liveLegal}')
      ..write('rejectReason=$rejectReason');
    _lastEngineFailureDetails = buf.toString();
    logger.e('$_logTag $_lastEngineFailureDetails');
  }

  static AiMoveType _aiMoveTypeFromReason(String reason) {
    final RegExpMatch? match = _aimovetypePattern.firstMatch(reason);
    if (match == null) {
      return AiMoveType.traditional;
    }
    return switch (match.group(1)) {
      'perfect' => AiMoveType.perfect,
      'consensus' => AiMoveType.consensus,
      'openingBook' => AiMoveType.openingBook,
      'humanDatabase' => AiMoveType.humanDatabase,
      'traditional' => AiMoveType.traditional,
      _ => AiMoveType.traditional,
    };
  }
}
