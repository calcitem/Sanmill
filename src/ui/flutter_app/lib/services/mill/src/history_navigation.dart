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

class HistoryNavigator {
  HistoryNavigator._();

  static bool _isGoingToHistory = false;

  static Future<void> _gotoHistory(
    BuildContext context,
    HistoryMove move, {
    bool pop = true,
    int? number,
  }) async {
    if (pop) Navigator.pop(context);
    final controller = MillController();

    MillController().tip.showTip(S.of(context).waiting);

    if (_isGoingToHistory) {
      return logger.i(
        "[TakeBack] Is going to history, ignore Take Back button press.",
      );
    }

    _isGoingToHistory = true;

    final response = await controller.position.gotoHistory(move, number);
    if (response != null) {
      ScaffoldMessenger.of(context)
          .showSnackBarClear(response.getString(context));
    }

    _isGoingToHistory = false;

    final String text;
    final lastEffectiveMove = controller.recorder.lastEffectiveMove;
    if (lastEffectiveMove?.notation != null) {
      text = S.of(context).lastMove(lastEffectiveMove!.notation);
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
}
