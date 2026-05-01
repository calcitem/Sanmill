// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/mill.dart' show PieceColor, Position;
import '../../game_platform/game_session.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'mill_action_codec.dart';
import 'mill_board_coordinate_maps.dart';
import 'native_mill_game_session.dart';
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
  }) : super(rules: rules) {
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
    assert(move != null && move.isNotEmpty, 'Native puzzle action has no move.');
    return ExtMove(move!, side: side);
  }

  Map<int, PlayerSeat> get occupiedNodes {
    final NativeMillSnapshotBoardView? board =
        NativeMillSnapshotBoardView.fromSnapshot(state.value);
    return board?.occupiedNodes() ?? const <int, PlayerSeat>{};
  }

  void _loadInitialFen(String initialFen) {
    final Position parsed = Position();
    final bool loaded = parsed.setFen(initialFen);
    assert(loaded, 'Puzzle FEN must be validated before native loading.');
    if (!loaded) {
      return;
    }

    setupClear();
    for (final MapEntry<int, int> entry
        in MillBoardCoordinateMaps.nodeToLegacySquare.entries) {
      final PieceColor piece = parsed.pieceOnGrid(entry.value);
      final int owner = switch (piece) {
        PieceColor.white => 1,
        PieceColor.black => 2,
        _ => 0,
      };
      if (owner != 0) {
        setupSetPiece(entry.key, owner);
      }
    }

    final int side = parsed.sideToMove == PieceColor.black ? 1 : 0;
    setupSetSide(side);
    humanSeat = side == 1 ? PlayerSeat.second : PlayerSeat.first;
    setupFinish();
  }

  void _appendExtMove(String move, PieceColor mover) {
    final ExtMove extMove = ExtMove(move, side: mover);
    GameController().gameRecorder.appendMoveIfDifferent(extMove);
  }
}
