// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// GameRecorder holds the move history and maintains
/// a PGN tree internally. It now provides PGN-based APIs.
class GameRecorder {
  GameRecorder({this.lastPositionWithRemove, this.setupPosition});

  /// The user's last position with remove operation, if any.
  String? lastPositionWithRemove;

  /// Custom setup position. If not null, it will be used instead of current FEN.
  String? setupPosition;

  /// Notifier that fires whenever a move is made or undone.
  /// Listeners can use this to react to move changes in business logic.
  final ValueNotifier<int> moveCountNotifier = ValueNotifier<int>(0);

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

  /// Get the path from root to active node as a list of moves
  List<ExtMove> get currentPath {
    final List<ExtMove> path = <ExtMove>[];
    PgnNode<ExtMove>? node = activeNode;
    while (node != null && node.data != null) {
      path.insert(0, node.data!);
      node = node.parent;
    }
    return path;
  }

  /// Get all variations (alternative moves) at the active node
  /// Returns a list of sibling nodes (excluding the active node itself)
  List<PgnNode<ExtMove>> getVariationsAtActiveNode() {
    final PgnNode<ExtMove>? parent = activeNode?.parent;
    if (parent == null) {
      return <PgnNode<ExtMove>>[];
    }

    // Return all siblings except the active node
    return parent.children
        .where((PgnNode<ExtMove> node) => node != activeNode)
        .toList();
  }

  /// Switch to a specific variation by setting it as the active branch
  /// This makes the variation node the new active node
  void switchToVariation(PgnNode<ExtMove> variationNode) {
    if (variationNode.parent != null) {
      activeNode = variationNode;
      moveCountNotifier.value = currentPath.length;
    }
  }

  /// Check if the active node has any variations (sibling branches)
  bool hasVariationsAtActiveNode() {
    return getVariationsAtActiveNode().isNotEmpty;
  }

  /// Get the next moves available from the current active position
  /// Returns the first child (mainline continuation) and any variation siblings
  List<PgnNode<ExtMove>> getNextMoveOptions() {
    final PgnNode<ExtMove> node = activeNode ?? _pgnRoot;
    return node.children;
  }

  /// Check if there are multiple move options from the current position
  bool hasMultipleNextMoves() {
    return getNextMoveOptions().length > 1;
  }

  /// Returns whether we are at the end of the move history.
  bool isAtEnd() {
    final PgnNode<ExtMove>? node = activeNode;
    if (node == null) {
      return true;
    }
    return node.children.isEmpty;
  }

  /// Resets the game recorder by clearing all moves and resetting the active node.
  void reset() {
    _pgnRoot.children.clear();
    activeNode = null;
    lastPositionWithRemove = null;
    moveCountNotifier.value = 0;
  }

