// ignore_for_file: use_build_context_synchronously

/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

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
    HistoryMove move, {
    bool pop = true,
    int? number,
  }) async {
    assert(move != HistoryMove.backN || number != null);

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
      await gotoHistory(move, number);
    } on _HistoryRangeException {
      ScaffoldMessenger.of(context).showSnackBarClear(S.of(context).atEnd);
      logger.i(_HistoryRangeException);
    } on _HistoryRuleException {
      ScaffoldMessenger.of(context)
          .showSnackBarClear(S.of(context).movesAndRulesNotMatch);
      logger.i(_HistoryRuleException);

      MillController().reset();
    }

    _isGoingToHistory = false;

    final String text;
    final lastEffectiveMove = controller.recorder.current;
    if (lastEffectiveMove != null) {
      text = S.of(context).lastMove(lastEffectiveMove.notation);
    } else {
      text = S.of(context).atEnd;
    }

    MillController().tip.showTip(text, snackBar: true);
  }

  static Future<void> takeBack(BuildContext context, {bool pop = true}) async =>
      _gotoHistory(
        context,
        HistoryMove.backOne,
        pop: pop,
      );

  static Future<void> stepForward(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryMove.forward,
        pop: pop,
      );

  static Future<void> takeBackAll(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryMove.backAll,
        pop: pop,
      );

  static Future<void> stepForwardAll(
    BuildContext context, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryMove.forwardAll,
        pop: pop,
      );

  static Future<void> takeBackN(
    BuildContext context,
    int n, {
    bool pop = true,
  }) async =>
      _gotoHistory(
        context,
        HistoryMove.backN,
        number: n,
        pop: pop,
      );

  /// Moves through the History by replaying all relevant moves.
  ///
  /// throws an [_HistoryResponseException] when the moves and rules don't match
  /// or when the end of the list moves has been reached.
  static Future<void> gotoHistory(HistoryMove move, [int? index]) async {
    move.gotoHistory(index);

    Audios().mute();

    // Backup context
    final gameModeBackup = MillController().gameInstance.gameMode;
    MillController().gameInstance.gameMode = GameMode.humanVsHuman;
    final historyBack = MillController().recorder;
    MillController().reset();

    historyBack.forEachVisible((move) async {
      if (!(await MillController().gameInstance._doMove(move))) {
        throw const _HistoryRuleException();
      }
    });

    // Restore context
    MillController().gameInstance.gameMode = gameModeBackup;
    MillController().recorder = historyBack;

    Audios().unMute();
    await move.gotoHistoryPlaySound();
  }
}

enum HistoryMove { forwardAll, backAll, forward, backN, backOne }

extension HistoryMoveExtension on HistoryMove {
  /// Moves the [_GameRecorder] to the specified position.
  ///
  /// Throws [_HistoryResponseException] when trying to access a value outside of the bounds.
  void gotoHistory([int? amount]) {
    final current = MillController().recorder.index;
    final iterator = MillController().recorder.globalIterator;

    switch (this) {
      case HistoryMove.forwardAll:
        iterator.moveToLast();
        break;
      case HistoryMove.backAll:
        iterator.moveToFirst();
        break;
      case HistoryMove.forward:
        if (!iterator.moveNext()) {
          throw const _HistoryRangeException();
        }
        break;
      case HistoryMove.backN:
        final _index = current - amount!;
        assert(_index >= 0);
        iterator.moveTo(_index);
        break;
      case HistoryMove.backOne:
        if (!iterator.movePrevious()) {
          throw const _HistoryRangeException();
        }
    }
  }

  Future<void> gotoHistoryPlaySound() async {
    if (!DB().preferences.keepMuteWhenTakingBack) {
      switch (this) {
        case HistoryMove.forwardAll:
        case HistoryMove.forward:
          return Audios().playTone(Sound.place);
        case HistoryMove.backAll:
        case HistoryMove.backN:
        case HistoryMove.backOne:
          return Audios().playTone(Sound.remove);
      }
    }
  }
}

abstract class _HistoryResponseException implements Exception {
  static const tag = "[_HistoryResponse]";

  const _HistoryResponseException();
}

class _HistoryRuleException extends _HistoryResponseException {
  const _HistoryRuleException();

  @override
  String toString() {
    return "${_HistoryResponseException.tag} cur is equal to moveIndex.";
  }
}

class _HistoryRangeException extends _HistoryResponseException {
  const _HistoryRangeException();

  @override
  String toString() {
    return "${_HistoryResponseException.tag} cur is equal to moveIndex.";
  }
}
