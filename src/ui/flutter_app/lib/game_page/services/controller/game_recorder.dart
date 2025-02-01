// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// GameRecorder holds the move history and also maintains
/// a PGN tree internally. It extends a PointedList of ExtMove
/// **for backward compatibility**.
///
/// ---
/// **LEGACY NOTE (Phase 1)**:
/// - This class extends `PointedList<ExtMove>` for **legacy** usage only.
/// - Please switch to the **PGN-based** methods (`pgnRoot`, `mainlineMoves`, `getMainlineMove`, etc.)
/// - The old array-like and pointer-like APIs (`index`, `operator[]`, `add()`, `prune()`, etc.)
///   are now **@deprecated** and will be removed in the future.
/// ---
///
/// Existing code can continue using `recorder[index!]`, `recorder.add(move)`,
/// but we encourage migration to the new PGN methods.
class GameRecorder extends PointedList<ExtMove> {
  GameRecorder({this.lastPositionWithRemove, this.setupPosition});

  /// The user's last position with remove operation, if any.
  String? lastPositionWithRemove = "";

  /// Custom setup position. If not null, it will be used instead of current fen.
  String? setupPosition;

  /// A new field that holds the PGN node tree for ExtMove.
  /// For now we only maintain a single mainline chain (children[0], children[0], ...).
  /// The internal PGN tree.
  /// Previously `_pgnRoot` was private and inaccessible
  /// to external callers. Now we expose it as `pgnRoot`.
  final PgnNode<ExtMove> _pgnRoot = PgnNode<ExtMove>();

  /// Read-only getter for the PGN tree, allowing external code
  /// to navigate or augment the PGN node structure.
  ///
  /// For example, callers can do:
  /// ```dart
  /// final mainNode = recorder.pgnRoot;
  /// mainNode.children.add(...);
  /// ```
  PgnNode<ExtMove> get pgnRoot => _pgnRoot;

  /// Returns all the moves from the PGN main line as a list.
  /// This is just a convenience wrapper for `_pgnRoot.mainline()`.
  ///
  /// For example:
  /// ```dart
  /// final mainline = recorder.mainlineMoves;
  /// ```
  List<ExtMove> get mainlineMoves => _pgnRoot.mainline().toList();

  /// Example of a bridging method: If you need to fetch a node at
  /// a certain index from the PGN mainline, you could do so here.
  ///
  /// But typically you'll either use:
  /// 1) Existing PointedList access: `[index]`
  /// 2) Or new PGN-based traversal: `pgnRoot.mainline()`
  ExtMove getMainlineMove(int index) {
    final List<ExtMove> line = mainlineMoves;
    if (index < 0 || index >= line.length) {
      throw RangeError('Index out of range: $index');
    }
    return line[index];
  }

  bool isAtEnd() {
    return index == mainlineMoves.length - 1 ||
        (index == null && mainlineMoves.isEmpty);
  }

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer("[ ");
    for (final ExtMove extMove in this) {
      buffer.write("${extMove.move}, ");
    }

    buffer.write("]");

