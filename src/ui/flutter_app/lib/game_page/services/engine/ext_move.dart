// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ext_move.dart

part of '../mill.dart';

enum MoveType { place, move, remove, draw, none }

/// Check if a character represents a special piece for Zhuolu Chess
bool isZhuoluSpecialPieceChar(String char) {
  const Set<String> specialChars = <String>{
    'Y',
    'y',
    'N',
    'n',
    'F',
    'f',
    'C',
    'c',
    'A',
    'a',
    'T',
    't',
    'Z',
    'z',
    'U',
    'u',
    'E',
    'e',
    'G',
    'g',
    'W',
    'w',
    'I',
    'i',
    'K',
    'k',
    'L',
    'l',
    'B',
    'b'
  };
  return specialChars.contains(char);
}

/// Convert character to SpecialPiece enum
SpecialPiece? charToZhuoluSpecialPiece(String char) {
  switch (char.toLowerCase()) {
    case 'y':
      return SpecialPiece.huangDi; // Yellow Emperor
    case 'n':
      return SpecialPiece.nuBa; // Nüba
    case 'f':
      return SpecialPiece.yanDi; // Flame Emperor
    case 'c':
      return SpecialPiece.chiYou; // Chiyou
    case 'a':
      return SpecialPiece.changXian; // Changxian
    case 't':
      return SpecialPiece.xingTian; // Xingtian
    case 'z':
      return SpecialPiece.zhuRong; // Zhurong
    case 'u':
      return SpecialPiece.yuShi; // Yushi
    case 'e':
      return SpecialPiece.fengHou; // Fenghou
    case 'g':
      return SpecialPiece.gongGong; // Gonggong
    case 'w':
      return SpecialPiece.nuWa; // Nüwa
    case 'i':
      return SpecialPiece.fuXi; // Fuxi
    case 'k':
      return SpecialPiece.kuaFu; // Kuafu
    case 'l':
      return SpecialPiece.yingLong; // Yinglong
    case 'b':
      return SpecialPiece.fengBo; // Fengbo
    default:
      return null;
  }
}

/// Convert SpecialPiece enum to character with color
String zhuoluSpecialPieceToChar(SpecialPiece piece, PieceColor color) {
  final bool isWhite = color == PieceColor.white;

  switch (piece) {
    case SpecialPiece.huangDi:
      return isWhite ? "Y" : "y";
    case SpecialPiece.nuBa:
      return isWhite ? "N" : "n";
    case SpecialPiece.yanDi:
      return isWhite ? "F" : "f";
    case SpecialPiece.chiYou:
      return isWhite ? "C" : "c";
    case SpecialPiece.changXian:
      return isWhite ? "A" : "a";
    case SpecialPiece.xingTian:
      return isWhite ? "T" : "t";
    case SpecialPiece.zhuRong:
      return isWhite ? "Z" : "z";
    case SpecialPiece.yuShi:
      return isWhite ? "U" : "u";
    case SpecialPiece.fengHou:
      return isWhite ? "E" : "e";
    case SpecialPiece.gongGong:
      return isWhite ? "G" : "g";
    case SpecialPiece.nuWa:
      return isWhite ? "W" : "w";
    case SpecialPiece.fuXi:
      return isWhite ? "I" : "i";
    case SpecialPiece.kuaFu:
      return isWhite ? "K" : "k";
    case SpecialPiece.yingLong:
      return isWhite ? "L" : "l";
    case SpecialPiece.fengBo:
      return isWhite ? "B" : "b";
  }
}

/// Get color from special piece character
PieceColor getColorFromZhuoluChar(String char) {
  if (char.toUpperCase() == char && char.toLowerCase() != char) {
    return PieceColor.white; // Uppercase = white
  } else if (char.toLowerCase() == char && char.toUpperCase() != char) {
    return PieceColor.black; // Lowercase = black
  }
  return PieceColor.none; // Invalid character
}

class MoveParser {
  /// Check if a character represents a special piece for Zhuolu Chess
  static bool _isZhuoluSpecialPieceChar(String char) {
    return isZhuoluSpecialPieceChar(char);
  }

