// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Setup-position editing controller for the Rust-native Mill session.
//
// This restores the legacy "Set Up Position" editor on top of the
// `NativeMillGameSession` setup API.  The legacy editor mutated the
// deleted Dart `Position` class directly; this controller instead keeps
// a small local board model, serialises it to a Mill FEN, and pushes it
// through `NativeMillGameSession.loadFen` so the Rust kernel remains the
// single source of truth for board state, validation, and rendering.
//
// Why a local model plus FEN rather than the minimal native setup API
// (`setupSetPiece` / `setupFinish`): the native API intentionally
// auto-derives the phase and in-hand counts from on-board occupancy
// (see docs/FRAMEWORK_API.md).  The legacy editor additionally lets the
// user pick the phase (e.g. a moving-phase endgame study where the
// missing pieces were captured) and an explicit pending-removal count.
// Those intents cannot be expressed through `setupFinish` alone, but the
// FEN format carries every field, and `tgf_kernel_set_from_fen` parses
// and validates all of them.  Building the FEN locally therefore gives
// full editor fidelity with zero new Rust surface.

import 'dart:typed_data';

import '../../game_page/services/transform/transform.dart';
import '../../game_platform/game_session.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'mill_marked_pieces_codec.dart';
import 'mill_types.dart';
import 'native_mill_game_session.dart';

/// Owns the mutable state of an in-progress setup-position edit and
/// applies every change to the backing [NativeMillGameSession].
///
/// The controller is UI-agnostic: it exposes intent methods
/// ([tapNode], [setPaintColor], [setPhase], …) that mutate the local
/// model and re-synchronise the session.  Widgets read [paintColor],
/// [phase], [sideToMove] and the count helpers to render their state.
class MillSetupPositionController {
  MillSetupPositionController({
    required this.session,
    required this.ruleSettings,
  });

  /// Backing native session whose board this controller edits.
  final NativeMillGameSession session;

  /// Rule snapshot captured when the editor was opened; controls piece
  /// limits, the marked-piece variant, and removal bookkeeping.
  final RuleSettings ruleSettings;

  /// Local board occupancy indexed by Rust node id (0..23).
  final List<PieceColor> _board = List<PieceColor>.filled(24, PieceColor.none);

  /// Piece type the next board tap will paint.  Cycled by the toolbar.
  PieceColor paintColor = PieceColor.white;

  /// Side to move committed into the FEN.
  PieceColor sideToMove = PieceColor.white;

  /// Phase committed into the FEN (placing or moving).
  Phase phase = Phase.placing;

  /// Pending removal obligation per side, mirroring `pieceToRemoveCount`.
  final Map<PieceColor, int> needRemove = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  /// Pieces already placed in the placing phase, mirroring the legacy
  /// setup editor's `newPlaced`.  Drives in-hand counts independently of
  /// on-board occupancy so mid-placing studies can be authored.
  int placedCount = 0;

  /// FEN captured on entry so [cancel] can roll the board back.
  String? _backupFen;

  /// Whether the most recent [_sync] produced a kernel-accepted FEN.
  bool _lastSyncValid = true;

  int get piecesCount => ruleSettings.piecesCount;

  /// True when the active variant supports delayed (marked) removal, so
  /// the paint cycle should offer the marked piece type.
  bool get supportsMarkedPiece =>
      ruleSettings.millFormationActionInPlacingPhase ==
      MillFormationActionInPlacingPhase.markAndDelayRemovingPieces;

  /// Number of pieces of [color] currently on the board.
  int countOnBoard(PieceColor color) =>
      _board.where((PieceColor c) => c == color).length;

  /// Total occupied points (both colours plus marked).
  int get totalOnBoard =>
      _board.where((PieceColor c) => c != PieceColor.none).length;

  // -------------------------------------------------------------- lifecycle

  /// Capture a rollback FEN and seed the local model from the session's
  /// current board so editing starts from the position on screen.
  void initFromSession() {
    _backupFen = session.getFen();
    _readBoardFromSession();

    final GameStateSnapshot snapshot = session.state.value;
    sideToMove = snapshot.activeSeat == PlayerSeat.second
        ? PieceColor.black
        : PieceColor.white;
    phase = snapshot.phase == 'moving' ? Phase.moving : Phase.placing;
    paintColor = sideToMove;
    needRemove[PieceColor.white] = 0;
    needRemove[PieceColor.black] = 0;
    _readPlacedCountFromSessionFen();
  }

  // ----------------------------------------------------------- edit intents

  /// Cycle the paint selection white → black → (marked) → empty → white,
  /// coupling [sideToMove] to the colour when a real colour is chosen
  /// (mirrors the legacy editor).
  void cyclePaintColor() {
    switch (paintColor) {
      case PieceColor.white:
        setPaintColor(PieceColor.black);
      case PieceColor.black:
        setPaintColor(
          supportsMarkedPiece && phase == Phase.placing
              ? PieceColor.marked
              : PieceColor.none,
        );
      case PieceColor.marked:
        setPaintColor(PieceColor.none);
      case PieceColor.none:
      case PieceColor.nobody:
      case PieceColor.draw:
        setPaintColor(PieceColor.white);
    }
  }