    return buffer.toString();
  }

  // ----------------------------------------------------------------------
  //  Pointer logic. (Some are newly marked as @deprecated bridging methods)
  // ----------------------------------------------------------------------

  int? _currentIndex;

  @Deprecated('Use [mainlineMoves] or [getMainlineMove] instead.')
  @override
  int? get index => _currentIndex;

  // Parent does NOT define a setter for `index`, so no @override here.
  set index(int? newIndex) {
    _currentIndex = newIndex;
  }

  bool get hasNext {
    if (mainlineMoves.isEmpty) {
      return false;
    }
    if (_currentIndex == null) {
      return true;
    }
    return _currentIndex! < mainlineMoves.length - 1;
  }

  // Parent DOES define hasPrevious, so we keep @override.
  @override
  bool get hasPrevious {
    if (mainlineMoves.isEmpty) {
      return false;
    }
    return _currentIndex != null;
  }

  bool moveNext() {
    if (!hasNext) {
      return false;
    }
    if (_currentIndex == null) {
      _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex! + 1;
    }
    return true;
  }

  bool movePrevious() {
    if (!hasPrevious) {
      return false;
    }
    if (_currentIndex == 0) {
      _currentIndex = null;
    } else {
      _currentIndex = _currentIndex! - 1;
    }
    return true;
  }

  void moveToHead() {
    _currentIndex = null;
  }

  void moveToLast() {
    if (mainlineMoves.isNotEmpty) {
      _currentIndex = mainlineMoves.length - 1;
    }
  }

  void moveTo(int targetIndex) {
    if (mainlineMoves.isEmpty) {
      return;
    }
    _currentIndex = targetIndex;
    if (_currentIndex! < 0) {
      _currentIndex = null;
    } else if (_currentIndex! >= mainlineMoves.length) {
      _currentIndex = mainlineMoves.length - 1;
    }
  }

  // Parent DOES define `E? get current`, so we keep @override.
  @override
  ExtMove? get current {
    if (_currentIndex == null) {
      return null;
    }
    return mainlineMoves[_currentIndex!];
  }

  ExtMove? get prev {
    if (_currentIndex == null || _currentIndex == 0) {
      return null;
    }
    return mainlineMoves[_currentIndex! - 1];
  }

  // Parent DOES define `PointedListIterator<E> get globalIterator`, so keep @override.
  @override
  PointedListIterator<ExtMove> get globalIterator =>
      _GameRecorderIterator(this);

  /// Example: Count how many 'place' moves exist in the visible portion (0..index).
  int get placeCount {
    if (isEmpty || index == null) {
      return 0;
    }

    int n = 0;

    for (int i = 0; i <= index!; i++) {
      if (this[i].type == MoveType.place) {
        n++;
      }
    }

    return n;
  }

  // ----------------------------------------------------------------------
  //  Bridging: old "list-style" add and prune. Mark them as @deprecated.
  // ----------------------------------------------------------------------

  @Deprecated('Use [getMainlineMove(i)] or [mainlineMoves] instead.')
  @override
  ExtMove operator [](int index) => getMainlineMove(index);

  @Deprecated('Use PGN logic or [pgnRoot.children.add()] instead.')
  @override
  void add(ExtMove value) {
    // 0) prune the forward moves, if any, to remain consistent.
    prune();

    // 1) Call the parent add to keep the PointedList updated.
    super.add(value);

    // 2) Sync to _pgnRoot. We assume a single main line.
    if (_pgnRoot.children.isEmpty) {
      // If no child at all, just add the first child
      _pgnRoot.children.add(PgnChildNode<ExtMove>(value));
    } else {
      // Otherwise walk down the mainline until we reach the end.
      PgnNode<ExtMove> tail = _pgnRoot;
      while (tail.children.isNotEmpty) {
        tail = tail.children.first;
      }
      tail.children.add(PgnChildNode<ExtMove>(value));
    }
    _currentIndex = mainlineMoves.length - 1;
  }

  @Deprecated('Use PGN logic or GN logic or `_prunePgnNode` instead.')
  @override
  void prune() {
    // 1) Prune the underlying PointedList logic
    super.prune();

    // 2) Reflect the pruning in _pgnRoot
    _prunePgnNode(_pgnRoot, index);

    if (mainlineMoves.isEmpty) {
      _currentIndex = null;
    } else if (_currentIndex != null &&
        _currentIndex! >= mainlineMoves.length) {
      _currentIndex = mainlineMoves.length - 1;
    }
  }

  /// A helper method to remove extra child nodes from _pgnRoot
  /// after the [keepIndex].
  void _prunePgnNode(PgnNode<ExtMove> node, int? keepIndex) {
    // If there's no index (== null), it means no valid moves. Clear everything.
    if (keepIndex == null) {
      node.children.clear();
      return;
    }
    // We keep the first [keepIndex + 1] moves in a single chain:
    int remaining = keepIndex + 1;

    // Start from the root, and walk down child[0] repeatedly.
    PgnNode<ExtMove> current = node;
    while (remaining > 0 && current.children.isNotEmpty) {
      remaining--;
      // If after decrementing 'remaining' we are at 0, we remove all extra
      // siblings and deeper children from the first child.
      if (remaining == 0) {
        // Keep only the first child in the list
        if (current.children.isNotEmpty) {
          current.children.removeRange(1, current.children.length);
          // Then go deeper and remove everything from its next generation
          current = current.children.first;
          current.children.clear();
        }
        return;
      }
      // If we still have more to keep, go deeper along the first child
      current = current.children.first;
    }

    // If we exit the loop but still have 'remaining' >= 0,
    // we must clear children from the last visited node:
    current.children.clear();
  }

  /// Returns a textual representation of the move history.
  /// Now we include NAG and comments by calling `_getRichMoveNotation()`.
  String get moveHistoryText {
    /// Build tag pairs such as FEN and SetUp lines.
    String buildTagPairs() {
      // If the user had a custom setupPosition, use it; otherwise, use the current position's fen.
      if (GameController().gameRecorder.setupPosition != null) {
        return '[FEN "${GameController().gameRecorder.setupPosition!}"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().position.fen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

    // If there are no moves, just return FEN tags if needed.
    if (isEmpty || index == null) {
      if (GameController().isPositionSetup == true) {
        return buildTagPairs();
      } else {
        return "";
      }
    }

    final StringBuffer moveHistory = StringBuffer();
    int num = 1;
    int i = 0;

    /// Build one step of notation (up to two moves per line).
    void buildStandardNotation() {
      const String separator = "    "; // Just for formatting alignment

      if (i <= index!) {
        // For the main move (either place/move/remove/draw/etc.)
        moveHistory.write(separator);
        moveHistory.write(_getRichMoveNotation(this[i++]));
      }
      // If the next moves are removal, handle them as well.
      for (int round = 0; round < 3; round++) {
        if (i <= index! && this[i].type == MoveType.remove) {
          moveHistory.write(_getRichMoveNotation(this[i++]));
        }
      }
    }

    // If the position is a custom setup, print the FEN tags first.
    if (GameController().isPositionSetup == true) {
      moveHistory.write(buildTagPairs());
    }

    // Walk through all moves in pairs (the typical chess-like formatting).
    while (i <= index!) {
      // TODO: When AI draw, print number but not move
      moveHistory.writeNumber(num++);
      buildStandardNotation();
      buildStandardNotation();

      if (i <= index!) {
        moveHistory.writeln();
      }
    }

    return moveHistory.toString();
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

/// Correctly overrides PointedListIterator's members for GameRecorder.
class _GameRecorderIterator extends PointedListIterator<ExtMove> {
  _GameRecorderIterator(this._rec) : super(<ExtMove>[]);

  final GameRecorder _rec;

  @override
  bool moveNext() => _rec.moveNext();

  @override
  bool movePrevious() => _rec.movePrevious();

  @override
  bool get hasNext => _rec.hasNext;

  @override
  bool get hasPrevious => _rec.hasPrevious;

  @override
  void moveTo(int index) => _rec.moveTo(index);

  @override
  void moveToFirst() => _rec.moveTo(0);

  @override
  void moveToHead() => _rec.moveToHead();

  @override
  void moveToLast() => _rec.moveToLast();

  @override
  ExtMove? get current => _rec.current;

  @override
  ExtMove? get prev => _rec.prev;

  @override
  int? get index => _rec.index;
}
