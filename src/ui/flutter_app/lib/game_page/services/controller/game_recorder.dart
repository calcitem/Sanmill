// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

class _MoveCountNotifier extends ValueNotifier<int> {
  _MoveCountNotifier(super.value);

  @override
  set value(int newValue) {
    final bool unchanged = super.value == newValue;
    super.value = newValue;
    if (unchanged) {
      notifyListeners();
    }
  }
}

/// GameRecorder holds the move history and maintains
/// a PGN tree internally. It now provides PGN-based APIs.
class GameRecorder {
  GameRecorder({this.lastPositionWithRemove, this.setupPosition}) {
    activeNode = _pgnRoot;
  }

  /// The user's last position with remove operation, if any.
  String? lastPositionWithRemove;

  /// Custom setup position. If not null, it will be used instead of current FEN.
  String? setupPosition;

  /// Notifier that fires whenever a move is made or undone.
  /// Listeners can use this to react to move changes in business logic.
  final ValueNotifier<int> moveCountNotifier = _MoveCountNotifier(0);

  /// PGN tree root node.
  /// Multiple branches are allowed; activeNode tracks the "current" branch.
  final PgnNode<ExtMove> _pgnRoot = PgnNode<ExtMove>();

  /// A pointer to the current node representing the HEAD of the active variation.
  /// If null, no moves have been made yet (or we are at root with no child).
  PgnNode<ExtMove>? activeNode;

  /// Tracks which child was last navigated through at each branching node.
  /// When taking back from a child, the child's index is recorded so that
  /// stepping forward can resume along the same variation instead of always
  /// defaulting to children[0] (mainline).
  /// Cleared when the tree structure changes (new moves, reset).
  final Map<PgnNode<ExtMove>, int> _preferredChildIndex =
      <PgnNode<ExtMove>, int>{};

  /// Records the preferred forward child at [parent].
  void setPreferredChild(PgnNode<ExtMove> parent, int childIndex) {
    _preferredChildIndex[parent] = childIndex;
  }

  /// Returns the preferred child index at [node], or 0 (mainline) if none.
  int getPreferredChildIndex(PgnNode<ExtMove> node) {
    return _preferredChildIndex[node] ?? 0;
  }

  /// Clears all preferred child records.
  void clearPreferredChildren() {
    _preferredChildIndex.clear();
  }

  /// Getter to expose the root node.
  PgnNode<ExtMove> get pgnRoot => _pgnRoot;

