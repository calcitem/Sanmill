// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ext_move.dart

part of '../mill.dart';

enum MoveType { place, move, remove, draw, none }

class MoveParser {
  MoveType parseMoveType(String move) {
    if (move.startsWith("x") && move.length == 3) {
      return MoveType.remove;
    } else if (move.contains("-") && move.length == 5) {
      return MoveType.move;
    } else if (RegExp(r'^[a-g][1-8]$').hasMatch(move) && move.length == 2) {
      return MoveType.place;
    } else if (move == "draw") {
      logger.i("[TODO] Computer request draw");
      return MoveType.draw;
    } else if (move == "(none)" || move == "none") {
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
    this.roundIndex,
    this.preferredRemoveTarget,
    super.nags,
    super.startingComments,
    super.comments,
  }) : type = MoveParser().parseMoveType(move),
       to = _parseToSquare(move),
       // Put all your own field initializations first ...
       super(
         // ...then call super(...) last
         san: move,
       ) {
    _checkLegal(move);
  }

  /// The standard notation move string, e.g. "a1", "a1-a4", "xa1"
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

  /// roundIndex is a separate concept from [moveIndex].
  /// If one side (White or Black) performs multiple consecutive moves,
  /// they all share the same half-round index. Once we switch side
  /// (e.g. from White to Black), we stay in the same round number;
  /// only when switching **back** from Black to White do we increment
  /// this round index. Thus, each cycle (White half + Black half)
  /// forms one complete round.
  int? roundIndex;

  /// Preferred target for intervention capture pairing.
  ///
  /// When a placing move is immediately followed by a remove move (e.g. b4xb2),
  /// this records the first removed square (b2). During replay, this helps the
  /// engine select the correct intervention capture line and ensures the second
  /// capture stays on the same line.
  int? preferredRemoveTarget;

  /// Move quality evaluation
  MoveQuality? quality;

  /// Whether this move is part of a variation (not mainline)
  bool? isVariation;

  /// Depth level of the variation (0 for mainline, 1+ for nested variations)
  int? variationDepth;

  /// Branch graph metadata for tree visualization
  /// Indicates which columns have active branches at this move
  List<bool>? branchColumns;

  /// The column index where this move is displayed in the branch tree
  int? branchColumn;

  /// Branch line type: 'continue', 'fork', 'join', 'end'
  String? branchLineType;

  /// Whether this is the last child of its parent (for drawing └ vs ├)
  bool? isLastSibling;

  /// Index among siblings (0 = first child, 1 = second, etc.)
  int? siblingIndex;

  /// Convert MoveQuality to numeric NAG (Numeric Annotation Glyph)
  /// Good moves: ! (1), !! (3)
  /// Bad moves: ? (2), ?? (4)
  static int? moveQualityToNag(MoveQuality? quality) {
    if (quality == null) {
      return null;
    }

    switch (quality) {
      case MoveQuality.minorGoodMove:
        return 1; // !
      case MoveQuality.majorGoodMove:
        return 3; // !!
      case MoveQuality.minorBadMove:
        return 2; // ?
      case MoveQuality.majorBadMove:
        return 4; // ??
      case MoveQuality.normal:
        return null; // No NAG for normal moves
    }
  }

  /// Convert numeric NAG to MoveQuality
  /// NAG 1 = !, 2 = ?, 3 = !!, 4 = ??
  static MoveQuality? nagToMoveQuality(int nag) {
    switch (nag) {
      case 1:
        return MoveQuality.minorGoodMove; // !
      case 2:
        return MoveQuality.minorBadMove; // ?
      case 3:
        return MoveQuality.majorGoodMove; // !!
      case 4:
        return MoveQuality.majorBadMove; // ??
      default:
        return null; // Unknown NAG, no quality assigned
    }
  }

  /// Get all NAGs for this move, including quality-derived NAG
  List<int> getAllNags() {
    final List<int> allNags = <int>[];

    // Add existing NAGs
    if (nags != null) {
      allNags.addAll(nags!);
    }

    // Add quality-derived NAG if not already present and no conflicting quality NAGs exist
    final int? qualityNag = moveQualityToNag(quality);
    if (qualityNag != null && !allNags.contains(qualityNag)) {
      // Check if there are any existing quality-related NAGs (1, 2, 3, 4)
      final bool hasQualityNags = allNags.any(
        (int nag) => nag >= 1 && nag <= 4,
      );
      if (!hasQualityNags) {
        allNags.add(qualityNag);
      }
    }

    return allNags;
  }

  /// Set quality from NAGs, prioritizing explicit quality NAGs over existing quality
  void updateQualityFromNags() {
    if (nags == null || nags!.isEmpty) {
      return;
    }

    // Look for quality-related NAGs (1, 2, 3, 4) and use the first one found
    for (final int nag in nags!) {
      if (nag >= 1 && nag <= 4) {
        final MoveQuality? nagQuality = nagToMoveQuality(nag);
        if (nagQuality != null) {
          quality = nagQuality;
          break; // Use first quality NAG found
        }
      }
    }
  }

  static const String _logTag = "[Move]";

  /// 'from' square if type==move; otherwise -1.
  int get from {
    if (type != MoveType.move) {
      return -1;
    }

    // Check if it's standard notation
    if (move.contains("-") && move.length == 5 && !move.contains("(")) {
      // Move notation like "a1-a4"
      final List<String> parts = move.split("-");
      if (parts.length == 2) {
        return _standardNotationToSquare(parts[0].trim());
      }
    }

    return -1;
  }

  static int _parseToSquare(String move) {
    MoveParser().parseMoveType(move);

    // Check if it's standard notation
    if (move.startsWith("x") && move.length == 3) {
      // Remove notation like "xa1"
      final String target = move.substring(1).trim();
      return _standardNotationToSquare(target);
    } else if (move.contains("-") && move.length == 5) {
      // Move notation like "a1-a4"
      final List<String> parts = move.split("-");
      if (parts.length == 2) {
        return _standardNotationToSquare(parts[1].trim());
      }
    } else if (RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      // Place notation like "a1"
      return _standardNotationToSquare(move);
    }

    return -1;
  }

  static int _standardNotationToSquare(String notation) {
    final Map<String, int> standardToSquare = <String, int>{
      // Inner ring
      "d5": 8, "e5": 9, "e4": 10, "e3": 11,
      "d3": 12, "c3": 13, "c4": 14, "c5": 15,
      // Middle ring
      "d6": 16, "f6": 17, "f4": 18, "f2": 19,
      "d2": 20, "b2": 21, "b4": 22, "b6": 23,
      // Outer ring
      "d7": 24, "g7": 25, "g4": 26, "g1": 27,
      "d1": 28, "a1": 29, "a4": 30, "a7": 31,
    };

    return standardToSquare[notation.toLowerCase()] ?? -1;
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
    31: "a7",
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

    // Check standard notation patterns
    if (RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      // Place move like "a1"
      return;
    }

    if (move.startsWith("x") && RegExp(r'^x[a-g][1-7]$').hasMatch(move)) {
      // Remove move like "xa1"
      return;
    }

    if (RegExp(r'^[a-g][1-7]-[a-g][1-7]$').hasMatch(move)) {
      // Move like "a1-a4"
      final List<String> parts = move.split("-");
      if (parts[0] == parts[1]) {
        throw Exception(
          "$_logTag Invalid Move: cannot move to the same place.",
        );
      }
      return;
    }

    throw FormatException("$_logTag Invalid Move: ", move);
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
