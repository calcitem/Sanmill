// ignore_for_file: use_build_context_synchronously

// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of '../mill.dart';

/// HistoryNavigator
///
/// Helper class to use [HistoryNavigator.doEachMove] in different scenarios.
/// This class will also try to handle any errors and visualize the results.
class HistoryNavigator {
  const HistoryNavigator._();

  static const _tag = "[HistoryNavigator]";

  static bool _isGoingToHistory = false;

  static Future<HistoryResponse?> _gotoHistory(
    BuildContext context,
    HistoryNavMode navMode, {
    bool pop = true,
    int? number,
  }) async {
    assert(navMode != HistoryNavMode.takeBackN || number != null);

    if (pop) Navigator.pop(context);

    final controller = MillController();

    MillController().tip.showTip(S
        .of(context)
        .atEnd); // TODO: Move to the end of this function. Or change to S.of(context).waiting?

    MillController().headIcons.showIcons(); // TODO: See above.

    if (_isGoingToHistory) {
      logger.i(
        "$_tag Is going to history, ignore Take Back button press.",
      );

      return const HistoryOK();
    }

    _isGoingToHistory = true;

    Audios().mute();

    var resp = await doEachMove(navMode, number); // doMove() to index

    switch (resp) {
      case HistoryOK():
        final lastEffectiveMove = controller.recorder.current;
        if (lastEffectiveMove != null) {
          MillController().tip.showTip(
                S.of(context).lastMove(lastEffectiveMove.notation),
                snackBar: true,
              );
          MillController().headIcons.showIcons();
        }
        break;
      case HistoryRange():
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).atEnd);
        logger.i(HistoryRange);
        break;
      case HistoryRule():
      default:
        MillController().reset(); // TODO: Need?
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).movesAndRulesNotMatch);
        logger.i(HistoryRule);
        break;
    }

    Audios().unMute();
    await navMode.gotoHistoryPlaySound();

    _isGoingToHistory = false;

    return const HistoryOK();
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

    var resp = navMode.gotoHistory(number); // Only change index

    if (resp != const HistoryOK()) return resp;

    // Backup context
    final gameModeBackup = MillController().gameInstance.gameMode;
    MillController().gameInstance.gameMode = GameMode.humanVsHuman;
    final recorderBackup = MillController().recorder;

    MillController().reset();

    recorderBackup.forEachVisible((extMove) async {
      if (!(await MillController().gameInstance.doMove(extMove))) {
        ret = false;
        // TODO: break?
      }
    });

    // Restore context
    MillController().gameInstance.gameMode = gameModeBackup;
    MillController().recorder = recorderBackup;

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
    final cur = MillController().recorder.index;
    final it = MillController().recorder.globalIterator;

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
          final index = cur! - number!;
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

    switch (this) {
      case HistoryNavMode.stepForwardAll:
      case HistoryNavMode.stepForward:
        // TODO: Uses this sound temporarily
        return Audios().playTone(Sound.place);
      case HistoryNavMode.takeBackAll:
      case HistoryNavMode.takeBackN:
      case HistoryNavMode.takeBack:
        // TODO: Uses this sound temporarily
        return Audios().playTone(Sound.remove);
    }
  }
}
