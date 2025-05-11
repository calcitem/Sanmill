// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(takeBackRejected),
            ),
          );
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
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).aiIsDelaying);
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
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).atEnd);
        logger.i(HistoryRange);
        break;
      case HistoryRule():
      default:
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).movesAndRulesNotMatch);
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
      BuildContext context, int steps) async {
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
    return _gotoHistory(context, HistoryNavMode.takeBack,
        pop: pop, toolbar: toolbar);
  }

  static Future<HistoryResponse?> stepForward(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(context, HistoryNavMode.stepForward,
        pop: pop, toolbar: toolbar);
  }

  static Future<HistoryResponse?> takeBackAll(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(context, HistoryNavMode.takeBackAll,
        pop: pop, toolbar: toolbar);
  }

  static Future<HistoryResponse?> stepForwardAll(
    BuildContext context, {
    bool pop = true,
    bool toolbar = false,
  }) async {
    return _gotoHistory(context, HistoryNavMode.stepForwardAll,
        pop: pop, toolbar: toolbar);
  }

  static Future<HistoryResponse?> takeBackN(
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
    GameController().reset();
    posKeyHistory.clear();

    final GameRecorder tempRec = GameController().newGameRecorder!;

    final List<ExtMove> pathMoves = _collectPathMoves(tempRec);

    bool success = true;
    for (final ExtMove move in pathMoves) {
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
    GameController().gameRecorder = tempRec; // adopt the updated recorder
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

    // Reset the board, clear position history, and replay moves on the path
    GameController().reset();
    posKeyHistory.clear();

    bool success = true;
    for (final PgnNode<ExtMove> node in path) {
      if (node.data != null) {
        final bool ok = GameController().gameInstance.doMove(node.data!);
        if (!ok) {
          importFailedStr = node.data!.notation;
          success = false;
          break;
        }
      }
    }

    // Restore game mode
    GameController().gameInstance.gameMode = backupMode;

    // Update the active node to the target
    GameController().gameRecorder.activeNode = targetNode;

    // Re-enable the controller
    GameController().isControllerActive = true;
    SoundManager().unMute();

    // Optionally close the current route if pop == true
    if (pop && context.mounted) {
      Navigator.pop(context);
    }

    return success ? const HistoryOK() : const HistoryRule();
  }

  /// Move HEAD up by `n` steps if possible
  static void _takeBack(int n) {
    while (n-- > 0) {
      final PgnNode<ExtMove>? node = GameController().gameRecorder.activeNode;
      if (node == null) {
        break;
      }
      // If parent is null => at the root, cannot go further
      if (node.parent == null) {
        break;
      }
      // Just move activeNode to parent
      GameController().gameRecorder.activeNode = node.parent;
    }
  }

  /// Move HEAD to the root
  static void _takeBackAll() {
    // HEAD => pgnRoot
    GameController().gameRecorder.activeNode =
        GameController().gameRecorder.pgnRoot;
  }

  /// Move HEAD forward by `n` steps along the first child
  static void _stepForward(int n) {
    while (n-- > 0) {
      final PgnNode<ExtMove>? node = GameController().gameRecorder.activeNode;
      if (node == null) {
        final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
        if (root.children.isNotEmpty) {
          GameController().gameRecorder.activeNode = root.children.first;
        } else {
          break;
        }
      } else {
        if (node.children.isNotEmpty) {
          GameController().gameRecorder.activeNode = node.children.first;
        } else {
          break;
        }
      }
    }
  }

  /// Move HEAD forward to the very end of the main child path
  static void _stepForwardAll() {
    while (true) {
      final PgnNode<ExtMove>? node = GameController().gameRecorder.activeNode;
      if (node == null) {
        final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
        if (root.children.isNotEmpty) {
          GameController().gameRecorder.activeNode = root.children.first;
        } else {
          break;
        }
      } else if (node.children.isNotEmpty) {
        GameController().gameRecorder.activeNode = node.children.first;
      } else {
        break;
      }
    }
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
