// SPDX-License-Identifier: GPL-3.0-or-later
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
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../src/rust/api/kernel.dart' as tgf_kernel;
import '../../src/rust/api/simple.dart' as tgf;
import 'lan_session_meta.dart';
import 'mill_action_codec.dart';
import 'mill_marked_pieces_codec.dart';
import 'mill_types.dart';
import 'native_mill_rules_port.dart';

const String _logTag = '[NativeMillGameSession]';

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
  NativeMillGameSession.fromPort(this.rulesPort, {this.lanMeta})
    : _state = ValueNotifier<GameStateSnapshot>(rulesPort.snapshot);

  NativeMillRulesPort rulesPort;
  LanSessionMeta? lanMeta;
  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();
  bool _disposed = false;
  GameAction? _lastSearchLegalAction;

  /// True while a session-level terminal result (resignation / timeout /
  /// abandonment) is overlaid on top of the Rust kernel state.  Cleared by
  /// the next real kernel transition (every [_setState] call that is not a
  /// forced terminal).  See [forceTerminal].
  bool _forcedTerminal = false;

  AiMoveType lastAiMoveType = AiMoveType.unknown;

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
    if (rules != null) {
      final NativeMillRulesPort nextPort = NativeMillRulesPort(
        ruleSettings: rules,
        generalSettings: generalSettings,
      );
      rulesPort.dispose();
      rulesPort = nextPort;
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
    final GameStateSnapshot next = rulesPort.apply(action);
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
  }) {
    return rulesPort.millSearchEvents(
      depth: depth,
      moveLimitMs: moveLimitMs,
      engineSettings: engineSettings,
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

    if (EnvironmentConfig.devMode) {
      logger.d(
        '$_logTag searchBestAction: depth=$depth '
        'moveLimitMs=$moveLimitMs phase=${state.value.phase}',
      );
    }

    _lastSearchLegalAction = null;
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
    while (undoDepth > 0) {
      await undo();
    }
    for (final ExtMove move in moves) {
      final String moveString = move.move;
      GameAction? action;
      for (final GameAction legal in legalActions) {
        if (MillActionCodec.moveStringFrom(legal) == moveString) {
          action = legal;
          break;
        }
      }
      if (action == null) {
        return false;
      }
      await apply(action);
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
    final Object? rawPayload = snapshot.payload['tgfPayload'];
    if (rawPayload is! Uint8List || rawPayload.length < 24) {
      return null;
    }
    final Object? rawMarkedNodes = snapshot.payload[millMarkedNodesPayloadKey];
    final Set<int> markedNodes = rawMarkedNodes is Set<int>
        ? rawMarkedNodes
        : MillMarkedPiecesCodec.markedNodesFromOpaquePayload(rawPayload);

    // The native node-id FEN dialect stores board nodes in the same order as
    // the first 24 bytes of MillState::encode(), with slashes after each ring.
    const int empty = 42; // '*'
    const int slash = 47; // '/'
    const int white = 79; // 'O'
    const int black = 64; // '@'
    const int marked = 88; // 'X'
    final List<int> chars = List<int>.filled(26, empty);
    chars[8] = slash;
    chars[17] = slash;
    for (int node = 0; node < 24; node++) {
      final int slot = node < 8
          ? node
          : node < 16
          ? node + 1
          : node + 2;
      if (markedNodes.contains(node)) {
        chars[slot] = marked;
      } else {
        chars[slot] = switch (rawPayload[node]) {
          1 => white,
          2 => black,
          _ => empty,
        };
      }
    }
    return String.fromCharCodes(chars);
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
    return null;
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
      'traditional' => AiMoveType.traditional,
      _ => AiMoveType.traditional,
    };
  }
}
