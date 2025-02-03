// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// GameRecorder holds the move history and maintains
/// a PGN tree internally. It now provides PGN-based APIs.
class GameRecorder {
  GameRecorder({
    this.lastPositionWithRemove,
    this.setupPosition,
  });

  /// The user's last position with remove operation, if any.
  String? lastPositionWithRemove;

  /// Custom setup position. If not null, it will be used instead of current FEN.
  String? setupPosition;

  /// PGN tree root node.
  /// Multiple branches are allowed; activeNode tracks the "current" branch.
  final PgnNode<ExtMove> _pgnRoot = PgnNode<ExtMove>();

  /// A pointer to the current node representing the HEAD of the active variation.
  /// If null, no moves have been made yet (or we are at root with no child).
  PgnNode<ExtMove>? activeNode;

  /// Getter to expose the root node.
  PgnNode<ExtMove> get pgnRoot => _pgnRoot;

  /// Returns all the moves from the main line (children[0] chain) as a list.
  List<ExtMove> get mainlineMoves => _pgnRoot.mainline().toList();

  /// Returns whether we are at the end of the move history.
  bool isAtEnd() {
    final PgnNode<ExtMove>? node = activeNode;
    if (node == null) {
      return true;
    }
    return node.children.isEmpty;
  }

  /// Appends a new move at the end of the current active line.
  void appendMove(ExtMove move) {
    if (activeNode == null) {
      // No moves yet or just reset. Walk down the mainline from root to the last child.
      PgnNode<ExtMove> tail = _pgnRoot;
      while (tail.children.isNotEmpty) {
        tail = tail.children.first;
      }
      final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
      newChild.parent = tail; // Set parent pointer.
      tail.children.add(newChild);
      activeNode = newChild;
    } else {
      // Extend the active line by inserting new move at the front of children.
      final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
      newChild.parent = activeNode;
      activeNode!.children.insert(0, newChild);
      activeNode = newChild;
    }
  }

  /// Appends a new move only if it differs from the current active move.
  void appendMoveIfDifferent(ExtMove newMove) {
    final ExtMove? curr = activeNode?.data;
    if (curr == null || curr.move != newMove.move) {
      appendMove(newMove);
    }
  }

  /// Creates a new branch from a given mainline index and makes it the new "main" branch.
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
    newChild.parent = node;
    node.children.insert(0, newChild);
    activeNode = newChild;
  }

  /// Creates a new branch node under the current activeNode and sets it as active.
  void branchNewMoveFromActiveNode(ExtMove newMove) {
    final PgnNode<ExtMove> where = activeNode ?? _pgnRoot;
    final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(newMove);
    newChild.parent = where;
    where.children.insert(0, newChild);
    activeNode = newChild;
  }

  /// Returns a textual representation of the move history including NAG and comments.
  /// In this updated implementation, the node's own comments (i.e. after-move comments)
  /// and the startingComments of its successor are merged and displayed together.
  String get moveHistoryText {
    // Helper to build tag pair header (e.g. FEN, SetUp).
    String buildTagPairs() {
      if (setupPosition != null) {
        return '[FEN "$setupPosition"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().position.fen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

    // Obtain mainline nodes (not just moves) for richer comment merging.
    final List<PgnNode<ExtMove>> nodes = mainlineNodes;
    if (nodes.isEmpty) {
      if (GameController().isPositionSetup) {
        return buildTagPairs();
      }
      return "";
    }

    final StringBuffer sb = StringBuffer();
    int num = 1;
    int i = 0;

    // Build one step of notation (up to two moves per line).
    void buildStandardNotation() {
      const String sep = "    "; // For formatting alignment.
      if (i < nodes.length) {
        // Retrieve current node and the next node's startingComments (if available).
        final PgnNode<ExtMove> currentNode = nodes[i];
        final List<String>? nextStartingComments =
            (i + 1 < nodes.length) ? nodes[i + 1].data!.startingComments : null;
        sb.write(sep);
        sb.write(
            _getRichMoveNotationForNode(currentNode, nextStartingComments));
        i++;
      }
      // Process subsequent removal moves (up to 3) if present.
      for (int round = 0; round < 3; round++) {
        if (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          final PgnNode<ExtMove> currentNode = nodes[i];
          final List<String>? nextStartingComments = (i + 1 < nodes.length)
              ? nodes[i + 1].data!.startingComments
              : null;
          sb.write(
              _getRichMoveNotationForNode(currentNode, nextStartingComments));
          i++;
        }
      }
    }

    // Write FEN tag pairs if a custom position is set.
    if (GameController().isPositionSetup) {
      sb.write(buildTagPairs());
    }

    // Walk through the moves in pairs (like typical chess notation).
    while (i < nodes.length) {
      sb.writeNumber(num++);
      buildStandardNotation();
      buildStandardNotation();
      if (i < nodes.length) {
        sb.writeln();
      }
    }

    return sb.toString();
  }

  /// Returns a list of PGN nodes along the mainline (children[0] chain).
  List<PgnNode<ExtMove>> get mainlineNodes {
    final List<PgnNode<ExtMove>> nodes = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove> current = _pgnRoot;
    while (current.children.isNotEmpty) {
      current = current.children.first;
      nodes.add(current);
    }
    return nodes;
  }

  /// Converts a PGN node into a rich move notation string.
  ///
  /// This method takes the node's own after-move comments (stored in [move.comments])
  /// and, if available, merges them with the [nextStartingComments] (which come from
  /// the next node's startingComments). This implements the requirement to merge
  /// the node's comments with its successor's startingComments.
  String _getRichMoveNotationForNode(PgnNode<ExtMove> node,
      [List<String>? nextStartingComments]) {
    // Force non-null for node.data since mainlineNodes should not include nodes with null data.
    final ExtMove move = node.data!;
    final StringBuffer sb = StringBuffer();

    // 1) Write the base move notation (e.g. "d6", "d5-c5", etc.).
    sb.write(move.notation);

    // 2) Append NAG symbols if present.
    if (move.nags != null && move.nags!.isNotEmpty) {
      sb.write(' ');
      sb.write(_nagsToString(move.nags!));
    }

    // 3) Merge the node's own after-move comments with next node's startingComments.
    // Note: The current node's startingComments are intentionally not displayed,
    // as they belong to the previous move.
    final List<String> mergedComments = <String>[];
    if (move.comments != null && move.comments!.isNotEmpty) {
      mergedComments.addAll(move.comments!);
    }
    if (nextStartingComments != null && nextStartingComments.isNotEmpty) {
      mergedComments.addAll(nextStartingComments);
    }

    // 4) If there are any merged comments, enclose them in braces.
    if (mergedComments.isNotEmpty) {
      sb.write(' {');
      sb.write(mergedComments.join(' '));
      sb.write('}');
    }

    return sb.toString();
  }

  /// Converts numeric NAGs (1, 2, 3, ...) into conventional symbols (e.g. "!", "?", etc.).
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
          // For unknown NAGs, keep the standard format $n.
          symbols.add('\$$nag');
          break;
      }
    }
    // Join multiple NAG symbols with space, e.g. "!? $22".
    return symbols.join(' ');
  }
}