  /// Set the paint selection directly and update the side to move when a
  /// concrete colour is selected.
  void setPaintColor(PieceColor color) {
    paintColor = color;
    if (color == PieceColor.white || color == PieceColor.black) {
      sideToMove = color;
      _sync();
    }
  }

  /// Toggle between placing and moving phase.
  void setPhase(Phase next) {
    phase = next;
    // Marked pieces only make sense during placing; drop the paint
    // selection back to a colour when leaving placing phase.
    if (phase != Phase.placing && paintColor == PieceColor.marked) {
      paintColor = sideToMove;
    }
    if (phase == Phase.moving) {
      placedCount = piecesCount;
    } else {
      updatePlacedCountFromBoard();
    }
    _sync();
  }

  /// Infer how many pieces have been placed from the current board layout.
  /// Mirrors legacy `setSetupPositionPlacedGetBegin`.
  int inferPlacedCountFromBoard() {
    if (phase == Phase.moving) {
      return piecesCount;
    }

    final int white = countOnBoard(PieceColor.white);
    final int black = countOnBoard(PieceColor.black);
    int begin = white > black ? white : black;
    if (sideToMove == PieceColor.black && white > black) {
      begin--;
    }
    return begin.clamp(0, piecesCount);
  }

  /// Lowest selectable value for the placed-count picker.
  int get placedCountModalBegin => inferPlacedCountFromBoard();

  /// Recompute [placedCount] from the board after occupancy changes.
  void updatePlacedCountFromBoard() {
    placedCount = inferPlacedCountFromBoard();
  }

  /// Set how many pieces have been placed in the placing phase.
  void setPlacedCount(int count) {
    if (phase != Phase.placing) {
      return;
    }
    placedCount = count.clamp(0, piecesCount);
    _sync();
  }

  /// Paint or clear the board point identified by Rust [node].
  void tapNode(int node) {
    if (node < 0 || node >= 24) {
      return;
    }
    if (paintColor == PieceColor.none) {
      _board[node] = PieceColor.none;
    } else {
      // Mirror the legacy editor: only paint onto empty points and honour
      // the per-colour and total piece limits so the position stays legal.
      if (_board[node] != PieceColor.none) {
        return;
      }
      if (paintColor == PieceColor.marked) {
        if (totalOnBoard >= piecesCount * 2) {
          return;
        }
      } else if (countOnBoard(paintColor) >= piecesCount) {
        return;
      }
      _board[node] = paintColor;
    }
    updatePlacedCountFromBoard();
    _sync();
  }

  /// Set the pending removal count for [color], clamped to a sane range.
  void setNeedRemove(PieceColor color, int count) {
    if (color != PieceColor.white && color != PieceColor.black) {
      return;
    }
    final PieceColor opponent = _opponentOf(color);
    final int opponentOnBoard = countOnBoard(opponent);
    final int clamped = count.clamp(
      0,
      opponentOnBoard < 3 ? opponentOnBoard : 3,
    );
    needRemove[color] = clamped;
    // The legacy engine never tracks a removal obligation for both sides
    // simultaneously; keep the opponent's count at zero.
    needRemove[opponent] = 0;
    _sync();
  }

  /// Clear the whole board and reset removal obligations.
  void clear() {
    for (int i = 0; i < 24; i++) {
      _board[i] = PieceColor.none;
    }
    needRemove[PieceColor.white] = 0;
    needRemove[PieceColor.black] = 0;
    updatePlacedCountFromBoard();
    _sync();
  }

  /// Apply a board symmetry [type] by transforming the current FEN.
  void transform(TransformationType type) {
    final String transformed = transformFEN(session.getFen(), type);
    if (session.loadFen(transformed)) {
      _readBoardFromSession();
      updatePlacedCountFromBoard();
    }
  }

  /// Current FEN as held by the session (after the latest [_sync]).
  String exportFen() {
    _sync();
    return session.getFen();
  }

  /// Load [fen] into the session and re-seed the local model from it.
  /// Returns true when the FEN was accepted by the kernel.
  bool pasteFen(String fen) {
    if (!session.loadFen(fen.trim())) {
      return false;
    }
    _readBoardFromSession();
    final GameStateSnapshot snapshot = session.state.value;
    sideToMove = snapshot.activeSeat == PlayerSeat.second
        ? PieceColor.black
        : PieceColor.white;
    phase = snapshot.phase == 'moving' ? Phase.moving : Phase.placing;
    paintColor = sideToMove;
    _readPlacedCountFromSessionFen();
    return true;
  }

  // ------------------------------------------------------------- completion

  /// Roll the session board back to the FEN captured on entry.
  void cancel() {
    final String? backup = _backupFen;
    if (backup != null) {
      session.loadFen(backup);
    }
  }

