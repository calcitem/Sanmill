// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// history_navigation.dart

part of '../mill.dart';

/// HistoryNavigator
///
/// Helper class to use [HistoryNavigator.doEachMove] in different scenarios.
/// This class will also try to handle any errors and visualize the results.
class HistoryNavigator {
  const HistoryNavigator._();

  static const String _logTag = "[HistoryNavigator]";

  static String importFailedStr = "";
  static bool _isGoingToHistory = false;

  static Future<HistoryResponse?> _gotoHistory(
    BuildContext context,
    HistoryNavMode navMode, {
    bool pop = true,
    bool toolbar = false,
    int? number,
  }) async {
    // Clear any existing analysis markers when player makes a move
    AnalysisMode.disable();

    // Disable statistics
    GameController().disableStats = true;

    // -----------------------------------------------------------
    //  LAN mode special rules:
    //   - Only single-step takeBack is allowed (requires remote approval).
    //   - All other history nav is disallowed in LAN mode.
    // -----------------------------------------------------------
    final GameMode currentMode = GameController().gameInstance.gameMode;
    if (currentMode == GameMode.humanVsLAN) {
      if (navMode == HistoryNavMode.takeBack && number == null) {
        // This is the user tapping a "Take Back 1" button
        // Request a single-step take back from the opponent
        final bool success = await _requestLanTakeBack(context, 1);
        // If user & remote accepted, success=true => done
        // If rejected or an error, success=false => do nothing
        if (pop && context.mounted) {
          Navigator.pop(context);
        }
        return success ? const HistoryOK() : const HistoryAbort();
      } else {
        // For takeBackN>=2, takeBackAll, stepForward, stepForwardAll => disallow
        if (context.mounted) {
          // In LAN mode, only single-step take back is allowed.
          final String takeBackRejected = S.of(context).takeBackRejected;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(takeBackRejected)));
        }
        if (pop && context.mounted) {
          Navigator.pop(context);
        }
        return const HistoryAbort();
      }
    }

    // ---------------  Normal (non-LAN) logic  ---------------
    assert(navMode != HistoryNavMode.takeBackN || number != null);

    if (pop == true || toolbar == true) {
      GameController().loadedGameFilenamePrefix = null;
    }

    if (GameController().isEngineInDelay) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).aiIsDelaying,
      );
      if (pop) {
        Navigator.pop(context);
      }
      return const HistoryOK();
    }

    GameController().isControllerActive = false;
    GameController().engine.stopSearching();

    final GameController controller = GameController();

    // TODO: Move to the end of this function. Or change to S.of(context).waiting?
    GameController().headerTipNotifier.showTip(S.of(context).atEnd);
    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();

    if (_isGoingToHistory) {
      logger.i("$_logTag Is going to history, ignore repeated request.");
      if (pop) {
        Navigator.pop(context);
      }
      return const HistoryOK();
    }

    _isGoingToHistory = true;
    SoundManager().mute();

    if (navMode == HistoryNavMode.takeBackAll ||
        navMode == HistoryNavMode.takeBackN ||
        navMode == HistoryNavMode.takeBack) {
      GameController().animationManager.allowAnimations = false;
    }

    // Replay moves to get the new board state
    final HistoryResponse resp = await doEachMove(navMode, number);

    GameController().animationManager.allowAnimations = true;

    if (!context.mounted) {
      return const HistoryAbort();
    }

    switch (resp) {
      case HistoryOK():
        final ExtMove? lastEffectiveMove =
            controller.gameRecorder.activeNode?.data;
        if (lastEffectiveMove != null) {
          GameController().headerTipNotifier.showTip(
            S.of(context).lastMove(lastEffectiveMove.notation),
          );
          GameController().headerIconsNotifier.showIcons();
          GameController().boardSemanticsNotifier.updateSemantics();
        }
        break;
      case HistoryRange(): // TODO: Impossible resp
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).atEnd,
        );
        logger.i(HistoryRange);
        break;
      case HistoryRule():
      default:
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).movesAndRulesNotMatch,
        );
        logger.i(HistoryRule);
        break;
    }

    SoundManager().unMute();
    await navMode.gotoHistoryPlaySound();

    _isGoingToHistory = false;

    if (pop) {
      if (!context.mounted) {
        return const HistoryAbort();
      }
      Navigator.pop(context);
    }

    return resp;
  }

  /// Requests a 1-step LAN take back, returns true if accepted, false if rejected or error.
  static Future<bool> _requestLanTakeBack(
    BuildContext context,
    int steps,
  ) async {
    if (steps != 1) {
      return false;
    }
    // This calls a new method in GameController that sends "take back:1:request"
    // and awaits an async result from the peer.
    final bool ok = await GameController().requestLanTakeBack(steps);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).takeBackRequestWasRejectedOrFailed),
        ),
      );
    }
    return ok;
  }

  static Future<HistoryResponse?> takeBack(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBack,
      pop: pop,
      toolbar: toolbar,
    );
  }

  static Future<HistoryResponse?> stepForward(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.stepForward,
      pop: pop,
      toolbar: toolbar,
    );
  }

  static Future<HistoryResponse?> takeBackAll(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBackAll,
      pop: pop,
      toolbar: toolbar,
    );
  }

  static Future<HistoryResponse?> stepForwardAll(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.stepForwardAll,
      pop: pop,
      toolbar: toolbar,
    );
  }

  static Future<HistoryResponse?> stepForwardN(
    BuildContext context,
    int n, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBackN,
      number: n,
      pop: pop,
      toolbar: toolbar,
    );
  }

  /// Navigate to a specific variation branch
  /// This method switches to the given variation node and replays to that position
  static Future<HistoryResponse?> gotoVariation(
    BuildContext context,
    PgnNode<ExtMove> variationNode, {
    bool pop = true,
  }) async {
    // Simply use the existing gotoNode method which handles arbitrary nodes
    return gotoNode(context, variationNode, pop: pop);
  }

  /// Navigate forward selecting a specific variation by index
  /// Index 0 is the mainline, 1+ are variations
  static Future<HistoryResponse?> stepForwardToVariation(
    BuildContext context,
    int variationIndex, {
    bool pop = true,
  }) async {
    GameController().isControllerActive = false;
    GameController().engine.stopSearching();

    final GameRecorder recorder = GameController().gameRecorder;
    final PgnNode<ExtMove> current = recorder.activeNode ?? recorder.pgnRoot;

    if (current.children.isEmpty || variationIndex >= current.children.length) {
      if (pop && context.mounted) {
        Navigator.pop(context);
      }
      return const HistoryRange();
    }

    final PgnNode<ExtMove> targetNode = current.children[variationIndex];
    return gotoNode(context, targetNode, pop: pop);
  }

  /// Moves through the History by replaying all relevant moves.
  ///
  /// Returns a [HistoryResponse] when the moves and rules don't match
  /// or when the end of the move path has been reached.
  @visibleForTesting
  static Future<HistoryResponse> doEachMove(
    HistoryNavMode navMode, [
    int? number,
  ]) async {
    // 1) Adjust the active node according to navMode
    switch (navMode) {
      case HistoryNavMode.takeBack:
        _takeBack(1);
        break;
      case HistoryNavMode.takeBackN:
        if (number == null) {
          return const HistoryRange();
        }
        _takeBack(number);
        break;
      case HistoryNavMode.takeBackAll:
        _takeBackAll();
        break;
      case HistoryNavMode.stepForward:
        _stepForward(1);
        break;
      case HistoryNavMode.stepForwardAll:
        _stepForwardAll();
        break;
    }

    // 2) Temporarily set the game mode to humanVsHuman
    final GameMode backupMode = GameController().gameInstance.gameMode;
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

    if (GameController().newGameRecorder == null) {
      GameController().newGameRecorder = GameController().gameRecorder;
    }

    // 3) Reset board, replay moves from root to current HEAD
    // Preserve LAN connection during history replay if we're originally in LAN mode.
    GameController().reset(preserveLan: backupMode == GameMode.humanVsLAN);
    posKeyHistory.clear();

    final GameRecorder tempRec = GameController().newGameRecorder!;

    final List<ExtMove> pathMoves = _collectPathMoves(tempRec);

    bool success = true;
    for (final ExtMove move in pathMoves) {
      // Preserve preferredRemoveTarget during replay execution
      if (move.preferredRemoveTarget != null) {
        GameController().position.preferredRemoveTarget =
            move.preferredRemoveTarget;
      }

      if (!GameController().gameInstance.doMove(move)) {
        importFailedStr = move.notation;
        success = false;
        break;
      }
    }

    // 4) Restore context
    GameController().gameInstance.gameMode = backupMode;

    final String? lastPosWithRemove =
        GameController().gameRecorder.lastPositionWithRemove;

    // Restore the original recorder.  Its activeNode was correctly adjusted
    // by the nav-mode functions in step 1 (_takeBack, _stepForward, etc.)
    // and was NOT modified during the replay (which operates on the
    // separate recorder created by reset()).  No re-location is needed.
    GameController().gameRecorder = tempRec;
    GameController().gameRecorder.lastPositionWithRemove = lastPosWithRemove;
    GameController().newGameRecorder = null;

    return success ? const HistoryOK() : const HistoryRule();
  }

  static Future<HistoryResponse?> gotoNode(
    BuildContext context,
    PgnNode<ExtMove> targetNode, {
    bool pop = true,
  }) async {
    // Temporarily disable the controller and stop engine searching
    GameController().isControllerActive = false;
    GameController().engine.stopSearching();

    // Build the path from root to the targetNode
    final List<PgnNode<ExtMove>> path = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? cur = targetNode;
    while (cur != null) {
      path.insert(0, cur);
      cur = cur.parent;
    }

    // Save the original game mode
    final GameMode backupMode = GameController().gameInstance.gameMode;
    // Force into humanVsHuman so we can freely replay moves
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

    // CRITICAL: Save the original gameRecorder to preserve the PGN tree
    // reset() will create a new GameRecorder, losing all variations/branches
    final GameRecorder originalRecorder = GameController().gameRecorder;

    // Reset the board, clear position history, and replay moves on the path
    GameController().reset();
    posKeyHistory.clear();

    // Let reset() create a temporary new recorder for replay
    // This prevents adding duplicate nodes to the original tree

    bool success = true;
    for (final PgnNode<ExtMove> node in path) {
      if (node.data != null) {
        // Preserve preferredRemoveTarget during replay execution
        final ExtMove m = node.data!;
        if (m.preferredRemoveTarget != null) {
          GameController().position.preferredRemoveTarget =
              m.preferredRemoveTarget;
        }

        final bool ok = GameController().gameInstance.doMove(m);
        if (!ok) {
          importFailedStr = node.data!.notation;
          success = false;
          break;
        }
      }
    }

    // Restore game mode
    GameController().gameInstance.gameMode = backupMode;

    // CRITICAL: Restore the original gameRecorder AFTER replay
    // This preserves the PGN tree without adding duplicate nodes
    GameController().gameRecorder = originalRecorder;

    // Update the active node to the target
    GameController().gameRecorder.activeNode = targetNode;
    // Notify move count change using currentPath to reflect actual position
    GameController().gameRecorder.moveCountNotifier.value =
        GameController().gameRecorder.currentPath.length;

    // Re-enable the controller
    GameController().isControllerActive = true;
    SoundManager().unMute();

    // Optionally close the current route if pop == true
    if (pop && context.mounted) {
      Navigator.pop(context);
    }

    return success ? const HistoryOK() : const HistoryRule();
  }

  /// Move HEAD up by `n` steps if possible.
  /// Records the child we came from at each step so that subsequent forward
  /// navigation can resume along the same variation branch.
  static void _takeBack(int n) {
    final GameRecorder rec = GameController().gameRecorder;
    while (n-- > 0) {
      final PgnNode<ExtMove>? node = rec.activeNode;
      if (node == null || node.parent == null) {
        break;
      }
      // Record the preferred child before moving up so that _stepForward
      // knows which branch to resume.
      final PgnNode<ExtMove> parent = node.parent!;
      final int childIdx = parent.children.indexOf(node);
      if (childIdx >= 0) {
        rec.setPreferredChild(parent, childIdx);
      }
      rec.activeNode = parent;
    }

    // Notify move count change — use currentPath for variation correctness.
    rec.moveCountNotifier.value = rec.currentPath.length;
  }

  /// Move HEAD to the root.
  /// Records preferred children along the full path so that a subsequent
  /// _stepForwardAll can retrace the exact same variation.
  static void _takeBackAll() {
    final GameRecorder rec = GameController().gameRecorder;
    // Walk from current position to root, recording preferred child at every
    // branching point.
    PgnNode<ExtMove>? node = rec.activeNode;
    while (node != null && node.parent != null) {
      final PgnNode<ExtMove> parent = node.parent!;
      final int childIdx = parent.children.indexOf(node);
      if (childIdx >= 0) {
        rec.setPreferredChild(parent, childIdx);
      }
      node = parent;
    }
    // HEAD => pgnRoot
    rec.activeNode = rec.pgnRoot;
    rec.moveCountNotifier.value = 0;
  }

  /// Move HEAD forward by `n` steps.
  /// When [explicitVariationIndex] is provided it overrides the preferred
  /// child lookup; otherwise the recorder's preferred-child map is consulted
  /// so that forward navigation resumes along the variation the user was in.
  static void _stepForward(int n, {int? explicitVariationIndex}) {
    final GameRecorder rec = GameController().gameRecorder;
    while (n-- > 0) {
      final PgnNode<ExtMove> current = rec.activeNode ?? rec.pgnRoot;
      if (current.children.isEmpty) {
        break;
      }
      final int index = _resolveChildIndex(
        rec,
        current,
        explicitVariationIndex,
      );
      rec.activeNode = current.children[index];
    }
    rec.moveCountNotifier.value = rec.currentPath.length;
  }

  /// Move HEAD forward to the very end along the current variation path.
  /// At every branching point the recorder's preferred-child map is consulted
  /// so that the navigation retraces the exact variation the user was in
  /// before taking back.
  static void _stepForwardAll() {
    final GameRecorder rec = GameController().gameRecorder;
    while (true) {
      final PgnNode<ExtMove> current = rec.activeNode ?? rec.pgnRoot;
      if (current.children.isEmpty) {
        break;
      }
      final int index = _resolveChildIndex(rec, current, null);
      rec.activeNode = current.children[index];
    }
    rec.moveCountNotifier.value = rec.currentPath.length;
  }

  /// Determines which child to follow at [node].
  /// Priority: explicit override > preferred child from takeBack history > 0.
  static int _resolveChildIndex(
    GameRecorder rec,
    PgnNode<ExtMove> node,
    int? explicitIndex,
  ) {
    if (explicitIndex != null) {
      return explicitIndex.clamp(0, node.children.length - 1);
    }
    final int preferred = rec.getPreferredChildIndex(node);
    return preferred.clamp(0, node.children.length - 1);
  }

  /// Collect all moves from HEAD up to the root
  static List<ExtMove> _collectPathMoves(GameRecorder rec) {
    final List<ExtMove> moves = <ExtMove>[];
    PgnNode<ExtMove>? cur = rec.activeNode;
    while (cur != null && cur.parent != null) {
      // if it has data, add it
      if (cur.data != null) {
        moves.add(cur.data!);
      }
      cur = cur.parent;
    }
    // Reverse them because we collected from HEAD up to root
    return moves.reversed.toList();
  }
}

enum HistoryNavMode {
  takeBack,
  stepForward,
  takeBackAll,
  stepForwardAll,
  takeBackN,
}

extension HistoryNavModeExtension on HistoryNavMode {
  Future<void> gotoHistoryPlaySound() async {
    if (DB().generalSettings.keepMuteWhenTakingBack) {
      return;
    }
    switch (this) {
      case HistoryNavMode.stepForwardAll:
      case HistoryNavMode.stepForward:
        return SoundManager().playTone(Sound.place);
      case HistoryNavMode.takeBackAll:
      case HistoryNavMode.takeBackN:
      case HistoryNavMode.takeBack:
        return SoundManager().playTone(Sound.remove);
    }
  }
}
