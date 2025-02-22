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

  /// Returns a human-readable move list containing all ExtMove details,
  /// structured in a way that is friendly for Large Language Models (LLMs)
  /// such as ChatGPT.
  ///
  /// This list includes:
  /// - The move number
  /// - The SAN-like notation of the move (e.g. 'a1', 'a1-a4', 'xa4')
  /// - Merged comments from the move's own after-move comments and the
  ///   next node's starting comments
  /// - Additional ExtMove fields: side, type, from, to, boardLayout,
  ///   moveIndex, roundIndex
  ///
  /// Example output (each pair of moves in one line):
  /// 1. a1 { side=White, type=place, ... comments="..." }
  ///    a4 { side=Black, ... comments="..." }
  ///
  /// You can feed this string to ChatGPT or other LLMs for further analysis
  /// or commentary.
  String get moveListPrompt {
    // Helper: Convert numeric NAG to symbols, e.g. 1 -> "!", 2 -> "?", etc.
    String nagsToString(List<int> nags) {
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
            symbols.add('\$$nag'); // Fallback to '$num'
            break;
        }
      }
      return symbols.join(' ');
    }

    // Helper: merges current node's `comments` with next node's `startingComments`.
    String mergeComments(
        PgnNode<ExtMove> node, List<String>? nextStartComments) {
      final List<String> merged = <String>[];
      if (node.data?.comments != null && node.data!.comments!.isNotEmpty) {
        merged.addAll(node.data!.comments!);
      }
      if (nextStartComments != null && nextStartComments.isNotEmpty) {
        merged.addAll(nextStartComments);
      }
      return merged.isEmpty ? "" : merged.join(' ');
    }

    // Format a single node (ExtMove) into a bracketed detail string,
    // suitable for an LLM-friendly prompt.
    String extMoveDetails(
        PgnNode<ExtMove> node, List<String>? nextStartComments) {
      final ExtMove m = node.data!;
      final String sideStr = m.side.toString().replaceAll('PieceColor.', '');
      final String typeStr = m.type.toString().replaceAll('MoveType.', '');
      final String boardStr = (m.boardLayout != null) ? m.boardLayout! : "";

      // Merge comments
      final String mergedComments = mergeComments(node, nextStartComments);

      // Convert NAG to symbols if any
      String nagStr = "";
      if (m.nags != null && m.nags!.isNotEmpty) {
        nagStr = nagsToString(m.nags!);
      }

      // Build a details string with all extra fields.
      return "{ side=$sideStr, type=$typeStr, ${boardStr.isNotEmpty ? 'boardLayout="$boardStr", ' : ""}${m.moveIndex != null ? "moveIndex=${m.moveIndex}, " : ""}${m.roundIndex != null ? "roundIndex=${m.roundIndex}, " : ""}${nagStr.isNotEmpty ? 'nags="$nagStr", ' : ""}${mergedComments.isNotEmpty ? 'comments="${mergedComments.replaceAll('"', r'\"')}"' : ""} }";
    }

    // We iterate over the mainline nodes
    final List<PgnNode<ExtMove>> nodes = mainlineNodes;
    if (nodes.isEmpty) {
      // If no moves, but we have a custom setup.
      if (setupPosition != null) {
        return '[FEN "$setupPosition"]\n[SetUp "1"]\n\n(No moves yet)';
      }
      return "(No moves yet)";
    }

    final StringBuffer sb = StringBuffer();
    int moveNumber = 1;
    int i = 0;

    // We'll do a typical "two moves per line" approach,
    // capturing all remove moves (if any) right after a place/move.
    while (i < nodes.length) {
      sb.write("$moveNumber. ");

      // Move #1 of the pair (e.g. White)
      final PgnNode<ExtMove> firstNode = nodes[i];
      // The next node's starting comments
      final List<String>? firstNodeSuccessorComments =
          (i + 1 < nodes.length) ? nodes[i + 1].data?.startingComments : null;
      // Notation + details in braces
      sb.write(firstNode.data!.notation);
      sb.write(' ');
      sb.write(extMoveDetails(firstNode, firstNodeSuccessorComments));
      i++;

      // Handle subsequent remove moves (up to 3) if they exist
      // (since an in-game mill might remove multiple pieces).
      while (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
        final PgnNode<ExtMove> removeNode = nodes[i];
        final List<String>? removeNodeSuccessorComments =
            (i + 1 < nodes.length) ? nodes[i + 1].data?.startingComments : null;
        sb.write(' ');
        sb.write(removeNode.data!.notation);
        sb.write(' ');
        sb.write(extMoveDetails(removeNode, removeNodeSuccessorComments));
        i++;
      }

      // If there's still a next move (likely Black's move), handle it on the same line
      if (i < nodes.length) {
        sb.write(' ');
        final PgnNode<ExtMove> secondNode = nodes[i];
        final List<String>? secondNodeSuccessorComments =
            (i + 1 < nodes.length) ? nodes[i + 1].data?.startingComments : null;
        sb.write(secondNode.data!.notation);
        sb.write(' ');
        sb.write(extMoveDetails(secondNode, secondNodeSuccessorComments));
        i++;

        // Possibly more remove moves again
        while (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          final PgnNode<ExtMove> removeNode = nodes[i];
          final List<String>? removeNodeSuccessorComments =
              (i + 1 < nodes.length)
                  ? nodes[i + 1].data?.startingComments
                  : null;
          sb.write(' ');
          sb.write(removeNode.data!.notation);
          sb.write(' ');
          sb.write(extMoveDetails(removeNode, removeNodeSuccessorComments));
          i++;
        }
      }

      sb.writeln();
      moveNumber++;
    }

    const String promptHeader = """
Nine Men's Morris:

---

## Points Overview

There are 24 positions on the board, arranged across three concentric rings (outer, middle, inner). Each point belongs to one ring and has a specific location:

- **Outer Ring (8 points)**
  - a7 (corner, 2 neighbors)
  - d7 (top edge, 3 neighbors)
  - g7 (corner, 2 neighbors)
  - g4 (right edge, 3 neighbors)
  - g1 (corner, 2 neighbors)
  - d1 (bottom edge, 3 neighbors)
  - a1 (corner, 2 neighbors)
  - a4 (left edge, 3 neighbors)

- **Middle Ring (8 points)**
  - b6 (corner, 2 neighbors)
  - d6 (top edge, 4 neighbors)
  - f6 (corner, 2 neighbors)
  - f4 (right edge, 4 neighbors)
  - f2 (corner, 2 neighbors)
  - d2 (bottom edge, 4 neighbors)
  - b2 (corner, 2 neighbors)
  - b4 (left edge, 4 neighbors)

- **Inner Ring (8 points)**
  - c5 (corner, 2 neighbors)
  - d5 (top edge, 3 neighbors)
  - e5 (corner, 2 neighbors)
  - e4 (right edge, 3 neighbors)
  - e3 (corner, 2 neighbors)
  - d3 (bottom edge, 3 neighbors)
  - c3 (corner, 2 neighbors)
  - c4 (left edge, 3 neighbors)

---

## Adjacency (Direct Connections)

Each point is connected to specific neighbors. For example:

> d7 → d6, g7, a7

Use the lists below to determine legal single-step moves:

- **Outer Ring**
  - a7 → d7, a4
  - d7 → d6, g7, a7
  - g7 → g4, d7
  - g4 → f4, g1, g7
  - g1 → d1, g4
  - d1 → d2, a1, g1
  - a1 → a4, d1
  - a4 → b4, a7, a1

- **Middle Ring**
  - b6 → d6, b4
  - d6 → d5, d7, f6, b6
  - f6 → f4, d6
  - f4 → e4, g4, f2, f6
  - f2 → d2, f4
  - d2 → d3, d1, b2, f2
  - b2 → b4, d2
  - b4 → c4, a4, b6, b2

- **Inner Ring**
  - c5 → d5, c4
  - d5 → d6, e5, c5
  - e5 → e4, d5
  - e4 → f4, e3, e5
  - e3 → d3, e4
  - d3 → d2, c3, e3
  - c3 → c4, d3
  - c4 → b4, c5, c3

---

## Mill Combinations (Three in a Row)

A “mill” is formed when three of your pieces occupy any of these triplets:

- **Inner Ring Mills**
  - (c5, d5, e5)
  - (e5, e4, e3)
  - (c3, d3, e3)
  - (c5, c4, c3)

- **Middle Ring Mills**
  - (b6, d6, f6)
  - (f6, f4, f2)
  - (b2, d2, f2)
  - (b6, b4, b2)

- **Outer Ring Mills**
  - (a7, d7, g7)
  - (g7, g4, g1)
  - (a1, d1, g1)
  - (a7, a4, a1)

---

## Key Lines

### Horizontal Lines

1. (a7, d7, g7)
2. (b6, d6, f6)
3. (c5, d5, e5)
4. (a4, b4, c4)
5. (e4, f4, g4)
6. (c3, d3, e3)
7. (b2, d2, f2)
8. (a1, d1, g1)

### Vertical Lines

1. (a7, a4, a1)
2. (b6, b4, b2)
3. (c5, c4, c3)
4. (d7, d6, d5)
5. (d3, d2, d1)
6. (e5, e4, e3)
7. (f6, f4, f2)
8. (g7, g4, g1)

---

## Rings (Outer → Middle → Inner)

- **Outer Ring**: d7 → g7 → g4 → g1 → d1 → a1 → a4 → a7 → (back to d7)
- **Middle Ring**: d6 → f6 → f4 → f2 → d2 → b2 → b4 → b6 → (back to d6)
- **Inner Ring**: d5 → e5 → e4 → e3 → d3 → c3 → c4 → c5 → (back to d5)

---

## Important Cross Points

On the middle ring, these four intersections are especially crucial for mobility and control:

- **d6, f4, d2, b4**

They allow varied connections and are often central to strategic maneuvers.

---

## Notes on the Board Layout String

A typical `boardLayout` is shown by three 8-character segments (one segment per ring), for example:

```
********/********/********
```
- **First 8 characters**: Inner Ring in order (d5, e5, e4, e3, d3, c3, c4, c5)
- **Second 8 characters**: Middle Ring in order (d6, f6, f4, f2, d2, b2, b4, b6)
- **Third 8 characters**: Outer Ring in order (d7, g7, g4, g1, d1, a1, a4, a7)

Here, `'*'` indicates an empty point, `'O'` a white piece, `'@'` a black piece, etc.

---

## Action

Please comment on the Nine Men's Morris Move List below. Add comments after each move using {} to express your own opinions. Please note that you should first clear the original {} and then fill in your own. The comments are all to indicate your intentions:    """;

    const String promptFooter = """
Please directly output the modified Move List

The format is as follows:

```
1.    d2 {Blabla}   d6 {Blabla}
2.    b2 {Blabla}   f4 {Blabla}
3.    f2xd6 {Blabla} d6 {Blabla}
```

Do not use side type boardLayout or other tags in the {Blabla} part.
    """;

    // Append a brief explanation note for boardLayout.
    const String boardLayoutNote =
        "[Note: The boardLayout string is composed of three 8-character rings "
        "representing board positions. The first ring corresponds to: "
        "d5, e5, e4, d4, e3, d3, c3, c4; the second to: d6, f6, f4, f2, d2, b2, b4, b6; "
        "and the third to: d7, g7, g4, g1, d1, a1, a4, a7. "
        "'*' indicates an empty point, 'O' a white piece, and '@' a black piece.]";

    final String rawOutput = sb.toString().trim();

    if (GameController().isPositionSetup && setupPosition != null) {
      return '[FEN "$setupPosition"]\n[SetUp "1"]\n\n$rawOutput\n$boardLayoutNote';
    }

    return "$promptHeader\n$rawOutput\n$boardLayoutNote\n$promptFooter";
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
