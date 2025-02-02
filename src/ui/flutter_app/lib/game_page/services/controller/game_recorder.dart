// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// GameRecorder holds the move history and also maintains
/// a PGN tree internally. It used to extend PointedList\<ExtMove>,
/// but now only provides PGN-based APIs.
class GameRecorder {
  GameRecorder({
    this.lastPositionWithRemove,
    this.setupPosition,
  });

  /// The user's last position with remove operation, if any.
  String? lastPositionWithRemove;

  /// Custom setup position. If not null, it will be used instead of current fen.
  String? setupPosition;

  /// PGN tree root node.
  /// We allow multiple branches and track an active node for the "current" path.
  final PgnNode<ExtMove> _pgnRoot = PgnNode<ExtMove>();

  /// A pointer to the current node, representing the "HEAD" of the active variation.
  ///
  /// If null, it means no moves yet or we are effectively at root with no child.
  PgnNode<ExtMove>? activeNode;

  /// A getter to expose the root node, if external code wants to examine it.
  PgnNode<ExtMove> get pgnRoot => _pgnRoot;

  /// Returns all the moves from the main line (children[0] chain) as a list.
  List<ExtMove> get mainlineMoves => _pgnRoot.mainline().toList();

  /// If you had an old `isAtEnd()` usage, either remove it or define a logic like:
  bool isAtEnd() {
    // For example, we say we are "at end" if activeNode is null or has no children.
    final PgnNode<ExtMove>? node = activeNode;
    if (node == null) {
      return true;
    }
    return node.children.isEmpty;
  }

  /// Appends a new move at the end of the current active line.
  /// If activeNode is null, we treat that as if we're at the root (no moves).
  void appendMove(ExtMove move) {
    if (activeNode == null) {
      // No moves yet or just reset. Walk down the mainline from root to the last child, if any.
      PgnNode<ExtMove> tail = _pgnRoot;
      while (tail.children.isNotEmpty) {
        tail = tail.children.first;
      }
      final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
      newChild.parent = tail; // Set parent pointer
      tail.children.add(newChild);
      activeNode = newChild;
    } else {
      // We already have an active node. We'll add the new move as child[0] of that node
      // so it extends the active line. If that node already had children, we insert at front.
      final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
      newChild.parent = activeNode; // parent is the old active node
      activeNode!.children.insert(0, newChild);
      activeNode = newChild;
    }
  }

  /// Appends a new move only if it's different from the current active move.
  void appendMoveIfDifferent(ExtMove newMove) {
    final ExtMove? curr = activeNode?.data;
    if (curr == null || curr.move != newMove.move) {
      // or compare other fields if you prefer
      appendMove(newMove);
    }
  }

  /// Creates a new branch from a given mainline index and makes it the new "main" child.
  void branchNewMove(int fromIndex, ExtMove newMove) {
    PgnNode<ExtMove> node = _pgnRoot;
    for (int i = 0; i < fromIndex; i++) {
      if (node.children.isNotEmpty) {
        node = node.children.first;
      } else {
        break;
      }
    }
    final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(newMove);
    newChild.parent = node; // link parent
    node.children.insert(0, newChild);
    activeNode = newChild;
  }

  /// Create a new branch node under the current activeNode and make activeNode point to it
  void branchNewMoveFromActiveNode(ExtMove newMove) {
    // If the current activeNode is null, it means we are at the root with no moves made
    // Treat it as the "root node"
    final PgnNode<ExtMove> where = activeNode ?? _pgnRoot;

    // Construct a new child node
    final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(newMove);
    newChild.parent = where;

    // Insert at the front to make it the "main branch"
    where.children.insert(0, newChild);

    // Update activeNode to the new branch
    activeNode = newChild;
  }

  /// Returns a textual representation of the move history, including NAG and comments.
  /// Implementation is unchanged except it now uses mainlineMoves instead of a pointer-based approach.
  String get moveHistoryText {
    String buildTagPairs() {
      if (setupPosition != null) {
        return '[FEN "$setupPosition"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().position.fen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

    final List<ExtMove> line = _pgnRoot.mainline().toList();
    if (line.isEmpty) {
      if (GameController().isPositionSetup) {
        return buildTagPairs();
      }
      return "";
    }

    final StringBuffer sb = StringBuffer();
    int num = 1;
    int i = 0;

    /// Build one step of notation (up to two moves per line).
    void buildStandardNotation() {
      const String sep = "    "; // Just for formatting alignment
      if (i < line.length) {
        // For the main move (either place/move/remove/draw/etc.)
        sb.write(sep);
        sb.write(_getRichMoveNotation(line[i++]));
      }
      // If the next moves are removal, handle them as well.
      for (int round = 0; round < 3; round++) {
        if (i < line.length && line[i].type == MoveType.remove) {
          sb.write(_getRichMoveNotation(line[i++]));
        }
      }
    }

    // If the position is a custom setup, print the FEN tags first.
    if (GameController().isPositionSetup) {
      sb.write(buildTagPairs());
    }

    // Walk through all moves in pairs (the typical chess-like formatting).
    while (i < line.length) {
      // TODO: When AI draw, print number but not move
      sb.writeNumber(num++);
      buildStandardNotation();
      buildStandardNotation();
      if (i < line.length) {
        sb.writeln();
      }
    }

    return sb.toString();
  }

  /// Converts an ExtMove into a notation string that includes NAG and comments.
  /// Example output: "d6!? {some comment}"
  String _getRichMoveNotation(ExtMove move) {
    final StringBuffer sb = StringBuffer();

    // 1) The base notation, e.g. "d6", "d5-c5", etc.
    sb.write(move.notation);

    // 2) Append NAG symbols if present (e.g. "!", "??" etc.)
    if (move.nags != null && move.nags!.isNotEmpty) {
      sb.write(' ');
      sb.write(_nagsToString(move.nags!));
    }

    // 3) Collect comments: both startingComments and comments
    final List<String> allComments = <String>[];
    if (move.startingComments != null) {
      allComments.addAll(move.startingComments!);
    }
    if (move.comments != null && move.comments!.isNotEmpty) {
      allComments.addAll(move.comments!);
    }

    // 4) If there are comments, enclose them in braces { ... }
    if (allComments.isNotEmpty) {
      sb.write(' {');
      sb.write(allComments.join(' '));
      sb.write('}');
    }

    return sb.toString();
  }

  /// Converts numeric NAGs (1,2,3,4,5,6...) into conventional notation (!, ?, !!, ??, etc.)
  String _nagsToString(List<int> nags) {
    final List<String> symbols = <String>[];
    for (final int nag in nags) {
      switch (nag) {
        case 1:
          symbols.add('!');
          break;
        case 2:
          symbols.add('?');
          break;
        case 3:
          symbols.add('!!');
          break;
        case 4:
          symbols.add('??');
          break;
        case 5:
          symbols.add('!?');
          break;
        case 6:
          symbols.add('?!');
          break;
        default:
          // If unknown, we keep the standard $7, $8, etc.
          symbols.add('\$$nag');
          break;
      }
    }
    // Join multiple NAGs with space, e.g. "!? $22"
    return symbols.join(' ');
  }
}
