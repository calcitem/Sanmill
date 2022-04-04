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
/// Helper class to use [Position.gotoHistory] in different scenarios.
/// This class will also try to handle any errors and visualize the results.
class HistoryNavigator {
  const HistoryNavigator._();

  static const _tag = "[HistoryNavigator]";

  static bool _isGoingToHistory = false;

  static Future<void> _gotoHistory(
    BuildContext context,
    HistoryNavMode navMode, {
    bool pop = true,
    int? number,
  }) async {
    assert(navMode != HistoryNavMode.takeBackN || number != null);

    if (pop) Navigator.pop(context);

    final controller = MillController();

    MillController().tip.showTip(S.of(context).waiting);

    if (_isGoingToHistory) {
      return logger.i(
        "$_tag Is going to history, ignore Take Back button press.",
      );
    }

    _isGoingToHistory = true;

    try {
      Audios().mute();

      await gotoHistory(navMode, number);

      final lastEffectiveMove = controller.recorder.current;
      if (lastEffectiveMove != null) {
        MillController().tip.showTip(
              S.of(context).lastMove(lastEffectiveMove.notation),
              snackBar: true,
            );
      }

      Audios().unMute();
      await navMode.gotoHistoryPlaySound();
    } on _HistoryRange {
      ScaffoldMessenger.of(context).showSnackBarClear(S.of(context).atEnd);
      logger.i(_HistoryRange);
    } on _HistoryRule {
      MillController().reset();
      ScaffoldMessenger.of(context)
          .showSnackBarClear(S.of(context).movesAndRulesNotMatch);
      logger.i(_HistoryRule);
    } finally {
      Audios().unMute();
    }

    _isGoingToHistory = false;
  }

  static Future<void> takeBack(BuildContext context, {bool pop = true}) async =>
      _gotoHistory(
        context,
        HistoryNavMode.takeBack,
        pop: pop,
      );

  static Future<void> stepForward(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryNavMode.stepForward,
        pop: pop,
      );

  static Future<void> takeBackAll(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryNavMode.takeBackAll,
        pop: pop,
      );

  static Future<void> stepForwardAll(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryNavMode.stepForwardAll,
        pop: pop,
      );

  static Future<void> takeBackN(
    BuildContext context,
    int n, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryNavMode.takeBackN,
        number: n,
        pop: pop,
      );

  /// Moves through the History by replaying all relevant moves.
  ///
  /// Throws an [_HistoryResponse] when the moves and rules don't match
  /// or when the end of the list moves has been reached.
  @visibleForTesting
  static Future<void> gotoHistory(HistoryNavMode navMode, [int? index]) async {
    navMode.gotoHistory(index);

    // Backup context
    final gameModeBackup = MillController().gameInstance.gameMode;
    MillController().gameInstance.gameMode = GameMode.humanVsHuman;
    final recorderBackup = MillController().recorder;
    MillController().reset();

    recorderBackup.forEachVisible((move) async {
      if (!(await MillController().gameInstance.doMove(move))) {
        throw const _HistoryRule();
      }
    });

    // Restore context
    MillController().gameInstance.gameMode = gameModeBackup;
    MillController().recorder = recorderBackup;
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
  /// Moves the [_GameRecorder] to the specified position.
  ///
  /// Throws [_HistoryResponse] When trying to access a value outside of the bounds.
  void gotoHistory([int? amount]) {
    final current = MillController().recorder.index;
    final iterator = MillController().recorder.globalIterator;

    switch (this) {
      case HistoryNavMode.stepForwardAll:
        iterator.moveToLast();
        break;
      case HistoryNavMode.takeBackAll:
        // TODO: [Leptopoda] Because of the way the PointedListIterator is implemented we can only move back until the first piece.
        // We'll have to evaluate if this is enough as we actually don't need more. Like If you want to move back even further just start a new game.
        iterator.moveToFirst();
        break;
      case HistoryNavMode.stepForward:
        if (!iterator.moveNext()) {
          throw const _HistoryRange();
        }
        break;
      case HistoryNavMode.takeBackN:
        assert(amount != null && current != null);
        final _index = current! - amount!;
        assert(_index >= 0);
        iterator.moveTo(_index);
        break;
      case HistoryNavMode.takeBack:
        if (!iterator.movePrevious()) {
          throw const _HistoryRange();
        }
    }
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