  /// Appends a new move at the end of the current active line.
  /// If a move already exists at this position with different notation,
  /// creates a new variation branch.
  void appendMove(ExtMove move, {bool createVariation = true}) {
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
      // Check if active node already has children
      if (activeNode!.children.isNotEmpty && createVariation) {
        // Check if the new move is different from existing first child
        final ExtMove? existingMove = activeNode!.children.first.data;
        if (existingMove != null && existingMove.move != move.move) {
          // Create a variation: add as a new child (not at position 0)
          final PgnNode<ExtMove> variationNode = PgnNode<ExtMove>(move);
          variationNode.parent = activeNode;
          activeNode!.children.add(variationNode);
          activeNode = variationNode;
        } else if (existingMove != null && existingMove.move == move.move) {
          // Same move exists, just follow it
          activeNode = activeNode!.children.first;
        } else {
          // Extend normally
          final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
          newChild.parent = activeNode;
          activeNode!.children.insert(0, newChild);
          activeNode = newChild;
        }
      } else {
        // Extend the active line by inserting new move at the front of children.
        final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
        newChild.parent = activeNode;
        activeNode!.children.insert(0, newChild);
        activeNode = newChild;
      }
    }
    // Notify that move count has changed
    moveCountNotifier.value = currentPath.length;
  }

  /// Appends a new move only if it differs from the current active move.
  void appendMoveIfDifferent(ExtMove newMove) {
    final PgnNode<ExtMove>? node = activeNode;
    if (node == null) {
      appendMove(newMove);
      return;
    }

    // Check if there's already a child with this move
    final PgnNode<ExtMove>? existingChild = node.children
        .cast<PgnNode<ExtMove>?>()
        .firstWhere(
          (PgnNode<ExtMove>? child) => child?.data?.move == newMove.move,
          orElse: () => null,
        );

    if (existingChild != null) {
      // Move already exists, just follow it
      activeNode = existingChild;
      moveCountNotifier.value = currentPath.length;
    } else {
      // New move, append it (will create variation if needed)
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

  /// Returns a textual representation of the move history including NAG, comments,
  /// and variations (branches).
  /// This implementation preserves the original formatting style when there are no variations,
  /// and adds support for variations and comments.
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
        // Retrieve current node
        final PgnNode<ExtMove> currentNode = nodes[i];
        sb.write(sep);
        final String moveText = _formatMoveWithAnnotations(currentNode);
        sb.write(moveText);

        // Check for variations after this move
        if (currentNode.parent != null &&
            currentNode.parent!.children.length > 1) {
          final int currentIndex = currentNode.parent!.children.indexOf(
            currentNode,
          );
          if (currentIndex == 0) {
            // This is mainline; output variations
            for (
              int varIdx = 1;
              varIdx < currentNode.parent!.children.length;
              varIdx++
            ) {
              sb.write(' (');
              // Use num-1 because num was already incremented in sb.writeNumber(num++)
              // The variation should use the same move number as the mainline move
              sb.write(
                _formatVariation(currentNode.parent!.children[varIdx], num - 1),
              );
              sb.write(')');
            }
          }
        }

        i++;
      }
      // Process subsequent removal moves (up to 3) if present.
      for (int round = 0; round < 3; round++) {
        if (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          final PgnNode<ExtMove> currentNode = nodes[i];
          sb.write(_formatMoveWithAnnotations(currentNode));

          // Check for variations after removal move
          if (currentNode.parent != null &&
              currentNode.parent!.children.length > 1) {
            final int currentIndex = currentNode.parent!.children.indexOf(
              currentNode,
            );
            if (currentIndex == 0) {
              for (
                int varIdx = 1;
                varIdx < currentNode.parent!.children.length;
                varIdx++
              ) {
                sb.write(' (');
                // Use num-1 because num was already incremented in sb.writeNumber(num++)
                // The variation should use the same move number as the mainline move
                sb.write(
                  _formatVariation(
                    currentNode.parent!.children[varIdx],
                    num - 1,
                  ),
                );
                sb.write(')');
              }
            }
          }

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

  /// Formats a single move with its annotations (startingComments, NAGs, and comments).
  String _formatMoveWithAnnotations(PgnNode<ExtMove> node) {
    final ExtMove move = node.data!;
    final StringBuffer sb = StringBuffer();

    // Write starting comments if present
    if (move.startingComments != null && move.startingComments!.isNotEmpty) {
      for (final String comment in move.startingComments!) {
        sb.write('{$comment} ');
      }
    }

    // Write the move notation
    sb.write(move.notation);

    // Write NAG symbols
    if (move.nags != null && move.nags!.isNotEmpty) {
      sb.write(_nagsToString(move.nags!));
    }

    // Write after-move comments
    if (move.comments != null && move.comments!.isNotEmpty) {
      for (final String comment in move.comments!) {
        sb.write(' {$comment}');
      }
    }

    return sb.toString();
  }

  /// Formats a variation branch in compact notation.
  String _formatVariation(PgnNode<ExtMove> start, int moveNumber) {
    final StringBuffer sb = StringBuffer();
    PgnNode<ExtMove>? current = start;
    int currentMove = moveNumber;
    PieceColor? lastSide;

    while (current != null && current.data != null) {
      final ExtMove move = current.data!;

      // Write starting comments
      if (move.startingComments != null && move.startingComments!.isNotEmpty) {
        for (final String comment in move.startingComments!) {
          sb.write('{$comment} ');
        }
      }

      // Write move number following PGN standard:
      // 1. White's move: always show "N."
      // 2. Black's move: only show "N..." if:
      //    a) First move in variation AND it's black's move (variation starts with black)
      //    b) Previous move was also black (consecutive black moves, e.g. after removal)
      // 3. Black's move right after white's move (same turn): omit "N..." for brevity
      final bool isFirstMove = current == start;
      final bool isWhiteMove = move.side == PieceColor.white;
      final bool isNonRemoveMove =
          move.type == MoveType.place || move.type == MoveType.move;

      // Determine if we should show move number
      bool showMoveNumber = false;
      if (isNonRemoveMove) {
        if (isWhiteMove) {
          // Always show move number for white
          showMoveNumber = true;
        } else {
          // For black, only show if variation starts with black OR previous was also black
          final bool variationStartsWithBlack = isFirstMove;
          final bool consecutiveBlackMoves = lastSide == PieceColor.black;
          showMoveNumber = variationStartsWithBlack || consecutiveBlackMoves;
        }
      }

      if (showMoveNumber) {
        if (isWhiteMove) {
          sb.write('$currentMove. ');
        } else {
          sb.write('$currentMove... ');
        }
      }

      // Write the move notation
      sb.write(move.notation);

      // Write NAG symbols
      if (move.nags != null && move.nags!.isNotEmpty) {
        sb.write(_nagsToString(move.nags!));
      }

      // Write after-move comments
      if (move.comments != null && move.comments!.isNotEmpty) {
        for (final String comment in move.comments!) {
          sb.write(' {$comment}');
        }
      }

      // Handle nested variations
      if (current.children.length > 1) {
        for (int i = 1; i < current.children.length; i++) {
          sb.write(' (');
          sb.write(
            _formatVariation(
              current.children[i],
              move.side == PieceColor.black ? currentMove + 1 : currentMove,
            ),
          );
          sb.write(')');
        }
      }

      // Update move number and track last side
      if (move.type != MoveType.remove && move.side == PieceColor.black) {
        currentMove++;
      }
      if (move.type != MoveType.remove) {
        lastSide = move.side;
      }

      // Move to next node
      if (current.children.isNotEmpty) {
        current = current.children[0];

        // Add space before next move, UNLESS next move is a removal
        // (place/move + remove should be concatenated like "b2xf4")
        if (current.data != null && current.data!.type != MoveType.remove) {
          sb.write(' ');
        }
      } else {
        break;
      }
    }

    return sb.toString().trim();
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
      PgnNode<ExtMove> node,
      List<String>? nextStartComments,
    ) {
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
      PgnNode<ExtMove> node,
      List<String>? nextStartComments,
      String? prevBoardLayout,
    ) {
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

      // Build an inline per-move compact context derived from boardLayout.
      // This helps the LLM analyze each move in its own resulting position.
      // Note: The model will later remove these braces and insert human commentary.
      final String inlineCtx = boardStr.isNotEmpty
          ? _buildInlineContextFromBoardLayout(
              boardStr,
              prevBoardLayout,
              m.side,
              m.type,
              m.from,
              m.to,
            )
          : "";

      // Build a details string with all extra fields and inline context.
      return "{ side=$sideStr, type=$typeStr, ${boardStr.isNotEmpty ? 'boardLayout="$boardStr", ' : ""}${m.moveIndex != null ? "moveIndex=${m.moveIndex}, " : ""}${m.roundIndex != null ? "roundIndex=${m.roundIndex}, " : ""}${nagStr.isNotEmpty ? 'nags="$nagStr", ' : ""}${mergedComments.isNotEmpty ? 'comments="${mergedComments.replaceAll('"', r'\"')}"' : ""}${inlineCtx.isNotEmpty ? ', ctx="${inlineCtx.replaceAll('"', r'\"')}"' : ''} }";
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
      final List<String>? firstNodeSuccessorComments = (i + 1 < nodes.length)
          ? nodes[i + 1].data?.startingComments
          : null;
      // Notation + details in braces
      sb.write(firstNode.data!.notation);
      sb.write(' ');
      sb.write(
        extMoveDetails(
          firstNode,
          firstNodeSuccessorComments,
          firstNode.parent?.data?.boardLayout,
        ),
      );
      i++;

      // Handle subsequent remove moves (up to 3) if they exist
      // (since an in-game mill might remove multiple pieces).
      while (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
        final PgnNode<ExtMove> removeNode = nodes[i];
        final List<String>? removeNodeSuccessorComments = (i + 1 < nodes.length)
            ? nodes[i + 1].data?.startingComments
            : null;
        sb.write(' ');
        sb.write(removeNode.data!.notation);
        sb.write(' ');
        sb.write(
          extMoveDetails(
            removeNode,
            removeNodeSuccessorComments,
            removeNode.parent?.data?.boardLayout,
          ),
        );
        i++;
      }

      // If there's still a next move (likely Black's move), handle it on the same line
      if (i < nodes.length) {
        sb.write(' ');
        final PgnNode<ExtMove> secondNode = nodes[i];
        final List<String>? secondNodeSuccessorComments = (i + 1 < nodes.length)
            ? nodes[i + 1].data?.startingComments
            : null;
        sb.write(secondNode.data!.notation);
        sb.write(' ');
        sb.write(
          extMoveDetails(
            secondNode,
            secondNodeSuccessorComments,
            secondNode.parent?.data?.boardLayout,
          ),
        );
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
          sb.write(
            extMoveDetails(
              removeNode,
              removeNodeSuccessorComments,
              removeNode.parent?.data?.boardLayout,
            ),
          );
          i++;
        }
      }

      sb.writeln();
      moveNumber++;
    }

    // Get the prompt header and footer from settings
    // Replace hardcoded values with user-configured ones
    final String promptHeader = DB().generalSettings.llmPromptHeader.isEmpty
        ? PromptDefaults.llmPromptHeader
        : DB().generalSettings.llmPromptHeader;
    final String promptFooter = DB().generalSettings.llmPromptFooter.isEmpty
        ? PromptDefaults.llmPromptFooter
        : DB().generalSettings.llmPromptFooter;

    final String rawOutput = sb.toString().trim();

    if (GameController().isPositionSetup && setupPosition != null) {
      return '[FEN "$setupPosition"]\n[SetUp "1"]\n\n$rawOutput';
    }

    // Do not include a global dynamic context block. Each move already embeds
    // an inline ctx string with precise per-move information that the LLM needs.
    // Keeping only the header + move list + footer avoids redundancy.
    return "$promptHeader\n$rawOutput\n$promptFooter";
  }

  /// Build a compact, single-line per-move context from a boardLayout string
  /// and the side who just moved. This function does not mutate global state
  /// and avoids using Position.doMove(). It reconstructs essential features
  /// (counts, power points, corners, mobility, threats, legal moves and a
  /// lightweight advantage) purely from the layout, DB rule settings and
  /// static connectivity tables.
  String _buildInlineContextFromBoardLayout(
    String boardLayout,
    String? prevBoardLayout,
    PieceColor sideJustMoved,
    MoveType lastMoveType,
    int lastFromSquare,
    int lastToSquare,
  ) {
    // Parse layout: inner/middle/outer strings of length 8
    final List<String> parts = boardLayout.split('/');
    if (parts.length != 3) {
      return '';
    }

    // Map into 24-square board indices [8..31].
    // Order from docs:
    // parts[0] -> inner:  d5(8), e5(9), e4(10), e3(11), d3(12), c3(13), c4(14), c5(15)
    // parts[1] -> middle: d6(16), f6(17), f4(18), f2(19), d2(20), b2(21), b4(22), b6(23)
    // parts[2] -> outer:  d7(24), g7(25), g4(26), g1(27), d1(28), a1(29), a4(30), a7(31)
    final Map<int, PieceColor> occ = <int, PieceColor>{};
    PieceColor chToColor(String ch) {
      if (ch == 'O') {
        return PieceColor.white;
      }
      if (ch == '@') {
        return PieceColor.black;
      }
      return PieceColor.none;
    }

    final List<int> idx0 = <int>[8, 9, 10, 11, 12, 13, 14, 15];
    final List<int> idx1 = <int>[16, 17, 18, 19, 20, 21, 22, 23];
    final List<int> idx2 = <int>[24, 25, 26, 27, 28, 29, 30, 31];
    for (int i = 0; i < 8; i++) {
      occ[idx0[i]] = chToColor(parts[0][i]);
      occ[idx1[i]] = chToColor(parts[1][i]);
      occ[idx2[i]] = chToColor(parts[2][i]);
    }

    // Counts on board and piece positions
    int onBoardW = 0, onBoardB = 0;
    final List<String> whitePiecesInline = <String>[];
    final List<String> blackPiecesInline = <String>[];
    final List<String> emptySquaresInline = <String>[];
    for (int s = 8; s <= 31; s++) {
      final PieceColor c = occ[s] ?? PieceColor.none;
      if (c == PieceColor.white) {
        onBoardW++;
        whitePiecesInline.add(ExtMove.sqToNotation(s));
      } else if (c == PieceColor.black) {
        onBoardB++;
        blackPiecesInline.add(ExtMove.sqToNotation(s));
      } else {
        emptySquaresInline.add(ExtMove.sqToNotation(s));
      }
    }

    // Determine phase heuristic from the last move type.
    // If the last move was a placement, treat as Placing; otherwise, Moving.
    final bool placingPhase = (lastMoveType == MoveType.place);
    final bool mayFly = DB().ruleSettings.mayFly;
    final int flyPieceCount = DB().ruleSettings.flyPieceCount;

    bool canFly(PieceColor side) =>
        mayFly &&
        ((side == PieceColor.white ? onBoardW : onBoardB) <= flyPieceCount);

    String colorName(PieceColor c) => c == PieceColor.white
        ? 'White'
        : (c == PieceColor.black ? 'Black' : 'None');

    // Cross points control
    const List<int> crossPoints = <int>[16, 18, 20, 22];
    const List<String> crossNames = <String>['d6', 'f4', 'd2', 'b4'];
    final Map<String, String> crossCtl = <String, String>{};
    for (int i = 0; i < crossPoints.length; i++) {
      crossCtl[crossNames[i]] = colorName(
        occ[crossPoints[i]] ?? PieceColor.none,
      );
    }

    // Corners occupancy
    const List<int> cornerSquares = <int>[31, 25, 27, 29];
    final List<String> whiteCorners = <String>[];
    final List<String> blackCorners = <String>[];
    for (final int sq in cornerSquares) {
      final PieceColor c = occ[sq] ?? PieceColor.none;
      if (c == PieceColor.white) {
        whiteCorners.add(ExtMove.sqToNotation(sq));
      }
      if (c == PieceColor.black) {
        blackCorners.add(ExtMove.sqToNotation(sq));
      }
    }

    // Legal moves for side to move next
    final PieceColor stm = sideJustMoved.opponent;
    List<String> placements() {
      if (!placingPhase) {
        return const <String>[];
      }
      return <String>[
        for (int s = 8; s <= 31; s++)
          if ((occ[s] ?? PieceColor.none) == PieceColor.none)
            ExtMove.sqToNotation(s),
      ];
    }

    List<String> stepMoves() {
      final bool movementAllowed =
          !placingPhase || DB().ruleSettings.mayMoveInPlacingPhase;
      if (!movementAllowed) {
        return const <String>[];
      }

      final bool canFlySide = canFly(stm);
      final Set<String> res = <String>{};
      for (int from = 8; from <= 31; from++) {
        if (occ[from] != stm) {
          continue;
        }
        if (canFlySide) {
          for (int to = 8; to <= 31; to++) {
            if ((occ[to] ?? PieceColor.none) == PieceColor.none) {
              res.add(
                '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
              );
            }
          }
        } else {
          for (final int to in Position._adjacentSquares[from]) {
            if (to != 0 && (occ[to] ?? PieceColor.none) == PieceColor.none) {
              res.add(
                '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
              );
            }
          }
        }
      }
      return res.toList(growable: false);
    }

    // Immediate mill threats for side to move next (single-step)
    bool completesMillAt(int s, PieceColor c) {
      // Check both lines for this square:
      for (int ld = 0; ld < Position._millTable[s].length; ld++) {
        final int a = Position._millTable[s][ld][0];
        final int b = Position._millTable[s][ld][1];
        if ((occ[a] == c) && (occ[b] == c)) {
          return true;
        }
      }
      return false;
    }

    // A mill created by the last placement/move implies a removal is pending for the same side.
    bool removalPending = false;
    if (lastMoveType == MoveType.place || lastMoveType == MoveType.move) {
      if (lastToSquare >= 8 && lastToSquare <= 31) {
        removalPending = completesMillAt(lastToSquare, sideJustMoved);
      }
    }

    final PieceColor sideToMoveAfter = removalPending ? sideJustMoved : stm;
    final String sideToMoveAfterStr = colorName(sideToMoveAfter);

    List<String> oneMoveMills(PieceColor c) {
      final Set<String> res = <String>{};
      if (placingPhase) {
        for (int s = 8; s <= 31; s++) {
          if ((occ[s] ?? PieceColor.none) != PieceColor.none) {
            continue;
          }
          if (completesMillAt(s, c)) {
            res.add(ExtMove.sqToNotation(s));
          }
        }
      } else {
        final bool canFlySide = canFly(c);
        for (int from = 8; from <= 31; from++) {
          if (occ[from] != c) {
            continue;
          }
          if (canFlySide) {
            for (int to = 8; to <= 31; to++) {
              if ((occ[to] ?? PieceColor.none) != PieceColor.none) {
                continue;
              }
              // Temporarily move and test
              final PieceColor bak = occ[from]!;
              occ[from] = PieceColor.none;
              if (completesMillAt(to, c)) {
                res.add(
                  '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
                );
              }
              occ[from] = bak;
            }
          } else {
            for (final int to in Position._adjacentSquares[from]) {
              if (to == 0 || (occ[to] ?? PieceColor.none) != PieceColor.none) {
                continue;
              }
              final PieceColor bak = occ[from]!;
              occ[from] = PieceColor.none;
              if (completesMillAt(to, c)) {
                res.add(
                  '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
                );
              }
              occ[from] = bak;
            }
          }
        }
      }
      return res.toList(growable: false);
    }

    // Mills total for each side
    int millsFor(PieceColor c) {
      int n = 0;
      for (final List<int> line in Position._millLinesHV) {
        if (occ[line[0]] == c && occ[line[1]] == c && occ[line[2]] == c) {
          n++;
        }
      }
      if (DB().ruleSettings.hasDiagonalLines == true) {
        for (final List<int> line in Position._millLinesD) {
          if (occ[line[0]] == c && occ[line[1]] == c && occ[line[2]] == c) {
            n++;
          }
        }
      }
      return n;
    }

    // Mobility for Moving phase
    int legalMovesCount(PieceColor c) {
      if (placingPhase) {
        return 0;
      }
      final bool canFlySide = canFly(c);
      int moves = 0;
      for (int from = 8; from <= 31; from++) {
        if (occ[from] != c) {
          continue;
        }
        if (canFlySide) {
          for (int to = 8; to <= 31; to++) {
            if ((occ[to] ?? PieceColor.none) == PieceColor.none) {
              moves++;
            }
          }
        } else {
          for (final int to in Position._adjacentSquares[from]) {
            if (to != 0 && (occ[to] ?? PieceColor.none) == PieceColor.none) {
              moves++;
            }
          }
        }
      }
      return moves;
    }

    int blockedPieces(PieceColor c) {
      if (placingPhase) {
        return 0;
      }
      final bool canFlySide = canFly(c);
      if (canFlySide) {
        return 0;
      }
      int blocked = 0;
      for (int from = 8; from <= 31; from++) {
        if (occ[from] != c) {
          continue;
        }
        bool hasLib = false;
        for (final int to in Position._adjacentSquares[from]) {
          if (to != 0 && (occ[to] ?? PieceColor.none) == PieceColor.none) {
            hasLib = true;
            break;
          }
        }
        if (!hasLib) {
          blocked++;
        }
      }
      return blocked;
    }

    // Lightweight advantage (no in-hand info available here)
    final int millsW = millsFor(PieceColor.white);
    final int millsB = millsFor(PieceColor.black);
    int crossW = 0, crossB = 0;
    for (final String name in crossNames) {
      if ((crossCtl[name] ?? 'None') == 'White') {
        crossW++;
      }
      if ((crossCtl[name] ?? 'None') == 'Black') {
        crossB++;
      }
    }
    final int onBoardDiff = onBoardW - onBoardB;
    final int millsDiff = millsW - millsB;
    final int crossDiff = crossW - crossB;
    final int cornersDiff = whiteCorners.length - blackCorners.length;
    final int legalW = legalMovesCount(PieceColor.white);
    final int legalB = legalMovesCount(PieceColor.black);
    final int blockedW = blockedPieces(PieceColor.white);
    final int blockedB = blockedPieces(PieceColor.black);
    final double mobilityTerm = placingPhase ? 0.0 : 0.05 * (legalW - legalB);
    final double blockedTerm = placingPhase
        ? 0.0
        : -0.05 * (blockedW - blockedB);
    final double flyTerm = placingPhase
        ? 0.0
        : ((canFly(PieceColor.white) ? 0.2 : 0.0) -
              (canFly(PieceColor.black) ? 0.2 : 0.0));
    final double adv =
        1.0 * onBoardDiff +
        0.5 * millsDiff +
        0.3 * crossDiff +
        (-0.2) * cornersDiff +
        mobilityTerm +
        blockedTerm +
        flyTerm;
    final String advSym = adv > 0.5 ? '±' : (adv < -0.5 ? '∓' : '=');
    final String advSide = adv > 0.5
        ? 'White better'
        : (adv < -0.5 ? 'Black better' : 'Equal');

    // Truncate helper
    List<String> trunc(List<String> items, int limit) {
      if (items.length <= limit) {
        return items;
      }
      return items.sublist(0, limit)..add('...(+${items.length - limit} more)');
    }

    // Assemble inline string (semicolon-separated for compactness)
    final String phaseStr = placingPhase ? 'Placing' : 'Moving';
    final String stmStr = sideToMoveAfterStr;
    // Keep power points and corners concise; we omit them in the final line to reduce clutter.
    // If needed later, they can be reintroduced.
    // final String powerStr = 'd6=${crossCtl['d6']}, f4=${crossCtl['f4']}, d2=${crossCtl['d2']}, b4=${crossCtl['b4']}';
    // final String cornersStr = 'W=[${whiteCorners.join(', ')}], B=[${blackCorners.join(', ')}]';
    final List<String> p = placements();
    final List<String> mv = stepMoves();
    final List<String> threats = oneMoveMills(sideToMoveAfter);

    String legalStr;
    if (removalPending) {
      // Approximate legal removals for sideToMoveNext
      List<String> legalRemovalsFor(PieceColor remover) {
        final PieceColor victim = remover.opponent;
        final bool mayRemoveFromMills =
            DB().ruleSettings.mayRemoveFromMillsAlways;
        // Determine if opponent is all in mills under current layout
        bool opponentAllInMills() {
          for (int s = 8; s <= 31; s++) {
            if (occ[s] == victim) {
              bool inMill = false;
              for (int ld = 0; ld < Position._millTable[s].length; ld++) {
                final int a = Position._millTable[s][ld][0];
                final int b = Position._millTable[s][ld][1];
                if (occ[a] == victim && occ[b] == victim) {
                  inMill = true;
                  break;
                }
              }
              if (!inMill) {
                return false;
              }
            }
          }
          return true;
        }

        final bool allInMills = opponentAllInMills();
        final List<String> res = <String>[];
        for (int s = 8; s <= 31; s++) {
          if (occ[s] != victim) {
            continue;
          }
          bool pieceInMill = false;
          for (int ld = 0; ld < Position._millTable[s].length; ld++) {
            final int a = Position._millTable[s][ld][0];
            final int b = Position._millTable[s][ld][1];
            if (occ[a] == victim && occ[b] == victim) {
              pieceInMill = true;
              break;
            }
          }
          if (pieceInMill && !mayRemoveFromMills && !allInMills) {
            continue;
          }
          res.add('x${ExtMove.sqToNotation(s)}');
        }
        return res;
      }

      final List<String> rm = legalRemovalsFor(sideToMoveAfter);
      legalStr =
          'legalForSideToMoveAfter(removals)=[${trunc(rm, 40).join(', ')}]';
    } else if (placingPhase) {
      final String movesPart = DB().ruleSettings.mayMoveInPlacingPhase
          ? ', moves=[${trunc(mv, 40).join(', ')}]'
          : '';
      legalStr =
          'legalForSideToMoveAfter(placements)=[${trunc(p, 40).join(', ')}]$movesPart';
    } else {
      legalStr = 'legalForSideToMoveAfter(moves)=[${trunc(mv, 60).join(', ')}]';
    }
    final String threatStr =
        'oneMoveMillsForSideToMove=[${trunc(threats, 20).join(', ')}]';

    // We omit detailed mobility to keep context concise.
    // final String mobilityStr = '';

    // Truncate lists if too long to keep inline context concise
    final String wPiecesStr = whitePiecesInline.join(',');
    final String bPiecesStr = blackPiecesInline.join(',');
    final String emptyStr = emptySquaresInline.join(',');

    // Build moverAlternatives from prevBoardLayout (options before this move)
    String moverAltStr = '';
    if (prevBoardLayout != null && prevBoardLayout.split('/').length == 3) {
      // Parse prev layout
      final List<String> prev = prevBoardLayout.split('/');
      final Map<int, PieceColor> occPrev = <int, PieceColor>{};
      PieceColor chToColorPrev(String ch) {
        if (ch == 'O') {
          return PieceColor.white;
        }
        if (ch == '@') {
          return PieceColor.black;
        }
        return PieceColor.none;
      }

      for (int i = 0; i < 8; i++) {
        occPrev[8 + i] = chToColorPrev(prev[0][i]);
        occPrev[16 + i] = chToColorPrev(prev[1][i]);
        occPrev[24 + i] = chToColorPrev(prev[2][i]);
      }
      int countPrev(PieceColor c) {
        int n = 0;
        for (int s = 8; s <= 31; s++) {
          if (occPrev[s] == c) {
            n++;
          }
        }
        return n;
      }

      bool canFlyPrev(PieceColor c) =>
          DB().ruleSettings.mayFly &&
          countPrev(c) <= DB().ruleSettings.flyPieceCount;

      List<String> altPlacements() => <String>[
        for (int s = 8; s <= 31; s++)
          if ((occPrev[s] ?? PieceColor.none) == PieceColor.none)
            ExtMove.sqToNotation(s),
      ];

      List<String> altMoves() {
        final bool canFlySide = canFlyPrev(sideJustMoved);
        final Set<String> r = <String>{};
        for (int from = 8; from <= 31; from++) {
          if (occPrev[from] != sideJustMoved) {
            continue;
          }
          if (canFlySide) {
            for (int to = 8; to <= 31; to++) {
              if ((occPrev[to] ?? PieceColor.none) == PieceColor.none) {
                r.add(
                  '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
                );
              }
            }
          } else {
            for (final int to in Position._adjacentSquares[from]) {
              if (to != 0 &&
                  (occPrev[to] ?? PieceColor.none) == PieceColor.none) {
                r.add(
                  '${ExtMove.sqToNotation(from)}-${ExtMove.sqToNotation(to)}',
                );
              }
            }
          }
        }
        return r.toList(growable: false);
      }

      List<String> altRemovals() {
        final PieceColor victim = sideJustMoved.opponent;
        final bool mayRemoveFromMills =
            DB().ruleSettings.mayRemoveFromMillsAlways;
        bool victimAllInMills() {
          for (int s = 8; s <= 31; s++) {
            if (occPrev[s] == victim) {
              bool inMill = false;
              for (int ld = 0; ld < Position._millTable[s].length; ld++) {
                final int a = Position._millTable[s][ld][0];
                final int b = Position._millTable[s][ld][1];
                if (occPrev[a] == victim && occPrev[b] == victim) {
                  inMill = true;
                  break;
                }
              }
              if (!inMill) {
                return false;
              }
            }
          }
          return true;
        }

        final bool allIn = victimAllInMills();
        final List<String> r = <String>[];
        for (int s = 8; s <= 31; s++) {
          if (occPrev[s] != victim) {
            continue;
          }
          bool inMill = false;
          for (int ld = 0; ld < Position._millTable[s].length; ld++) {
            final int a = Position._millTable[s][ld][0];
            final int b = Position._millTable[s][ld][1];
            if (occPrev[a] == victim && occPrev[b] == victim) {
              inMill = true;
              break;
            }
          }
          if (inMill && !mayRemoveFromMills && !allIn) {
            continue;
          }
          r.add('x${ExtMove.sqToNotation(s)}');
        }
        return r;
      }

      List<String> alts;
      if (lastMoveType == MoveType.place) {
        alts = altPlacements();
      } else if (lastMoveType == MoveType.move) {
        alts = altMoves();
      } else if (lastMoveType == MoveType.remove) {
        alts = altRemovals();
      } else {
        alts = const <String>[];
      }
      final String moverStr = colorName(sideJustMoved);
      final String chosen = (lastMoveType == MoveType.place)
          ? ExtMove.sqToNotation(lastToSquare)
          : (lastMoveType == MoveType.move)
          ? '${ExtMove.sqToNotation(lastFromSquare)}-${ExtMove.sqToNotation(lastToSquare)}'
          : (lastMoveType == MoveType.remove)
          ? 'x${ExtMove.sqToNotation(lastToSquare)}'
          : '';
      moverAltStr =
          'mover=$moverStr; moverAlternatives=[${trunc(alts, 40).join(', ')}]; chosen=$chosen; ';
    }

    return 'phaseAfter=$phaseStr; sideToMoveAfter=$stmStr; whitePieces=[$wPiecesStr]; blackPieces=[$bPiecesStr]; empty=[$emptyStr]; mills(W/B)=$millsW/$millsB; $legalStr; $threatStr; ${moverAltStr}advantage=${adv.toStringAsFixed(2)} $advSym ($advSide)';
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

  /// Build a compact dynamic context block derived from current engine state.
  @visibleForTesting
  String buildGlobalDynamicContextForTesting(
    Position pos,
    List<ExtMove> mainlineMoves,
  ) {
    // --- Helpers -----------------------------------------------------------
    String colorName(PieceColor c) => c == PieceColor.white
        ? 'White'
        : (c == PieceColor.black ? 'Black' : 'None');

    String phaseName(Phase p) {
      switch (p) {
        case Phase.placing:
          return 'Placing';
        case Phase.moving:
          return 'Moving';
        case Phase.ready:
          return 'Ready';
        case Phase.gameOver:
          return 'GameOver';
      }
    }

    bool canFlyFor(PieceColor side) {
      return DB().ruleSettings.mayFly &&
          pos.pieceOnBoardCount[side]! <= DB().ruleSettings.flyPieceCount;
    }

    String boardLayoutNow() {
      // Uses engine's current board to produce a layout string "outer/middle/inner".
      return pos.generateBoardLayoutAfterThisMove();
    }

    String lastCombinedMove() {
      // Merge the last non-remove move with trailing remove(s), e.g. "f6xa7".
      if (mainlineMoves.isEmpty) {
        return 'None';
      }

      int idx = mainlineMoves.length - 1;
      final List<String> captures = <String>[];
      while (idx >= 0 && mainlineMoves[idx].type == MoveType.remove) {
        final int sq = mainlineMoves[idx].to;
        captures.add(ExtMove.sqToNotation(sq));
        idx--;
      }
      if (idx < 0) {
        // Only remove(s) without a base move (should not happen), show compact form
        return captures.isEmpty ? 'None' : 'x${captures.reversed.join('/')}';
      }
      final String base = mainlineMoves[idx].notation;
      if (captures.isEmpty) {
        return base;
      }
      if (captures.length == 1) {
        return '${base}x${captures.first}';
      }
      return '${base}x${captures.reversed.join('/')}';
    }

    // Squares helpers
    String sqToStr(int sq) => ExtMove.sqToNotation(sq);
    bool isEmptySq(int sq) => pos.pieceOnGrid(sq) == PieceColor.none;

    // Fixed reference squares
    const List<int> crossPoints = <int>[16, 18, 20, 22]; // d6, f4, d2, b4
    const List<String> crossNames = <String>['d6', 'f4', 'd2', 'b4'];
    const List<int> cornerSquares = <int>[31, 25, 27, 29]; // a7, g7, g1, a1

    // Power points control snapshot
    final Map<String, String> crossControl = <String, String>{};
    for (int i = 0; i < crossPoints.length; i++) {
      final int sq = crossPoints[i];
      crossControl[crossNames[i]] = colorName(pos.pieceOnGrid(sq));
    }

    // Corners occupancy list per color
    final List<String> whiteCorners = <String>[];
    final List<String> blackCorners = <String>[];
    for (final int sq in cornerSquares) {
      final PieceColor c = pos.pieceOnGrid(sq);
      if (c == PieceColor.white) {
        whiteCorners.add(sqToStr(sq));
      }
      if (c == PieceColor.black) {
        blackCorners.add(sqToStr(sq));
      }
    }

    // Mills count per side
    final int whiteMills = pos.totalMillsCount(PieceColor.white);
    final int blackMills = pos.totalMillsCount(PieceColor.black);

    // Captured count per side derived from initial quota
    final int maxPieces = DB().ruleSettings.piecesCount;
    int capturedOf(PieceColor side) =>
        maxPieces - pos.pieceOnBoardCount[side]! - pos.pieceInHandCount[side]!;

    // List all squares occupied by white and black pieces, and empty squares
    final List<String> whitePieces = <String>[];
    final List<String> blackPieces = <String>[];
    final List<String> emptySquares = <String>[];
    for (int sq = 8; sq <= 31; sq++) {
      final PieceColor c = pos.pieceOnGrid(sq);
      if (c == PieceColor.white) {
        whitePieces.add(sqToStr(sq));
      } else if (c == PieceColor.black) {
        blackPieces.add(sqToStr(sq));
      } else {
        emptySquares.add(sqToStr(sq));
      }
    }

    // Mobility and blocked pieces (Moving phase only)
    int countLegalMovesFor(PieceColor side) {
      if (pos.phase != Phase.moving) {
        return 0;
      }
      final bool canFly = canFlyFor(side);
      int moves = 0;
      // Iterate over all 24 squares (indices 8..31)
      for (int sq = 8; sq <= 31; sq++) {
        if (pos.pieceOnGrid(sq) != side) {
          continue;
        }
        if (canFly) {
          // Can fly to any empty square
          for (int t = 8; t <= 31; t++) {
            if (isEmptySq(t)) {
              moves++;
            }
          }
        } else {
          // Normal adjacent moves only
          for (int d = 0; d < Position._adjacentSquares[sq].length; d++) {
            final int t = Position._adjacentSquares[sq][d];
            if (t != 0 && isEmptySq(t)) {
              moves++;
            }
          }
        }
      }
      return moves;
    }

    int countBlockedPieces(PieceColor side) {
      if (pos.phase != Phase.moving) {
        return 0;
      }
      final bool canFly = canFlyFor(side);
      if (canFly) {
        return 0; // When flying is allowed, no piece is truly blocked
      }
      int blocked = 0;
      for (int sq = 8; sq <= 31; sq++) {
        if (pos.pieceOnGrid(sq) != side) {
          continue;
        }
        bool hasLiberty = false;
        for (int d = 0; d < Position._adjacentSquares[sq].length; d++) {
          final int t = Position._adjacentSquares[sq][d];
          if (t != 0 && isEmptySq(t)) {
            hasLiberty = true;
            break;
          }
        }
        if (!hasLiberty) {
          blocked++;
        }
      }
      return blocked;
    }

    // Immediate mill threats (one-move mills)
    List<String> immediateMillSquaresPlacing(PieceColor side) {
      final List<String> res = <String>[];
      for (int sq = 8; sq <= 31; sq++) {
        if (!isEmptySq(sq)) {
          continue;
        }
        // _potentialMillsCount > 0 means placing at sq completes at least one mill
        if (pos._potentialMillsCount(sq, side) > 0) {
          res.add(sqToStr(sq));
        }
      }
      return res;
    }

    List<String> immediateMillMovesMoving(PieceColor side) {
      final bool canFly = canFlyFor(side);
      final Set<String> res = <String>{};
      for (int from = 8; from <= 31; from++) {
        if (pos.pieceOnGrid(from) != side) {
          continue;
        }
        if (canFly) {
          for (int to = 8; to <= 31; to++) {
            if (!isEmptySq(to)) {
              continue;
            }
            if (pos._potentialMillsCount(to, side, from: from) > 0) {
              res.add('${sqToStr(from)}-${sqToStr(to)}');
            }
          }
        } else {
          for (int d = 0; d < Position._adjacentSquares[from].length; d++) {
            final int to = Position._adjacentSquares[from][d];
            if (to == 0 || !isEmptySq(to)) {
              continue;
            }
            if (pos._potentialMillsCount(to, side, from: from) > 0) {
              res.add('${sqToStr(from)}-${sqToStr(to)}');
            }
          }
        }
      }
      return res.toList(growable: false);
    }

    // Truncation helper to keep prompt compact
    List<String> truncateList(List<String> items, int limit) {
      if (items.length <= limit) {
        return items;
      }
      return items.sublist(0, limit)..add('...(+${items.length - limit} more)');
    }

    // --- Assemble lines ----------------------------------------------------
    final String phaseLine = 'phase: ${phaseName(pos.phase)}';
    final String sideLine = 'sideToMove: ${colorName(pos.sideToMove)}';
    final String boardLine = 'boardLayout: ${boardLayoutNow()}';

    final String countsLine =
        'counts: onBoard(W/B)=${pos.pieceOnBoardCount[PieceColor.white]}/${pos.pieceOnBoardCount[PieceColor.black]}, inHand(W/B)=${pos.pieceInHandCount[PieceColor.white]}/${pos.pieceInHandCount[PieceColor.black]}, captured(W/B)=${capturedOf(PieceColor.white)}/${capturedOf(PieceColor.black)}';
    final String millsLine = 'mills: total(W/B)=$whiteMills/$blackMills';

    final String crossLine =
        'powerPoints: d6=${crossControl['d6']}, f4=${crossControl['f4']}, d2=${crossControl['d2']}, b4=${crossControl['b4']}';
    final String cornersLine =
        'corners: white=[${whiteCorners.join(', ')}], black=[${blackCorners.join(', ')}]';

    final bool isMoving = pos.phase == Phase.moving;
    final String mobilityLine = isMoving
        ? 'mobility: legalMoves(W/B)=${countLegalMovesFor(PieceColor.white)}/${countLegalMovesFor(PieceColor.black)}, blockedPieces(W/B)=${countBlockedPieces(PieceColor.white)}/${countBlockedPieces(PieceColor.black)}, canFly(W/B)=${canFlyFor(PieceColor.white)}/${canFlyFor(PieceColor.black)}'
        : '';

    final List<String> wThreats = isMoving
        ? immediateMillMovesMoving(PieceColor.white)
        : immediateMillSquaresPlacing(PieceColor.white);
    final List<String> bThreats = isMoving
        ? immediateMillMovesMoving(PieceColor.black)
        : immediateMillSquaresPlacing(PieceColor.black);

    final String threatLine =
        'immediateMillThreats: white=${truncateList(wThreats, 12).join(', ')}, black=${truncateList(bThreats, 12).join(', ')}';

    final String lastMoveLine = 'lastMove: ${lastCombinedMove()}';

    // ---------------------------------------------------------------------
    // Legal moves for the side to move (after the last completed step)
    // This helps the LLM avoid proposing non-existent alternatives.
    // ---------------------------------------------------------------------
    final PieceColor stm = pos.sideToMove;

    // Generate legal placement targets for the side to move in Placing phase.
    List<String> legalPlacements(PieceColor side) {
      if (pos.phase != Phase.placing) {
        return const <String>[];
      }
      if (pos.pieceInHandCount[side] == null ||
          pos.pieceInHandCount[side]! <= 0) {
        return const <String>[];
      }
      final List<String> res = <String>[];
      for (int sq = 8; sq <= 31; sq++) {
        if (isEmptySq(sq)) {
          res.add(sqToStr(sq));
        }
      }
      return res;
    }

    // Generate legal step moves for the side to move (Moving phase or
    // optionally during Placing if movement is allowed by rules).
    List<String> legalStepMoves(PieceColor side) {
      final bool movementAllowed =
          (pos.phase == Phase.moving) || pos.canMoveDuringPlacingPhase();
      if (!movementAllowed) {
        return const <String>[];
      }

      final bool canFlySide =
          DB().ruleSettings.mayFly &&
          pos.pieceOnBoardCount[side]! <= DB().ruleSettings.flyPieceCount;

      final Set<String> res = <String>{};
      for (int from = 8; from <= 31; from++) {
        if (pos.pieceOnGrid(from) != side) {
          continue;
        }

        if (canFlySide) {
          // Fly to any empty square
          for (int to = 8; to <= 31; to++) {
            if (!isEmptySq(to)) {
              continue;
            }
            res.add('${sqToStr(from)}-${sqToStr(to)}');
          }
        } else {
          // Normal adjacent moves only
          for (int d = 0; d < Position._adjacentSquares[from].length; d++) {
            final int to = Position._adjacentSquares[from][d];
            if (to == 0 || !isEmptySq(to)) {
              continue;
            }
            res.add('${sqToStr(from)}-${sqToStr(to)}');
          }
        }
      }
      return res.toList(growable: false);
    }

    // Generate legal removals for the side to move when action is Remove.
    List<String> legalRemovals(PieceColor side) {
      if (pos.action != Act.remove) {
        return const <String>[];
      }
      final bool stalemateRemoval = pos.isStalemateRemoval(side);
      final PieceColor opponent = side.opponent;
      final bool mayRemoveFromMills =
          DB().ruleSettings.mayRemoveFromMillsAlways;
      final bool opponentAllInMills = pos._isAllInMills(opponent);

      // pieceToRemoveCount sign determines whether to remove opponent or self (special rules)
      final int need = pos.pieceToRemoveCount[side] ?? 0;
      final PieceColor targetSide = need >= 0 ? opponent : side;

      final List<String> res = <String>[];
      for (int sq = 8; sq <= 31; sq++) {
        if (pos.pieceOnGrid(sq) != targetSide) {
          continue;
        }

        // Stalemate removal may restrict to adjacent only
        if (stalemateRemoval && !pos.isAdjacentTo(sq, side)) {
          continue;
        }

        // Cannot remove from mills unless allowed or opponent is all in mills
        if (targetSide == opponent && !mayRemoveFromMills) {
          if (pos._potentialMillsCount(sq, PieceColor.nobody) > 0 &&
              !opponentAllInMills) {
            continue;
          }
        }

        res.add('x${sqToStr(sq)}');
      }
      return res;
    }

    // Assemble legal moves line(s) with truncation to keep prompt concise.
    final List<String> placements = legalPlacements(stm);
    final List<String> stepMoves = legalStepMoves(stm);
    final List<String> removals = legalRemovals(stm);

    String legalLine = '';
    if (pos.action == Act.remove) {
      legalLine =
          'legalRemovals(${colorName(stm)}): ${truncateList(removals, 60).join(', ')}';
    } else if (pos.phase == Phase.placing) {
      final String pStr = placements.isEmpty
          ? '[]'
          : truncateList(placements, 60).join(', ');
      final String mStr = stepMoves.isEmpty
          ? '[]'
          : truncateList(stepMoves, 60).join(', ');
      legalLine =
          'legalMovesForSideToMove(${colorName(stm)}): placements=[$pStr], moves=[$mStr]';
    } else if (pos.phase == Phase.moving) {
      final String mStr = stepMoves.isEmpty
          ? '[]'
          : truncateList(stepMoves, 60).join(', ');
      legalLine = 'legalMovesForSideToMove(${colorName(stm)}): moves=[$mStr]';
    }

    // ---------------------------------------------------------------------
    // Advantage value
    // Prefer the app's existing engine evaluation if available (GameController().value),
    // which drives the advantage graph. If not available, fall back to a
    // lightweight heuristic derived from Position. White-positive, Black-negative.
    // Heuristic components and weights:
    // - Material (onBoard + inHand): 1.0 per piece
    // - Completed mills: 0.5 per mill
    // - Cross points control (d6,f4,d2,b4): 0.3 each
    // - Corners occupancy (penalty): -0.2 each
    // - Mobility (Moving only): +0.05 per legal move, -0.05 per blocked piece
    // - Can-fly (Moving only): +0.2 if White can fly, -0.2 if Black can fly
    double heuristicAdvantageScore() {
      final int onBoardW = pos.pieceOnBoardCount[PieceColor.white] ?? 0;
      final int onBoardB = pos.pieceOnBoardCount[PieceColor.black] ?? 0;
      final int inHandW = pos.pieceInHandCount[PieceColor.white] ?? 0;
      final int inHandB = pos.pieceInHandCount[PieceColor.black] ?? 0;
      final int materialDiff = (onBoardW + inHandW) - (onBoardB + inHandB);

      final int millsDiff = whiteMills - blackMills;

      // Cross control diff (White minus Black)
      int crossW = 0, crossB = 0;
      for (final String name in crossNames) {
        final String owner = crossControl[name] ?? 'None';
        if (owner == 'White') {
          crossW++;
        }
        if (owner == 'Black') {
          crossB++;
        }
      }
      final int crossDiff = crossW - crossB;

      // Corners: more corners = slight structural weakness
      final int cornersDiff = whiteCorners.length - blackCorners.length;

      // Mobility (only meaningful in Moving phase)
      double mobilityTerm = 0.0;
      double blockedTerm = 0.0;
      double flyTerm = 0.0;
      if (isMoving) {
        final int legalW = countLegalMovesFor(PieceColor.white);
        final int legalB = countLegalMovesFor(PieceColor.black);
        final int blockedW = countBlockedPieces(PieceColor.white);
        final int blockedB = countBlockedPieces(PieceColor.black);
        mobilityTerm = 0.05 * (legalW - legalB);
        blockedTerm = -0.05 * (blockedW - blockedB);
        final bool whiteFly = canFlyFor(PieceColor.white);
        final bool blackFly = canFlyFor(PieceColor.black);
        flyTerm = (whiteFly ? 0.2 : 0.0) - (blackFly ? 0.2 : 0.0);
      }

      return 1.0 * materialDiff +
          0.5 * millsDiff +
          0.3 * crossDiff +
          (-0.2) * cornersDiff +
          mobilityTerm +
          blockedTerm +
          flyTerm;
    }

    // Try to reuse engine-provided advantage (range typically [-100, 100]).
    double adv;
    final String? engineValStr = GameController().value;
    if (engineValStr != null) {
      // If parsing fails for any reason, fall back to heuristic.
      final int parsed = int.tryParse(engineValStr) ?? 0;
      adv = parsed.toDouble();
    } else {
      adv = heuristicAdvantageScore();
    }
    String advSymbol;
    String advSide;
    if (adv > 0.5) {
      advSymbol = '±';
      advSide = 'White better';
    } else if (adv < -0.5) {
      advSymbol = '∓';
      advSide = 'Black better';
    } else {
      advSymbol = '=';
      advSide = 'Equal';
    }
    final String advLine =
        'advantage: ${adv.toStringAsFixed(2)} $advSymbol ($advSide)';

    // Add piece positions lines
    final String whitePiecesLine = 'whitePieces: [${whitePieces.join(', ')}]';
    final String blackPiecesLine = 'blackPieces: [${blackPieces.join(', ')}]';
    final String emptySquaresLine =
        'emptySquares: [${emptySquares.join(', ')}]';

    final StringBuffer ctx = StringBuffer();
    ctx.writeln('\n## Dynamic Context');
    ctx.writeln(phaseLine);
    ctx.writeln(sideLine);
    ctx.writeln(boardLine);
    ctx.writeln(whitePiecesLine);
    ctx.writeln(blackPiecesLine);
    ctx.writeln(emptySquaresLine);
    ctx.writeln(countsLine);
    ctx.writeln(millsLine);
    ctx.writeln(crossLine);
    ctx.writeln(cornersLine);
    if (mobilityLine.isNotEmpty) {
      ctx.writeln(mobilityLine);
    }
    ctx.writeln(threatLine);
    ctx.writeln(lastMoveLine);
    if (legalLine.isNotEmpty) {
      ctx.writeln(legalLine);
    }
    ctx.writeln(advLine);
    return ctx.toString();
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