  /// Returns the PGN game termination marker matching the current game result.
  ///
  /// This ensures the movetext termination marker is consistent with the
  /// `[Result]` header written by [ImportService.addTagPairs].
  String get gameResultPgn {
    switch (GameController().activeSessionWinner ??
        GameController().activeBoardView.winner) {
      case PieceColor.white:
        return '1-0';
      case PieceColor.black:
        return '0-1';
      case PieceColor.draw:
        return '1/2-1/2';
      case PieceColor.marked:
      case PieceColor.none:
      case PieceColor.nobody:
        return '*';
    }
  }

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
    // If activeNode is null or pgnRoot, check if there are any children.
    // Otherwise check if the current node has children.
    if (node == null || node == _pgnRoot) {
      return _pgnRoot.children.isEmpty;
    }
    return node.children.isEmpty;
  }

  /// Resets the game recorder by clearing all moves and resetting the active node.
  void reset() {
    _pgnRoot.children.clear();
    // Set activeNode to pgnRoot (root position) instead of null
    // to maintain consistency with history navigation behavior.
    activeNode = _pgnRoot;
    lastPositionWithRemove = null;
    _preferredChildIndex.clear();
    moveCountNotifier.value = 0;
  }

  /// Applies a Mill board symmetry to every recorded coordinate.
  ///
  /// This is used when the user transforms an active local game position. The
  /// native session FEN is transformed separately; this method keeps the PGN
  /// tree, setup FEN, and per-node board layouts in the same coordinate frame.
  void transformCoordinates(TransformationType type) {
    setupPosition = _transformFenOrNull(setupPosition, type);
    lastPositionWithRemove = _transformFenOrNull(lastPositionWithRemove, type);
    _transformNodeCoordinates(_pgnRoot, type);
    moveCountNotifier.value = currentPath.length;
  }

  void _transformNodeCoordinates(
    PgnNode<ExtMove> node,
    TransformationType type,
  ) {
    final ExtMove? move = node.data;
    if (move != null) {
      node.data = _transformMove(move, type);
    }
    for (final PgnNode<ExtMove> child in node.children) {
      _transformNodeCoordinates(child, type);
    }
  }

  ExtMove _transformMove(ExtMove move, TransformationType type) {
    final ExtMove transformed = ExtMove(
      transformMoveNotation(move.move, type),
      side: move.side,
      boardLayout: _transformFenOrNull(move.boardLayout, type),
      moveIndex: move.moveIndex,
      roundIndex: move.roundIndex,
      preferredRemoveTarget: _transformPreferredRemoveTarget(
        move.preferredRemoveTarget,
        type,
      ),
      nags: move.nags == null ? null : List<int>.from(move.nags!),
      startingComments: move.startingComments == null
          ? null
          : List<String>.from(move.startingComments!),
      comments: move.comments == null
          ? null
          : List<String>.from(move.comments!),
    );
    transformed.quality = move.quality;
    transformed.isVariation = move.isVariation;
    transformed.variationDepth = move.variationDepth;
    transformed.branchColumns = move.branchColumns == null
        ? null
        : List<bool>.from(move.branchColumns!);
    transformed.branchColumn = move.branchColumn;
    transformed.branchLineType = move.branchLineType;
    transformed.isLastSibling = move.isLastSibling;
    transformed.siblingIndex = move.siblingIndex;
    return transformed;
  }

  String? _transformFenOrNull(String? fen, TransformationType type) {
    if (fen == null || fen.isEmpty) {
      return fen;
    }
    assert(
      fen.length >= 26,
      'Mill FEN or board layout must include the 26-character board field.',
    );
    return transformFEN(fen, type);
  }

  int? _transformPreferredRemoveTarget(int? square, TransformationType type) {
    if (square == null || square <= 0) {
      return square;
    }
    final String notation = MillBoardCoordinateMaps.legacySquareToNotation(
      square,
    );
    assert(notation.isNotEmpty, 'Preferred remove target must be a Mill node.');
    final String transformed = transformMoveNotation(notation, type);
    final int transformedSquare =
        MillBoardCoordinateMaps.notationToLegacySquare(transformed);
    assert(
      transformedSquare > 0,
      'Transformed preferred remove target must be a Mill node.',
    );
    return transformedSquare;
  }

  /// Appends a new move at the end of the current active line.
  /// If a move already exists at this position with different notation,
  /// creates a new variation branch.
  void appendMove(ExtMove move, {bool createVariation = true}) {
    if (activeNode == null) {
      // Treat null as "at root". Never walk to the tail here:
      // - When users navigate back to the start position, the head is pgnRoot.
      // - If a bug ever sets activeNode=null while moves exist, appending to the
      //   tail will silently corrupt history by duplicating moves at the end.
      final PgnNode<ExtMove> where = _pgnRoot;

      bool isNewVariation = false;
      if (where.children.isNotEmpty && createVariation) {
        // Follow an existing matching first move when possible.
        for (final PgnNode<ExtMove> child in where.children) {
          if (child.data != null && child.data!.move == move.move) {
            activeNode = child;
            moveCountNotifier.value = currentPath.length;
            return;
          }
        }
        // No match found among existing children — this is a new variation.
        isNewVariation = true;
      }

      // New node creation invalidates preferred-child navigation state.
      _preferredChildIndex.clear();

      final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(move);
      newChild.parent = where;
      if (isNewVariation) {
        // Append as variation to preserve existing mainline order.
        where.children.add(newChild);
      } else {
        // No existing children or createVariation=false: first child = mainline.
        where.children.insert(0, newChild);
      }
      activeNode = newChild;
    } else {
      // Check if active node already has children
      if (activeNode!.children.isNotEmpty && createVariation) {
        // IMPORTANT: Check ALL children to see if this move already exists
        // This allows re-walking existing variations without creating duplicates
        PgnNode<ExtMove>? matchingChild;

        for (int i = 0; i < activeNode!.children.length; i++) {
          final ExtMove? childMove = activeNode!.children[i].data;
          if (childMove != null && childMove.move == move.move) {
            matchingChild = activeNode!.children[i];
            break;
          }
        }

        if (matchingChild != null) {
          // Found matching move in existing children - follow it
          activeNode = matchingChild;
        } else {
          // No matching child found - create new variation.
          // Append (not insert at 0) to preserve existing mainline order.
          _preferredChildIndex.clear();
          final PgnNode<ExtMove> variationNode = PgnNode<ExtMove>(move);
          variationNode.parent = activeNode;
          activeNode!.children.add(variationNode);
          activeNode = variationNode;
        }
      } else {
        // Extend the active line by inserting new move at the front of children.
        _preferredChildIndex.clear();
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

    // Check if activeNode itself is already this move (avoid duplicate)
    if (node.data?.move == newMove.move) {
      // Already at this move, do nothing
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
  /// IMPORTANT: Now checks if the move already exists in children to avoid duplicates.
  /// New branches are appended (not inserted at position 0) to preserve mainline stability.
  void branchNewMoveFromActiveNode(ExtMove newMove) {
    final PgnNode<ExtMove> where = activeNode ?? _pgnRoot;

    // Check if this move already exists in children to avoid duplicates
    for (int i = 0; i < where.children.length; i++) {
      final ExtMove? childMove = where.children[i].data;
      if (childMove != null && childMove.move == newMove.move) {
        // Move already exists - just follow it instead of creating duplicate
        activeNode = where.children[i];
        moveCountNotifier.value = currentPath.length;
        return;
      }
    }

    // No matching child found - create new branch.
    // Use add() instead of insert(0, ...) to preserve existing mainline order.
    _preferredChildIndex.clear();
    final PgnNode<ExtMove> newChild = PgnNode<ExtMove>(newMove);
    newChild.parent = where;
    where.children.add(newChild);
    activeNode = newChild;
    moveCountNotifier.value = currentPath.length;
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
      return '[FEN "${GameController().activeFen}"]\r\n[SetUp "1"]\r\n\r\n';
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

    // PGN standard 8.2.5: A move number indication is forced after
    // the close of a RAV. This flag tracks whether any variation was
    // output so the next mainline move can restate its move number.
    bool hadVariation = false;

    // Detect if the first non-removal move is black's (e.g., from a
    // FEN setup where black moves first).
    final bool startsWithBlack =
        nodes.isNotEmpty &&
        nodes[0].data != null &&
        nodes[0].data!.side == PieceColor.black &&
        nodes[0].data!.type != MoveType.remove;

    // Build one step of notation (up to two moves per line).
    // Variations are deferred until after the complete turn
    // (placement/movement + removals) so the full mainline move
    // is shown before any alternative branches.
    void buildStandardNotation() {
      const String sep = " ";
      // Collect all nodes in this turn for deferred variation output.
      final List<PgnNode<ExtMove>> turnNodes = <PgnNode<ExtMove>>[];

      if (i < nodes.length) {
        final PgnNode<ExtMove> currentNode = nodes[i];
        sb.write(sep);
        sb.write(_formatMoveWithAnnotations(currentNode));
        turnNodes.add(currentNode);
        i++;
      }

      // Process subsequent removal moves (up to 3) if present.
      for (int round = 0; round < 3; round++) {
        if (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          final PgnNode<ExtMove> currentNode = nodes[i];
          sb.write(_formatMoveWithAnnotations(currentNode));
          turnNodes.add(currentNode);
          i++;
        }
      }

      // Output all variations AFTER the complete turn so readers
      // see the full mainline move (e.g. "d6xc3") before branches.
      for (final PgnNode<ExtMove> node in turnNodes) {
        if (node.parent != null && node.parent!.children.length > 1) {
          final int currentIndex = node.parent!.children.indexOf(node);
          if (currentIndex == 0) {
            for (
              int varIdx = 1;
              varIdx < node.parent!.children.length;
              varIdx++
            ) {
              sb.write(' (');
              sb.write(_formatVariation(node.parent!.children[varIdx], num));
              sb.write(')');
            }
            hadVariation = true;
          }
        }
      }
    }

    // Write FEN tag pairs if a custom position is set.
    if (GameController().isPositionSetup) {
      sb.write(buildTagPairs());
    }

    // PGN standard: if the game starts with black's move, output the
    // initial black half-move with "N..." notation before entering
    // the standard white-black pair loop.
    if (startsWithBlack && i < nodes.length) {
      sb.write('$num...');
      hadVariation = false;
      buildStandardNotation();
      // PGN 8.2.5: if black's initial move had a variation, the
      // forced move number for white's next move is naturally
      // provided by sb.writeNumber(num) at the next iteration.
      num++;
      if (i < nodes.length) {
        sb.writeln();
      }
    }

    // Walk through the remaining moves in white-black pairs.
    while (i < nodes.length) {
      sb.writeNumber(num);
      hadVariation = false;
      buildStandardNotation();
      // PGN standard 8.2.5: restate move number after RAV close.
      if (hadVariation && i < nodes.length) {
        sb.write(' $num...');
      }
      hadVariation = false;
      buildStandardNotation();
      // PGN 8.2.5: after black's RAV close, the forced move number
      // for the next white move is provided by sb.writeNumber(num)
      // at the top of the next iteration.
      num++;
      if (i < nodes.length) {
        sb.writeln();
      }
    }

    // PGN standard: append game termination marker.
    if (sb.isNotEmpty) {
      sb.write(' $gameResultPgn');
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
        sb.write('{${safeComment(comment)}} ');
      }
    }

    // Write the move notation
    sb.write(move.notation);

    // Write NAG symbols
    if (move.nags != null && move.nags!.isNotEmpty) {
      final String nagStr = _nagsToString(move.nags!);
      // Numeric NAGs ($N) need a preceding space per PGN standard;
      // symbolic NAGs (!, ?, etc.) attach directly to the move.
      if (nagStr.startsWith(r'$')) {
        sb.write(' ');
      }
      sb.write(nagStr);
    }

    // Write after-move comments
    if (move.comments != null && move.comments!.isNotEmpty) {
      for (final String comment in move.comments!) {
        sb.write(' {${safeComment(comment)}}');
      }
    }

    return sb.toString();
  }

  /// Formats a variation branch in compact notation.
  ///
  /// When a variation starts with a removal move, the preceding
  /// placement/movement from the parent node is prepended so the
  /// output always carries full move context (e.g. "1. d6xc3"
  /// instead of bare "xc3").
  String _formatVariation(PgnNode<ExtMove> start, int moveNumber) {
    final StringBuffer sb = StringBuffer();
    PgnNode<ExtMove>? current = start;
    int currentMove = moveNumber;
    PieceColor? lastSide;

    // PGN standard 8.2.5: track whether a nested RAV was just closed
    // so the next move restates its move number.
    bool hadNestedVariation = false;

    // If the variation begins with a removal move, prefix with the
    // parent's placement/movement notation for complete context.
    if (start.data != null &&
        start.data!.type == MoveType.remove &&
        start.parent != null &&
        start.parent!.data != null) {
      final ExtMove parentMove = start.parent!.data!;
      if (parentMove.side == PieceColor.white) {
        sb.write('$currentMove. ');
      } else {
        sb.write('$currentMove... ');
      }
      sb.write(parentMove.notation);
      // Initialise lastSide so subsequent moves get correct numbering.
      lastSide = parentMove.side;
    }

    // Collect nested variations for deferred output so the full
    // mainline turn (placement/movement + removals) is shown before
    // any alternative branches.
    final List<PgnNode<ExtMove>> deferredVarNodes = <PgnNode<ExtMove>>[];
    final List<int> deferredVarMoveNums = <int>[];

    while (current != null && current.data != null) {
      final ExtMove move = current.data!;

      // Write starting comments
      if (move.startingComments != null && move.startingComments!.isNotEmpty) {
        for (final String comment in move.startingComments!) {
          sb.write('{${safeComment(comment)}} ');
        }
      }

      // Write move number following PGN standard:
      // 1. White's move: always show "N."
      // 2. Black's move: show "N..." if:
      //    a) First move in variation AND it's black's move
      //    b) Previous move was also black (consecutive black moves)
      //    c) A nested RAV was just closed (PGN 8.2.5)
      // 3. Black's move right after white's move (same turn): omit
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
          // For black, show when variation starts with black,
          // after consecutive black moves, or after a nested RAV.
          final bool variationStartsWithBlack = isFirstMove;
          final bool consecutiveBlackMoves = lastSide == PieceColor.black;
          showMoveNumber =
              variationStartsWithBlack ||
              consecutiveBlackMoves ||
              hadNestedVariation;
        }
      }

      // Reset nested-variation flag after it has been consumed by a
      // non-removal move (removal moves are concatenated and do not
      // represent a new half-move).
      if (isNonRemoveMove) {
        hadNestedVariation = false;
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
        final String nagStr = _nagsToString(move.nags!);
        // Numeric NAGs ($N) need a preceding space per PGN standard;
        // symbolic NAGs (!, ?, etc.) attach directly to the move.
        if (nagStr.startsWith(r'$')) {
          sb.write(' ');
        }
        sb.write(nagStr);
      }

      // Write after-move comments
      if (move.comments != null && move.comments!.isNotEmpty) {
        for (final String comment in move.comments!) {
          sb.write(' {${safeComment(comment)}}');
        }
      }

      // Collect nested variations instead of outputting them now.
      // They will be emitted after all removal moves in this turn
      // have been written (see deferred output below).
      if (current.children.length > 1) {
        final int varMoveNum = move.side == PieceColor.black
            ? currentMove + 1
            : currentMove;
        for (int i = 1; i < current.children.length; i++) {
          deferredVarNodes.add(current.children[i]);
          deferredVarMoveNums.add(varMoveNum);
        }
      }

      // Update move number and track last side
      if (move.type != MoveType.remove && move.side == PieceColor.black) {
        currentMove++;
      }
      if (move.type != MoveType.remove) {
        lastSide = move.side;
      }

      // Determine whether the next mainline node is a removal.
      final bool nextIsRemoval =
          current.children.isNotEmpty &&
          current.children[0].data != null &&
          current.children[0].data!.type == MoveType.remove;

      // Output all deferred variations once the turn is complete
      // (i.e. when the next node is not a removal, or there are no
      // more children).  This ensures the full mainline move such
      // as "f2xf4" is shown before branches like "(3. f2xb6)".
      if (!nextIsRemoval && deferredVarNodes.isNotEmpty) {
        for (int j = 0; j < deferredVarNodes.length; j++) {
          sb.write(' (');
          sb.write(
            _formatVariation(deferredVarNodes[j], deferredVarMoveNums[j]),
          );
          sb.write(')');
        }
        deferredVarNodes.clear();
        deferredVarMoveNums.clear();
        hadNestedVariation = true;
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
      // The legacy `_buildInlineContextFromBoardLayout` helper
      // generated a verbose annotation block (mobility, threats,
      // legal moves, advantage estimate) for the LLM context, but
      // it pulled state out of `Position._adjacentSquares` /
      // `Position._millTable` -- both gone with the rule-machine
      // cleanup.  Drop the per-move context for now; the AI chat
      // service still has access to the FEN + move history, so the
      // PGN export simply omits this annotation block.
      const String inlineCtx = "";

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

  /// Checks if the game tree contains any variations (branches).
  /// Returns true if any node in the tree has more than one child.
  bool hasVariations() {
    return _hasVariationsRecursive(_pgnRoot);
  }

  /// Recursively checks if any node in the tree has variations.
  bool _hasVariationsRecursive(PgnNode<ExtMove> node) {
    // If this node has more than one child, it has variations
    if (node.children.length > 1) {
      return true;
    }
    // Check all children recursively
    for (final PgnNode<ExtMove> child in node.children) {
      if (_hasVariationsRecursive(child)) {
        return true;
      }
    }
    return false;
  }

  /// Gets the move history text for current path only (from root to activeNode).
  String get moveHistoryTextCurrentLine {
    // Helper to build tag pair header (e.g. FEN, SetUp).
    String buildTagPairs() {
      if (setupPosition != null) {
        return '[FEN "$setupPosition"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().activeFen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

    final List<ExtMove> path = currentPath;

    if (path.isEmpty) {
      if (GameController().isPositionSetup) {
        return buildTagPairs();
      }
      return "";
    }

    final StringBuffer sb = StringBuffer();
    int num = 1;
    int i = 0;

    // Build one step of notation (up to two moves per line) - current path only
    void buildStandardNotation() {
      const String sep = " ";
      if (i < path.length) {
        final ExtMove move = path[i];
        sb.write(sep);
        sb.write(_formatMoveSimple(move));
        i++;
      }
      // Process subsequent removal moves (up to 3) if present.
      for (int round = 0; round < 3; round++) {
        if (i < path.length && path[i].type == MoveType.remove) {
          sb.write(_formatMoveSimple(path[i]));
          i++;
        }
      }
    }

    // Detect if the first non-removal move is black's (e.g., FEN setup).
    final bool startsWithBlack =
        path.isNotEmpty &&
        path[0].side == PieceColor.black &&
        path[0].type != MoveType.remove;

    // Write FEN tag pairs if a custom position is set.
    if (GameController().isPositionSetup) {
      sb.write(buildTagPairs());
    }

    // PGN standard: if the game starts with black's move, output the
    // initial black half-move with "N..." notation.
    if (startsWithBlack && i < path.length) {
      sb.write('$num...');
      buildStandardNotation();
      num++;
      if (i < path.length) {
        sb.writeln();
      }
    }

    // Walk through the remaining moves in white-black pairs.
    while (i < path.length) {
      sb.writeNumber(num);
      buildStandardNotation();
      buildStandardNotation();
      num++;
      if (i < path.length) {
        sb.writeln();
      }
    }

    // PGN standard: append game termination marker.
    if (sb.isNotEmpty) {
      sb.write(' $gameResultPgn');
    }

    return sb.toString();
  }

  /// Formats a single move with annotations (simple version without variations).
  String _formatMoveSimple(ExtMove move) {
    final StringBuffer sb = StringBuffer();

    // Write starting comments if present
    if (move.startingComments != null && move.startingComments!.isNotEmpty) {
      for (final String comment in move.startingComments!) {
        sb.write('{${safeComment(comment)}} ');
      }
    }

    // Write the move notation
    sb.write(move.notation);

    // Write NAG symbols
    if (move.nags != null && move.nags!.isNotEmpty) {
      final String nagStr = _nagsToString(move.nags!);
      // Numeric NAGs ($N) need a preceding space per PGN standard;
      // symbolic NAGs (!, ?, etc.) attach directly to the move.
      if (nagStr.startsWith(r'$')) {
        sb.write(' ');
      }
      sb.write(nagStr);
    }

    // Write after-move comments
    if (move.comments != null && move.comments!.isNotEmpty) {
      for (final String comment in move.comments!) {
        sb.write(' {${safeComment(comment)}}');
      }
    }

    return sb.toString();
  }

  /// Gets the move history text without variations (mainline only).
  String get moveHistoryTextWithoutVariations {
    // Helper to build tag pair header (e.g. FEN, SetUp).
    String buildTagPairs() {
      if (setupPosition != null) {
        return '[FEN "$setupPosition"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().activeFen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

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

    // Build one step of notation (up to two moves per line) - mainline only
    void buildStandardNotation() {
      const String sep = " ";
      if (i < nodes.length) {
        final PgnNode<ExtMove> currentNode = nodes[i];
        sb.write(sep);
        sb.write(_formatMoveWithAnnotationsMainlineOnly(currentNode));
        i++;
      }
      // Process subsequent removal moves (up to 3) if present.
      for (int round = 0; round < 3; round++) {
        if (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          final PgnNode<ExtMove> currentNode = nodes[i];
          sb.write(_formatMoveWithAnnotationsMainlineOnly(currentNode));
          i++;
        }
      }
    }

    // Detect if the first non-removal move is black's (e.g., FEN setup).
    final bool startsWithBlack =
        nodes.isNotEmpty &&
        nodes[0].data != null &&
        nodes[0].data!.side == PieceColor.black &&
        nodes[0].data!.type != MoveType.remove;

    // Write FEN tag pairs if a custom position is set.
    if (GameController().isPositionSetup) {
      sb.write(buildTagPairs());
    }

    // PGN standard: if the game starts with black's move, output the
    // initial black half-move with "N..." notation.
    if (startsWithBlack && i < nodes.length) {
      sb.write('$num...');
      buildStandardNotation();
      num++;
      if (i < nodes.length) {
        sb.writeln();
      }
    }

    // Walk through the remaining moves in white-black pairs.
    while (i < nodes.length) {
      sb.writeNumber(num);
      buildStandardNotation();
      buildStandardNotation();
      num++;
      if (i < nodes.length) {
        sb.writeln();
      }
    }

    // PGN standard: append game termination marker.
    if (sb.isNotEmpty) {
      sb.write(' $gameResultPgn');
    }

    return sb.toString();
  }

  /// Formats a single move with annotations but without variations.
  String _formatMoveWithAnnotationsMainlineOnly(PgnNode<ExtMove> node) {
    final ExtMove move = node.data!;
    final StringBuffer sb = StringBuffer();

    // Write starting comments if present
    if (move.startingComments != null && move.startingComments!.isNotEmpty) {
      for (final String comment in move.startingComments!) {
        sb.write('{${safeComment(comment)}} ');
      }
    }

    // Write the move notation
    sb.write(move.notation);

    // Write NAG symbols
    if (move.nags != null && move.nags!.isNotEmpty) {
      final String nagStr = _nagsToString(move.nags!);
      // Numeric NAGs ($N) need a preceding space per PGN standard;
      // symbolic NAGs (!, ?, etc.) attach directly to the move.
      if (nagStr.startsWith(r'$')) {
        sb.write(' ');
      }
      sb.write(nagStr);
    }

    // Write after-move comments
    if (move.comments != null && move.comments!.isNotEmpty) {
      for (final String comment in move.comments!) {
        sb.write(' {${safeComment(comment)}}');
      }
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
