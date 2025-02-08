// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ext_move.dart

part of '../mill.dart';

enum MoveType { place, move, remove, draw, none }

class MoveParser {
  MoveType parseMoveType(String move) {
    if (move.startsWith("-") && move.length == "-(1,2)".length) {
      return MoveType.remove;
    } else if (move.length == "(1,2)->(3,4)".length) {
      return MoveType.move;
    } else if (move.length == "(1,2)".length) {
      return MoveType.place;
    } else if (move == "draw") {
      logger.i("[TODO] Computer request draw");
      return MoveType.draw;
    } else if (move == "(none)") {
      logger.i("MoveType is (none).");
      return MoveType.none;
    } else {
      // TODO: If Setup Position is illegal
      throw const FormatException();
    }
  }
}

/// ExtMove now extends [PgnNodeData] in order to satisfy
/// the generic bound `T extends PgnNodeData` in `PgnNode<T>`.
class ExtMove extends PgnNodeData {
  /// We override PgnNodeData's "san" by passing it into super(...).
  /// Also we can pass along nags, startingComments, etc.
  ///
  /// Because PgnNodeData constructor requires `san` and optionally
  /// `startingComments`, `comments`, `nags`, we can map them
  /// from what we already have in ExtMove.
  ///
  /// If you prefer, you can unify "move" and "san" as well.
  ExtMove(
    this.move, {
    required this.side,
    this.boardLayout,
    this.moveIndex,
    super.nags,
    super.startingComments,
    super.comments,
  })  : type = MoveParser().parseMoveType(move),
        to = _parseToSquare(move),
        // Put all your own field initializations first ...
        super(
          // ...then call super(...) last
          san: move,
        ) {
    _checkLegal(move);
  }

  /// The UCI-like move string, e.g. "(3,5)->(3,4)"
  final String move;

  /// Indicates which side performed the move.
  final PieceColor side;

  /// The parsed MoveType (place/move/remove/draw/none).
  final MoveType type;

  /// 'to' square (computed from 'move').
  final int to;

  /// The board layout after the move.
  String? boardLayout;

  /// The move index.
  int? moveIndex;

  static const String _logTag = "[Move]";

  /// 'from' square if type==move; otherwise -1.
  int get from => type == MoveType.move
      ? makeSquare(int.parse(move[1]), int.parse(move[3]))
      : -1;

  static int _parseToSquare(String move) {
    late int file;
    late int rank;
    final MoveType t = MoveParser().parseMoveType(move);
    switch (t) {
      case MoveType.place:
        file = int.parse(move[1]);
        rank = int.parse(move[3]);
        break;
      case MoveType.move:
        file = int.parse(move[8]);
        rank = int.parse(move[10]);
        break;
      case MoveType.remove:
        file = int.parse(move[2]);
        rank = int.parse(move[4]);
        break;
      case MoveType.draw:
        file = 0;
        rank = 0;
        break;
      case MoveType.none:
        file = -1;
        rank = -1;
        break;
    }
    return makeSquare(file, rank);
  }

  static final Map<int, String> _squareToWmdNotation = <int, String>{
    -1: "(none)", // TODO: Can parse it?
    0: "draw", // TODO: Can parse it?
    8: "d5",
    9: "e5",
    10: "e4",
    11: "e3",
    12: "d3",
    13: "c3",
    14: "c4",
    15: "c5",
    16: "d6",
    17: "f6",
    18: "f4",
    19: "f2",
    20: "d2",
    21: "b2",
    22: "b4",
    23: "b6",
    24: "d7",
    25: "g7",
    26: "g4",
    27: "g1",
    28: "d1",
    29: "a1",
    30: "a4",
    31: "a7"
  };

  static String sqToNotation(int sq) {
    final String? ret = _squareToWmdNotation[sq];
    return ret ?? "";
  }

  /// Validate the move string format.
  static void _checkLegal(String move) {
    // TODO: Which one?
    if (move == "draw" || move == "(none)" || move == "none") {
      return; // no further checks
    }

    if (move.length > "(3,1)->(2,1)".length) {
      throw FormatException("$_logTag Invalid Move: too long", move);
    }

    if (!(move.startsWith("(") || move.startsWith("-"))) {
      throw FormatException(
          "$_logTag Invalid Move: must start with '(' or '-'", move, 0);
    }

    if (!move.endsWith(")")) {
      throw FormatException(
          "$_logTag Invalid Move: must end with ')'", move, move.length - 1);
    }

    const String allowedChars = "0123456789(,)->";
    for (int i = 0; i < move.length; i++) {
      if (!allowedChars.contains(move[i])) {
        throw FormatException(
            "$_logTag Invalid char at $i: ${move[i]}", move, i);
      }
    }

    // Avoid throwing raw strings. Throw an Exception instead:
    if (move.length == "(3,1)->(2,1)".length &&
        move.substring(0, 4) == move.substring(7, 11)) {
      throw Exception("$_logTag Invalid Move: cannot move to the same place.");
    }
  }

  /// The standard notation for the move,
  /// e.g. "d6", "d6??", "d5-c5", "xg4", etc.
  String get notation {
    final bool useUpperCase = DB().generalSettings.screenReaderSupport;
    final int f = from;
    final String? fromStr = _squareToWmdNotation[f];
    final String? toStr = _squareToWmdNotation[to];
    switch (type) {
      case MoveType.remove:
        return useUpperCase ? "x${toStr?.toUpperCase()}" : "x$toStr";
      case MoveType.move:
        final String sep = useUpperCase ? "-" : "-";
        return useUpperCase
            ? "${fromStr?.toUpperCase()}$sep${toStr?.toUpperCase()}"
            : "$fromStr$sep$toStr";
      case MoveType.place:
      case MoveType.draw:
      case MoveType.none:
        return useUpperCase ? toStr?.toUpperCase() ?? "" : toStr ?? "";
    }
  }
}

class EngineRet {
  EngineRet(this.value, this.aiMoveType, this.extMove);

  String? value;
  ExtMove? extMove;
  AiMoveType? aiMoveType;
}
