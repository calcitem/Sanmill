// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// ignore_for_file: use_build_context_synchronously

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
    int? number,
  }) async {
    assert(navMode != HistoryNavMode.takeBackN || number != null);

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

    final HistoryResponse resp =
        await doEachMove(navMode, number); // doMove() to index

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
      Navigator.pop(context);
    }

    return resp;
  }

  static Future<HistoryResponse?> takeBack(BuildContext context,
      {bool pop = true}) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBack,
      pop: pop,
    );
  }

  static Future<HistoryResponse?> stepForward(
    BuildContext context, {
    bool pop = true,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.stepForward,
      pop: pop,
    );
  }

  static Future<HistoryResponse?> takeBackAll(
    BuildContext context, {
    bool pop = true,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBackAll,
      pop: pop,
    );
  }

  static Future<HistoryResponse?> stepForwardAll(
    BuildContext context, {
    bool pop = true,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.stepForwardAll,
      pop: pop,
    );
  }

  static Future<HistoryResponse?> takeBackN(
    BuildContext context,
    int n, {
    bool pop = true,
  }) async {
    return _gotoHistory(
      context,
      HistoryNavMode.takeBackN,
      number: n,
      pop: pop,
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

    final HistoryResponse resp =
        navMode.gotoHistory(number); // Only change index

    if (resp != const HistoryOK()) {
      return resp;
    }

    // Backup context
    final GameMode gameModeBackup = GameController().gameInstance.gameMode;
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

    if (GameController().newGameRecorder == null) {
      GameController().newGameRecorder = GameController().gameRecorder;
    }

    GameController().reset();

    GameController().newGameRecorder!.forEachVisible((ExtMove extMove) async {
      if (GameController().gameInstance.doMove(extMove) == false) {
        if (GameController().newGameRecorder != null) {
          GameController().newGameRecorder!.prune();
          importFailedStr = extMove.notation;
          ret = false;
        }
      }
    });

    // Restore context
    GameController().gameInstance.gameMode = gameModeBackup;
    final String? lastPositionWithRemove =
        GameController().gameRecorder.lastPositionWithRemove;
    GameController().gameRecorder = GameController().newGameRecorder!;
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
