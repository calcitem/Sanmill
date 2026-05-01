// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/mill.dart'
    show ExtMove, GameController, PieceColor;
import '../../game_platform/game_session.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'mill_action_codec.dart';
import 'native_mill_game_session.dart';
import 'native_mill_rules_port.dart';
import 'native_mill_snapshot_board_view.dart';

/// Native Mill session specialized for puzzle mode.
///
/// The current Rust kernel setup API can express the board occupancy and
/// side-to-move carried by normal puzzle FENs.  Legacy `Position` is used only
/// as a parser/validator until the Rust kernel exposes a full FEN parser.
class PuzzleMillSession extends NativeMillGameSession {
  PuzzleMillSession({
    required String initialFen,
    RuleSettings rules = const RuleSettings(),
  }) : super.fromPort(NativeMillRulesPort(ruleSettings: rules)) {
    _loadInitialFen(initialFen);
  }

  late final PlayerSeat humanSeat;

  PieceColor get humanColor =>
      humanSeat == PlayerSeat.second ? PieceColor.black : PieceColor.white;

  PieceColor get sideToMove => switch (state.value.activeSeat) {
    PlayerSeat.second => PieceColor.black,
    PlayerSeat.first => PieceColor.white,
    PlayerSeat.none => PieceColor.nobody,
  };

  bool applyMoveString(String move) {
    final PieceColor mover = sideToMove;
    for (final GameAction action in legalActions) {
      if (action.payload['move'] == move) {
        apply(action);
        _appendExtMove(move, mover);
        return true;
      }
    }
    return false;
  }

  bool applyExtMove(ExtMove move) => applyMoveString(move.move);

  ExtMove extMoveForAction(GameAction action, {required PieceColor side}) {
    final String? move = MillActionCodec.moveStringFrom(action);
    assert(
      move != null && move.isNotEmpty,
      'Native puzzle action has no move.',
    );
    return ExtMove(move!, side: side);
  }

  Map<int, PlayerSeat> get occupiedNodes {
    final NativeMillSnapshotBoardView? board =
        NativeMillSnapshotBoardView.fromSnapshot(state.value);
    return board?.occupiedNodes() ?? const <int, PlayerSeat>{};
  }

  void _loadInitialFen(String initialFen) {
    final bool loaded = loadFen(initialFen);
    assert(loaded, 'Puzzle FEN must be validated before native loading.');
    // Derive humanSeat from the side-to-move in the loaded snapshot.
    humanSeat = state.value.activeSeat == PlayerSeat.second
        ? PlayerSeat.second
        : PlayerSeat.first;
  }

  void _appendExtMove(String move, PieceColor mover) {
    final ExtMove extMove = ExtMove(move, side: mover);
    GameController().gameRecorder.appendMoveIfDifferent(extMove);
  }
}
