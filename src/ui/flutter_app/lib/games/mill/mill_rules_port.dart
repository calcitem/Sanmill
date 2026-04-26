// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Phase 6 transitional RulesPort backed by FRB.
//
// This is the first non-stub Mill rules port.  It delegates to the Phase 2
// legacy kernel (Dart -> FRB -> Rust -> cxx -> mature C++ engine) so the
// generic game shell can enumerate legal actions without depending on
// GameController or duplicating rule logic in Dart.

import '../../game_platform/engine/legacy_tgf_kernel.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/rules_port.dart';
import 'mill_constants.dart';

class MillRulesPort implements RulesPort {
  MillRulesPort({LegacyTgfKernel kernel = const LegacyTgfKernel()})
    : _kernel = kernel {
    reset();
  }

  final LegacyTgfKernel _kernel;
  late GameStateSnapshot _snapshot;

  /// Current legacy-kernel FEN mirrored by this rules port.
  String get fen => _snapshot.payload['fen']! as String;

  /// Reset this rules port to a fresh game and return the new snapshot.
  GameStateSnapshot reset({int ruleIndex = 0}) {
    final String fen = _kernel.reset(ruleIndex: ruleIndex);
    _snapshot = _snapshotFromFen(fen);
    return _snapshot;
  }

  /// Synchronise this rules port with an existing legacy FEN snapshot.
  GameStateSnapshot setFen(String fen) {
    _kernel.setFen(fen);
    _snapshot = _snapshotFromFen(_kernel.fen());
    return _snapshot;
  }

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  List<GameAction> get legalActions {
    if (_snapshot.outcome.isTerminal) {
      return const <GameAction>[];
    }
    return _kernel.legalActions().map(_actionFromUci).toList(growable: false);
  }

  @override
  bool isLegal(GameAction action) {
    final String? move = _moveStringFrom(action);
    if (move == null || move.isEmpty) {
      return false;
    }
    return _kernel.legalActions().contains(move);
  }

  @override
  GameStateSnapshot apply(GameAction action) {
    assert(isLegal(action), 'Illegal Mill action: ${action.type}.');
    final String move = _moveStringFrom(action)!;
    final bool ok = _kernel.applyUci(move);
    assert(ok, 'Legacy kernel rejected legal Mill action: $move.');
    _snapshot = _snapshotFromFen(_kernel.fen(), lastAction: action);
    return _snapshot;
  }

  GameStateSnapshot _snapshotFromFen(String fen, {GameAction? lastAction}) {
    final int side = _kernel.sideToMove();
    final PlayerSeat seat = switch (side) {
      1 => PlayerSeat.first,
      2 => PlayerSeat.second,
      _ => PlayerSeat.none,
    };
    return GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: seat,
      outcome: const GameOutcome.ongoing(),
      phase: _phaseName(_kernel.phaseTag()),
      lastAction: lastAction,
      payload: <String, Object?>{'fen': fen},
    );
  }

  static String _phaseName(int phaseTag) {
    return switch (phaseTag) {
      1 => 'ready',
      2 => 'placing',
      3 => 'moving',
      4 => 'gameOver',
      _ => MillPhases.legacy,
    };
  }

  static GameAction _actionFromUci(String move) {
    final String type = _typeFromUci(move);
    return GameAction(type: type, payload: <String, Object?>{'move': move});
  }

  static String _typeFromUci(String move) {
    if (move.startsWith('x')) {
      return MillActionTypes.remove;
    }
    if (move.contains('-')) {
      return MillActionTypes.move;
    }
    return MillActionTypes.place;
  }

  static String? _moveStringFrom(GameAction action) {
    final Object? raw = action.payload['move'];
    return raw is String ? raw : null;
  }
}