  MoveType parseMoveType(String move) {
    // Handle special records for Zhuolu Chess piece selection
    if (move.contains("Special Pieces")) {
      return MoveType.none;
    }

    // Handle removal moves (starting with 'x')
    if (move.startsWith("x")) {
      if (move.length == 2 && _isZhuoluSpecialPieceChar(move[1])) {
        // Zhuolu Chess special piece removal like "xY" or "xy"
        return MoveType.remove;
      } else if (move.length == 3 && RegExp(r'^x[a-g][1-8]$').hasMatch(move)) {
        // Standard coordinate removal like "xa1"
        return MoveType.remove;
      }
    }

    // Handle move operations (containing '-')
    if (move.contains("-")) {
      if (move.length == 4 &&
          _isZhuoluSpecialPieceChar(move[0]) &&
          RegExp(r'^[YyNnFfCcAaTtZzUuEeGgWwIiKkLlBb]-[a-g][1-8]$')
              .hasMatch(move)) {
        // Zhuolu Chess special piece move like "Y-a1" or "y-a1"
        return MoveType.move;
      } else if (move.length == 5 &&
          RegExp(r'^[a-g][1-8]-[a-g][1-8]$').hasMatch(move)) {
        // Standard coordinate move like "a1-a4"
        return MoveType.move;
      }
    }

    // Handle placement moves
    if (move.length == 1 && _isZhuoluSpecialPieceChar(move)) {
      // Zhuolu Chess special piece placement like "Y" or "y"
      return MoveType.place;
    } else if (move.length == 3 &&
        _isZhuoluSpecialPieceChar(move[0]) &&
        RegExp(r'^[YyNnFfCcAaTtZzUuEeGgWwIiKkLlBb][a-g][1-7]$')
            .hasMatch(move)) {
      // Zhuolu Chess special piece placement with coordinate like "Yf2"
      return MoveType.place;
    } else if (move.length == 2 && RegExp(r'^[a-g][1-8]$').hasMatch(move)) {
      // Standard coordinate placement like "a1"
      return MoveType.place;
    } else if (move.length == 2 && (move == "O@" || move == "@O")) {
      // Normal piece placement for Zhuolu Chess
      return MoveType.place;
    }

    // Handle special cases
    if (move == "draw") {
      logger.i("[TODO] Computer request draw");
      return MoveType.draw;
    } else if (move == "(none)" || move == "none") {
      logger.i("MoveType is (none).");
      return MoveType.none;
    }

    // If no pattern matches, throw format exception
    throw const FormatException();
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
    this.specialPiece,
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
    // Auto-extract special piece if not provided (e.g., "Yf2", "xY", "Y-a1")
    specialPiece ??= _extractSpecialPieceFromNotation(move, side);
    _checkLegal(move);
  }

  /// Constructor for creating ExtMove from Zhuolu Chess special piece notation
  ExtMove.fromZhuoluNotation(
    String notation, {
    required this.side,
    this.boardLayout,
    this.moveIndex,
    this.roundIndex,
    super.nags,
    super.startingComments,
    super.comments,
  })  : move = notation,
        type = MoveParser().parseMoveType(notation),
        to = _parseToSquare(notation),
        specialPiece = _extractSpecialPieceFromNotation(notation, side),
        super(san: notation) {
    _checkLegal(notation);
  }

  /// Extract SpecialPiece from Zhuolu Chess notation
  static SpecialPiece? _extractSpecialPieceFromNotation(
      String notation, PieceColor side) {
    // Handle placement moves like "Y" or "y"
    if (notation.length == 1 && isZhuoluSpecialPieceChar(notation)) {
      return charToZhuoluSpecialPiece(notation);
    }

    // Handle removal moves like "xY" or "xy"
    if (notation.startsWith("x") &&
        notation.length == 2 &&
        isZhuoluSpecialPieceChar(notation[1])) {
      return charToZhuoluSpecialPiece(notation[1]);
    }

    // Handle move operations like "Y-a1" or "y-a1"
    if (notation.contains("-") &&
        notation.length == 4 &&
        isZhuoluSpecialPieceChar(notation[0])) {
      return charToZhuoluSpecialPiece(notation[0]);
    }

    // Handle placement with coordinate like "Yf2"
    if (notation.length == 3 && isZhuoluSpecialPieceChar(notation[0])) {
      return charToZhuoluSpecialPiece(notation[0]);
    }

    return null;
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

  /// Special piece type used for this move (Zhuolu Chess)
  SpecialPiece? specialPiece;

  /// Move quality evaluation
  MoveQuality? quality;

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
      final bool hasQualityNags =
          allNags.any((int nag) => nag >= 1 && nag <= 4);
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

    // Handle Zhuolu Chess special piece moves
    if (move.contains("-")) {
      if (move.length == 4 && MoveParser._isZhuoluSpecialPieceChar(move[0])) {
        // Zhuolu Chess special piece move like "Y-a1" - from square is determined by special piece location
        return -1; // Special piece from square needs to be determined by game state
      } else if (move.length == 5 && !move.contains("(")) {
        // Standard move notation like "a1-a4"
        final List<String> parts = move.split("-");
        if (parts.length == 2) {
          return _standardNotationToSquare(parts[0].trim());
        }
      }
    }

    return -1;
  }

