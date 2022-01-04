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

// TODO: [Leptopoda] clean up the file
// TODO: [Leptopoda] change error handling
@visibleForTesting
class ImportService {
  static const _tag = "[Importer]";

  const ImportService._();

  /// Exports the game to the devices clipboard
  static Future<void> exportGame(BuildContext context) async {
    Navigator.pop(context);

    await Clipboard.setData(
      ClipboardData(text: MillController().recorder.moveHistoryText),
    );

    ScaffoldMessenger.of(context)
        .showSnackBarClear(S.of(context).moveHistoryCopied);
  }

  /// Tries to import the game saved in the devices clipboard
  static Future<void> importGame(BuildContext context) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data?.text == null) return;

    await HistoryNavigator.gotoHistory(HistoryMove.backAll);
    // TODO: [Leptopoda] use reset game
    MillController().reset();

    final importFailedStr = import(data!.text!);

    if (importFailedStr != null) {
      return MillController().tip.showTip(
            S.of(context).cannotImport(importFailedStr),
            snackBar: true,
          );
    }

    await HistoryNavigator.stepForwardAll(context, pop: false);

    MillController().tip.showTip(S.of(context).gameImported, snackBar: true);
  }

  static String? _wmdNotationToMoveString(String wmd) {
    if (wmd.length == 3 && wmd[0] == "x") {
      if (wmdNotationToMove[wmd.substring(1, 3)] != null) {
        return "-${wmdNotationToMove[wmd.substring(1, 3)]!}";
      }
    } else if (wmd.length == 2) {
      if (wmdNotationToMove[wmd] != null) {
        return wmdNotationToMove[wmd]!;
      }
    } else if (wmd.length == 5 && wmd[2] == "-") {
      if (wmdNotationToMove[(wmd.substring(0, 2))] != null &&
          wmdNotationToMove[(wmd.substring(3, 5))] != null) {
        return "${wmdNotationToMove[(wmd.substring(0, 2))]!}->${wmdNotationToMove[(wmd.substring(3, 5))]!}";
      }
    } else if ((wmd.length == 8 && wmd[2] == "-" && wmd[5] == "x") ||
        (wmd.length == 5 && wmd[2] == "x")) {
      logger.w("$_tag Not support parsing format oo-ooxo notation.");
    } else {
      logger.e("$_tag Parse notation $wmd failed.");
    }
  }

  static String? _playOkNotationToMoveString(String playOk) {
    if (playOk.isEmpty) return null;

    final iDash = playOk.indexOf("-");
    final iX = playOk.indexOf("x");

    if (iDash == -1 && iX == -1) {
      // 12
      final val = int.parse(playOk);
      if (val >= 1 && val <= 24) {
        return playOkNotationToMove[playOk]!;
      } else {
        logger.e("$_tag Parse PlayOK notation $playOk failed.");
        return null;
      }
    }

    if (iX == 0) {
      // x12
      final sub = playOk.substring(1);
      final val = int.parse(sub);
      if (val >= 1 && val <= 24) {
        return "-${playOkNotationToMove[sub]!}";
      } else {
        logger.e("$_tag Parse PlayOK notation $playOk failed.");
        return null;
      }
    }
    if (iDash != -1 && iX == -1) {
      String? move;
      // 12-13
      final sub1 = playOk.substring(0, iDash);
      final val1 = int.parse(sub1);
      if (val1 >= 1 && val1 <= 24) {
        move = playOkNotationToMove[sub1];
      } else {
        logger.e("$_tag Parse PlayOK notation $playOk failed.");
        return null;
      }

      final sub2 = playOk.substring(iDash + 1);
      final val2 = int.parse(sub2);
      if (val2 >= 1 && val2 <= 24) {
        return "$move->${playOkNotationToMove[sub2]!}";
      } else {
        logger.e("$_tag Parse PlayOK notation $playOk failed.");
        return null;
      }
    }

    logger.w("$_tag Not support parsing format oo-ooxo PlayOK notation.");
    return null;
  }

  static bool _isDalmaxMoveList(String text) {
    if (text.length >= 15 && text.substring(0, 14) == '[Event "Dalmax') {
      return true;
    }

    return false;
  }

  static bool _isPlayOkMoveList(String text) {
    if (text.length >= 4 &&
        text.substring(0, 3) == "1. " &&
        int.tryParse(text.substring(3, 4)) != null) {
      return true;
    }

    if (text.isNotEmpty && text[0] == "[") {
      return true;
    }

    return false;
  }

  static bool _isGoldTokenMoveList(String text) {
    if (text.length >= 10 &&
        (text.substring(0, 9) == "GoldToken" ||
            text.substring(0, 10) == "Past Moves" ||
            text.substring(0, 5) == "Go to" ||
            text.substring(0, 4) == "Turn" ||
            text.substring(0, 8) == "(Player ")) {
      return true;
    }

    return false;
  }

  // TODO [Leptopoda] make param a List<Move> and change the return type
  @visibleForTesting
  static String? import(String moveList) {
    // TODO: [Leptopoda] clean up
    logger.v("Clipboard text: $moveList");

    if (_isDalmaxMoveList(moveList)) {
      return _importDalmax(moveList);
    }

    if (_isPlayOkMoveList(moveList)) {
      return _importPlayOk(moveList);
    }

    if (_isGoldTokenMoveList(moveList)) {
      return _importGoldToken(moveList);
    }

    final _GameRecorder newHistory = _GameRecorder();
    final List<String> list = moveList
        .toLowerCase()
        .replaceAll("\n", " ")
        .replaceAll(",", " ")
        .replaceAll(";", " ")
        .replaceAll("!", " ")
        .replaceAll("?", " ")
        .replaceAll("#", " ")
        .replaceAll("()", " ")
        .replaceAll("white", " ")
        .replaceAll("black", " ")
        .replaceAll("win", " ")
        .replaceAll("lose", " ")
        .replaceAll("draw", " ")
        .replaceAll("resign", " ")
        .replaceAll("-/x", "x")
        .replaceAll("/x", "x")
        .replaceAll(".a", ". a")
        .replaceAll(".b", ". b")
        .replaceAll(".c", ". c")
        .replaceAll(".d", ". d")
        .replaceAll(".e", ". e")
        .replaceAll(".f", ". f")
        .replaceAll(".g", ". g")
        // GoldToken
        .replaceAll("\t", " ")
        .replaceAll("place to ", "")
        .replaceAll("  take ", "x")
        .replaceAll(" -> ", "-")
        // Finally
        .split(" ");

    for (var i in list) {
      i = i.trim();

      if (int.tryParse(i) != null) {
        i = "$i.";
      }

      // TODO: [Leptopoda] deduplicate
      if (i.isNotEmpty && !i.endsWith(".")) {
        if (i.length == 5 && i[2] == "x") {
          // "a1xc3"
          final String? m1 = _wmdNotationToMoveString(i.substring(0, 2));
          if (m1 != null) {
            newHistory.add(ExtMove(m1));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
          final String? m2 = _wmdNotationToMoveString(i.substring(2));
          if (m2 != null) {
            newHistory.add(ExtMove(m2));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
        } else if (i.length == 8 && i[2] == "-" && i[5] == "x") {
          // "a1-b2xc3"
          final String? m1 = _wmdNotationToMoveString(i.substring(0, 5));
          if (m1 != null) {
            newHistory.add(ExtMove(m1));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
          final String? m2 = _wmdNotationToMoveString(i.substring(5));
          if (m2 != null) {
            newHistory.add(ExtMove(m2));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
        } else {
          // no x
          final String? m = _wmdNotationToMoveString(i);
          if (m != null) {
            newHistory.add(ExtMove(m));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
        }
      }
    }

    if (newHistory.isNotEmpty) {
      MillController().recorder = newHistory;
    }
  }

  static String? _importDalmax(String moveList) {
    return import(moveList.substring(moveList.indexOf("1. ")));
  }

  static String? _importPlayOk(String moveList) {
    final _GameRecorder newHistory = _GameRecorder();

    final List<String> list = moveList
        .replaceAll("\n", " ")
        .replaceAll(" 1/2-1/2", "")
        .replaceAll(" 1-0", "")
        .replaceAll(" 0-1", "")
        .replaceAll("TXT", "")
        .split(" ");

    for (var i in list) {
      i = i.trim();

      if (i.isNotEmpty &&
          !i.endsWith(".") &&
          !i.startsWith("[") &&
          !i.endsWith("]")) {
        final iX = i.indexOf("x");
        if (iX == -1) {
          final String? m = _playOkNotationToMoveString(i);
          if (m != null) {
            newHistory.add(ExtMove(m));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
        } else if (iX != -1) {
          final String? m1 = _playOkNotationToMoveString(i.substring(0, iX));
          if (m1 != null) {
            newHistory.add(ExtMove(m1));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
          final String? m2 = _playOkNotationToMoveString(i.substring(iX));
          if (m2 != null) {
            newHistory.add(ExtMove(m2));
          } else {
            logger.e("Cannot import $i");
            return i;
          }
        }
      }
    }

    if (newHistory.isNotEmpty) {
      MillController().recorder = newHistory;
    }

    return null;
  }

  static String? _importGoldToken(String moveList) {
    int start = moveList.indexOf("1\t");

    if (start == -1) {
      start = moveList.indexOf("1 ");
    }

    if (start == -1) {
      start = 0;
    }

    return import(moveList.substring(start));
  }
}
