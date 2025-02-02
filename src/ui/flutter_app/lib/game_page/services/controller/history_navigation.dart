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
      logger.i("$_logTag Is going to history, ignore Take Back button press.");
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

  static void _takeBack(int n) {
    while (n-- > 0) {
      final PgnChildNode<ExtMove>? node =
          GameController().gameRecorder.activeNode;
      if (node == null) {
        break;
      }
      if (node.parent == null) {
        break;
      }
      // Only cast if the parent is a PgnChildNode; if it's the root (PgnNode) then stop.
      if (node.parent is PgnChildNode<ExtMove>) {
        GameController().gameRecorder.activeNode =
            node.parent as PgnChildNode<ExtMove>?;
      } else {
        GameController().gameRecorder.activeNode = null;
        break;
      }
    }
  }

  static void _takeBackAll() {
    while (GameController().gameRecorder.activeNode?.parent != null) {
      final PgnNode<ExtMove>? parent =
          GameController().gameRecorder.activeNode!.parent;
      if (parent is PgnChildNode<ExtMove>) {
        GameController().gameRecorder.activeNode = parent;
      } else {
        GameController().gameRecorder.activeNode = null;
        break;
      }
    }
  }

  static void _stepForward(int n) {
    while (n-- > 0) {
      final PgnChildNode<ExtMove>? node =
          GameController().gameRecorder.activeNode;
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

  static void _stepForwardAll() {
    while (true) {
      final PgnChildNode<ExtMove>? node =
          GameController().gameRecorder.activeNode;
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

  static List<ExtMove> _collectPathMoves(GameRecorder rec) {
    final List<ExtMove> moves = <ExtMove>[];
    PgnChildNode<ExtMove>? cur = rec.activeNode;
    while (cur != null && cur.parent != null) {
      moves.add(cur.data);
      if (cur.parent is PgnChildNode<ExtMove>) {
        cur = cur.parent as PgnChildNode<ExtMove>?;
      } else {
        break;
      }
    }
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
