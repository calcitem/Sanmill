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

    if (GameController().isEngineInDelay == true) {
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

    GameController().headerTipNotifier.showTip(S
        .of(context)
        .atEnd); // TODO: Move to the end of this function. Or change to S.of(context).waiting?

    GameController().headerIconsNotifier.showIcons(); // TODO: See above.
    GameController().boardSemanticsNotifier.updateSemantics();

    if (_isGoingToHistory) {
      logger.i(
        "$_logTag Is going to history, ignore Take Back button press.",
      );

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

    final HistoryResponse resp =
        await doEachMove(navMode, number); // doMove() to index

    GameController().animationManager.allowAnimations = true;

    if (!context.mounted) {
      return const HistoryAbort();
    }

    switch (resp) {
      case HistoryOK():
        final ExtMove? lastEffectiveMove = controller.gameRecorder.current;
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
  /// Return an [HistoryResponse] when the moves and rules don't match
  /// or when the end of the list moves has been reached.
  @visibleForTesting
  static Future<HistoryResponse> doEachMove(HistoryNavMode navMode,
      [int? number]) async {
    bool ret = true;

    // 1) Move the recorder index to the correct spot
    final HistoryResponse resp = navMode.gotoHistory(number);
    if (resp != const HistoryOK()) {
      return resp;
    }

    // 2) Temporarily set the game mode to humanVsHuman
    final GameMode backupMode = GameController().gameInstance.gameMode;
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

    if (GameController().newGameRecorder == null) {
      GameController().newGameRecorder = GameController().gameRecorder;
    }

    // 3) Reset board, replay moves up to the new index
    GameController().reset();
    posKeyHistory.clear();

    final GameRecorder tempRec = GameController().newGameRecorder!;

    // Reapply all visible moves using the PGN tree interface instead of legacy index-based access.
    // Instead of iterating over 0..recorder.index, iterate over the mainlineMoves list.
    final int? visibleIndex = tempRec.index;
    if (visibleIndex != null) {
      // Take the visible moves up to the current index.
      final Iterable<ExtMove> visibleMoves =
          tempRec.mainlineMoves.take(visibleIndex + 1);

      for (final ExtMove extMove in visibleMoves) {
        if (!GameController().gameInstance.doMove(extMove)) {
          tempRec.prune();
          importFailedStr = extMove.notation;
          ret = false;
          break;
        }
      }
    }

    // 4) Restore context
    GameController().gameInstance.gameMode = backupMode;

    final String? lastPositionWithRemove =
        GameController().gameRecorder.lastPositionWithRemove;
    GameController().gameRecorder = tempRec; // adopt the updated recorder
    GameController().gameRecorder.lastPositionWithRemove =
        lastPositionWithRemove;
    GameController().newGameRecorder = null;

    return ret ? const HistoryOK() : const HistoryRule();
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
  /// Moves the [GameRecorder] to the specified position.
  ///
  /// Throws [HistoryResponse] When trying to access a value outside of the bounds.
  HistoryResponse gotoHistory([int? number]) {
    final int? cur = GameController().gameRecorder.index;
    final PointedListIterator<ExtMove> it =
        GameController().gameRecorder.globalIterator;

    switch (this) {
      case HistoryNavMode.stepForwardAll:
        it.moveToLast();
        break;
      case HistoryNavMode.takeBackAll:
        it.moveToHead();
        break;
      case HistoryNavMode.stepForward:
        if (!it.moveNext()) {
          return const HistoryRange();
        }
        break;
      case HistoryNavMode.takeBackN:
        assert(number != null && cur != null);
        if (it.index == 0) {
          it.moveToHead();
        } else {
          final int index = cur! - number!;
          assert(index >= 0);
          it.moveTo(index);
        }
        break;
      case HistoryNavMode.takeBack:
        if (!it.movePrevious()) {
          return const HistoryRange();
        }
    }

    return const HistoryOK();
  }

  Future<void> gotoHistoryPlaySound() async {
    if (DB().generalSettings.keepMuteWhenTakingBack) {
      return;
    }

    // Multiplexing sound resources to save space.
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