  /// Finalise editing: push the model and return the committed FEN, or
  /// null when the position is not a legal Mill FEN.
  String? commit() {
    if (!_sync() || !_lastSyncValid) {
      return null;
    }
    return session.getFen();
  }

  // --------------------------------------------------------------- internals

  void _readBoardFromSession() {
    for (int i = 0; i < 24; i++) {
      _board[i] = PieceColor.none;
    }
    final Object? raw = session.state.value.payload['tgfPayload'];
    if (raw is! Uint8List || raw.length < 24) {
      return;
    }
    final Set<int> marked = MillMarkedPiecesCodec.markedNodesFromOpaquePayload(
      raw,
    );
    for (int node = 0; node < 24; node++) {
      if (marked.contains(node)) {
        _board[node] = PieceColor.marked;
        continue;
      }
      _board[node] = switch (raw[node]) {
        1 => PieceColor.white,
        2 => PieceColor.black,
        _ => PieceColor.none,
      };
    }
  }

  /// Serialise the local model to a Mill FEN and push it to the session.
  bool _sync() {
    final String fen = _buildFen();
    _lastSyncValid = session.loadFen(fen);
    return _lastSyncValid;
  }

  String _buildFen() {
    final String board = _buildBoardField();

    final int onWhite = countOnBoard(PieceColor.white);
    final int onBlack = countOnBoard(PieceColor.black);

    final int inHandWhite;
    final int inHandBlack;
    if (phase == Phase.moving) {
      // Missing pieces are captured/gone, not in hand.
      inHandWhite = 0;
      inHandBlack = 0;
    } else {
      final ({int white, int black}) inHand = placingInHandCounts(
        piecesCount: piecesCount,
        placedCount: placedCount,
        sideToMove: sideToMove,
      );
      inHandWhite = inHand.white;
      inHandBlack = inHand.black;
    }

    final int removeWhite = needRemove[PieceColor.white] ?? 0;
    final int removeBlack = needRemove[PieceColor.black] ?? 0;

    final String side = sideToMove == PieceColor.black ? 'b' : 'w';
    final String phaseToken = phase == Phase.moving ? 'm' : 'p';

    final int activeRemove = sideToMove == PieceColor.black
        ? removeBlack
        : removeWhite;
    final String actionToken = activeRemove > 0
        ? 'r'
        : (phase == Phase.placing ? 'p' : 's');

    // Fields: board side phase act w_on w_hand b_on b_hand w_remove
    //         b_remove w_from w_to b_from b_to mills_mask rule50 fullmove
    return '$board $side $phaseToken $actionToken '
        '$onWhite $inHandWhite $onBlack $inHandBlack '
        '$removeWhite $removeBlack -1 -1 -1 -1 0 0 1 ids:nodes';
  }

  /// Build the 26-character FEN board field (three 8-char ranks joined by
  /// '/') from the local node-indexed model.
  String _buildBoardField() {
    final List<String> chars = List<String>.filled(26, '*');
    chars[8] = '/';
    chars[17] = '/';

    for (int node = 0; node < 24; node++) {
      final int pos = node;
      final int slot = pos < 8
          ? pos
          : pos < 16
          ? pos + 1
          : pos + 2;
      chars[slot] = _pieceChar(_board[node]);
    }
    return chars.join();
  }

  static PieceColor _opponentOf(PieceColor color) {
    return switch (color) {
      PieceColor.white => PieceColor.black,
      PieceColor.black => PieceColor.white,
      _ => PieceColor.none,
    };
  }

  void _readPlacedCountFromSessionFen() {
    if (phase == Phase.moving) {
      placedCount = piecesCount;
      return;
    }

    final List<String> parts = session.getFen().split(' ');
    if (parts.length < 8) {
      updatePlacedCountFromBoard();
      return;
    }

    final int? blackInHand = int.tryParse(parts[7]);
    if (blackInHand == null) {
      updatePlacedCountFromBoard();
      return;
    }

    placedCount = (piecesCount - blackInHand).clamp(0, piecesCount);
  }

  /// Encode in-hand counts for a placing-phase FEN from [placedCount].
  /// Mirrors legacy `updateSetupPositionPiecesCount`.
  static ({int white, int black}) placingInHandCounts({
    required int piecesCount,
    required int placedCount,
    required PieceColor sideToMove,
  }) {
    final int clampedPlaced = placedCount.clamp(0, piecesCount);
    final int blackInHand = (piecesCount - clampedPlaced).clamp(0, piecesCount);
    if (sideToMove == PieceColor.white) {
      return (white: blackInHand, black: blackInHand);
    }
    if (sideToMove == PieceColor.black) {
      return (
        white: (blackInHand - 1).clamp(0, piecesCount),
        black: blackInHand,
      );
    }
    return (white: blackInHand, black: blackInHand);
  }

  static String _pieceChar(PieceColor color) {
    switch (color) {
      case PieceColor.white:
        return 'O';
      case PieceColor.black:
        return '@';
      case PieceColor.marked:
        return 'X';
      case PieceColor.none:
      case PieceColor.nobody:
      case PieceColor.draw:
        return '*';
    }
  }
}