  static int _parseToSquare(String move) {
    MoveParser().parseMoveType(move);

    // Handle special records for Zhuolu Chess
    if (move.contains("Special Pieces")) {
      return -1; // No specific square for special piece selection records
    }

    // Handle Zhuolu Chess special piece notation
    if (move.startsWith("x") &&
        move.length == 2 &&
        MoveParser._isZhuoluSpecialPieceChar(move[1])) {
      // Remove notation like "xY" - for special pieces, we don't have a specific square
      return -1; // Special piece removal doesn't map to a specific square
    } else if (move.startsWith("x") && move.length == 3) {
      // Remove notation like "xa1"
      final String target = move.substring(1).trim();
      return _standardNotationToSquare(target);
    } else if (move.contains("-")) {
      if (move.length == 4 && MoveParser._isZhuoluSpecialPieceChar(move[0])) {
        // Zhuolu Chess special piece move like "Y-a1"
        final List<String> parts = move.split("-");
        if (parts.length == 2) {
          return _standardNotationToSquare(parts[1].trim());
        }
      } else if (move.length == 5) {
        // Standard move notation like "a1-a4"
        final List<String> parts = move.split("-");
        if (parts.length == 2) {
          return _standardNotationToSquare(parts[1].trim());
        }
      }
    } else if (move.length == 1 && MoveParser._isZhuoluSpecialPieceChar(move)) {
      // Zhuolu Chess special piece placement like "Y" - no specific square
      return -1; // Special piece placement doesn't map to a specific square initially
    } else if (move.length == 3 &&
        MoveParser._isZhuoluSpecialPieceChar(move[0]) &&
        RegExp(r'^[YyNnFfCcAaTtZzUuEeGgWwIiKkLlBb][a-g][1-7]$')
            .hasMatch(move)) {
      // Zhuolu Chess special piece placement with coordinate like "Yf2"
      final String target = move.substring(1).trim();
      return _standardNotationToSquare(target);
    } else if (RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      // Standard place notation like "a1"
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
      "d1": 28, "a1": 29, "a4": 30, "a7": 31
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
    31: "a7"
  };

  static String sqToNotation(int sq) {
    final String? ret = _squareToWmdNotation[sq];
    return ret ?? "";
  }

  /// Validate the move string format.
  static void _checkLegal(String move) {
    // Handle special cases first
    if (move == "draw" || move == "(none)" || move == "none") {
      return; // no further checks
    }

    // Allow special records for Zhuolu Chess
    if (move.contains("Special Pieces")) {
      return; // Special records are always valid
    }

    // Check Zhuolu Chess special piece notation patterns
    if (move.length == 1 && MoveParser._isZhuoluSpecialPieceChar(move)) {
      // Zhuolu Chess special piece placement like "Y" or "y"
      return;
    }

    if (move.startsWith("x") &&
        move.length == 2 &&
        MoveParser._isZhuoluSpecialPieceChar(move[1])) {
      // Zhuolu Chess special piece removal like "xY" or "xy"
      return;
    }

    if (move.length == 4 &&
        MoveParser._isZhuoluSpecialPieceChar(move[0]) &&
        RegExp(r'^[YyNnFfCcAaTtZzUuEeGgWwIiKkLlBb]-[a-g][1-8]$')
            .hasMatch(move)) {
      // Zhuolu Chess special piece move like "Y-a1" or "y-a1"
      return;
    }

    if (move.length == 3 &&
        MoveParser._isZhuoluSpecialPieceChar(move[0]) &&
        RegExp(r'^[YyNnFfCcAaTtZzUuEeGgWwIiKkLlBb][a-g][1-7]$')
            .hasMatch(move)) {
      // Zhuolu Chess special piece placement with coordinate like "Yf2"
      return;
    }

    // Check standard notation patterns
    if (RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      // Standard place move like "a1"
      return;
    }

    if (move.startsWith("x") && RegExp(r'^x[a-g][1-7]$').hasMatch(move)) {
      // Standard remove move like "xa1"
      return;
    }

    if (RegExp(r'^[a-g][1-7]-[a-g][1-7]$').hasMatch(move)) {
      // Standard move like "a1-a4"
      final List<String> parts = move.split("-");
      if (parts[0] == parts[1]) {
        throw Exception(
            "$_logTag Invalid Move: cannot move to the same place.");
      }
      return;
    }

    // Check normal piece notation for Zhuolu Chess
    if (move.length == 1 && (move == "O" || move == "@")) {
      // Normal piece placement for Zhuolu Chess
      return;
    }

    throw FormatException("$_logTag Invalid Move: ", move);
  }

  /// Get the special piece character for Zhuolu Chess notation
  /// Returns the assigned letter based on piece type and color
  String? get _specialPieceChar {
    if (specialPiece == null) {
      return null;
    }
    return zhuoluSpecialPieceToChar(specialPiece!, side);
  }

  /// The standard notation for the move,
  /// e.g. "d6", "d6??", "d5-c5", "xg4", etc.
  /// For Zhuolu Chess, uses special piece characters instead of coordinates when applicable.
  String get notation {
    // Handle special records for Zhuolu Chess piece selection
    if (move.contains("Special Pieces")) {
      return move; // Return the original move string for special records
    }

    final bool useUpperCase = DB().generalSettings.screenReaderSupport;
    final int f = from;
    final String? fromStr = _squareToWmdNotation[f];
    final String? toStr = _squareToWmdNotation[to];

    String baseNotation;
    switch (type) {
      case MoveType.remove:
        // For Zhuolu Chess special pieces, use piece character
        if (DB().ruleSettings.zhuoluMode && specialPiece != null) {
          final String? pieceChar = _specialPieceChar;
          if (pieceChar != null) {
            baseNotation =
                useUpperCase ? "x${pieceChar.toUpperCase()}" : "x$pieceChar";
          } else {
            baseNotation =
                useUpperCase ? "x${toStr?.toUpperCase()}" : "x$toStr";
          }
        } else {
          baseNotation = useUpperCase ? "x${toStr?.toUpperCase()}" : "x$toStr";
        }
        break;
      case MoveType.move:
        final String sep = useUpperCase ? "-" : "-";
        // For Zhuolu Chess special pieces, use piece character for from/to squares
        if (DB().ruleSettings.zhuoluMode && specialPiece != null) {
          final String? pieceChar = _specialPieceChar;
          if (pieceChar != null) {
            // Use piece character for the piece being moved
            final String fromPiece =
                useUpperCase ? pieceChar.toUpperCase() : pieceChar;
            final String toSquare =
                useUpperCase ? toStr?.toUpperCase() ?? "" : toStr ?? "";
            baseNotation = "$fromPiece$sep$toSquare";
          } else {
            baseNotation = useUpperCase
                ? "${fromStr?.toUpperCase()}$sep${toStr?.toUpperCase()}"
                : "$fromStr$sep$toStr";
          }
        } else {
          baseNotation = useUpperCase
              ? "${fromStr?.toUpperCase()}$sep${toStr?.toUpperCase()}"
              : "$fromStr$sep$toStr";
        }
        break;
      case MoveType.place:
        // For Zhuolu Chess special pieces, use piece character instead of coordinate
        if (DB().ruleSettings.zhuoluMode && specialPiece != null) {
          final String? pieceChar = _specialPieceChar;
          if (pieceChar != null) {
            // If the raw move already encodes piece+coordinate (e.g. "Yf2"), prefer it
            if (move.length == 3 && isZhuoluSpecialPieceChar(move[0])) {
              baseNotation = useUpperCase ? move.toUpperCase() : move;
            } else {
              baseNotation = useUpperCase ? pieceChar.toUpperCase() : pieceChar;
            }
          } else {
            // Fallback to normal piece notation
            final bool isWhite = side == PieceColor.white;
            baseNotation = isWhite ? "O" : "@";
          }
        } else {
          baseNotation =
              useUpperCase ? toStr?.toUpperCase() ?? "" : toStr ?? "";
        }
        break;
      case MoveType.draw:
      case MoveType.none:
        baseNotation = useUpperCase ? toStr?.toUpperCase() ?? "" : toStr ?? "";
        break;
    }

    return baseNotation;
  }
}

class EngineRet {
  EngineRet(this.value, this.aiMoveType, this.extMove);

  String? value;
  ExtMove? extMove;
  AiMoveType? aiMoveType;
}
