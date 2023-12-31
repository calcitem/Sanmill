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

// TODO: [Leptopoda] Clean up the file
@visibleForTesting
class ImportService {
  const ImportService._();

  static const String _logTag = "[Importer]";

  /// Exports the game to the devices clipboard.
  static Future<void> exportGame(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: GameController().gameRecorder.moveHistoryText),
    );

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).moveHistoryCopied);

    Navigator.pop(context);
  }

  /// Tries to import the game saved in the device's clipboard.
  static Future<void> importGame(BuildContext context) async {
    rootScaffoldMessengerKey.currentState!.clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data?.text == null) {
      Navigator.pop(context);
      return;
    }

    try {
      import(data!.text!); // MillController().newRecorder = newHistory;
    } catch (exception) {
      final String tip = S.of(context).cannotImport(data!.text!);
      GameController().headerTipNotifier.showTip(tip);
      //MillController().animationController.forward();
      Navigator.pop(context);
      return;
    }

    await HistoryNavigator.takeBackAll(context, pop: false);

    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      GameController().headerTipNotifier.showTip(S.of(context).gameImported);
    } else {
      final String tip =
          S.of(context).cannotImport(HistoryNavigator.importFailedStr);
      GameController().headerTipNotifier.showTip(tip);
      HistoryNavigator.importFailedStr = "";
    }

    Navigator.pop(context);
  }

  static String _wmdNotationToMoveString(String wmd) {
    if (wmd.length == 3 && wmd[0] == "x") {
      if (wmdNotationToMove[wmd.substring(1, 3)] != null) {
        return "-${wmdNotationToMove[wmd.substring(1, 3)]!}";
      }
    } else if (wmd.length == 2) {
      if (wmdNotationToMove[wmd] != null) {
        return wmdNotationToMove[wmd]!;
      }
    } else if (wmd.length == 5 && wmd[2] == "-") {
      if (wmdNotationToMove[wmd.substring(0, 2)] != null &&
          wmdNotationToMove[wmd.substring(3, 5)] != null) {
        return "${wmdNotationToMove[wmd.substring(0, 2)]!}->${wmdNotationToMove[wmd.substring(3, 5)]!}";
      }
    } else if ((wmd.length == 8 && wmd[2] == "-" && wmd[5] == "x") ||
        (wmd.length == 5 && wmd[2] == "x")) {
      logger.w("$_logTag Not support parsing format oo-ooxo notation.");
      throw ImportFormatException(wmd);
    }
    throw ImportFormatException(wmd);
  }

  static String _playOkNotationToMoveString(String playOk) {
    if (playOk.isEmpty) {
      throw ImportFormatException(playOk);
    }

    final int iDash = playOk.indexOf("-");
    final int iX = playOk.indexOf("x");

    if (iDash == -1 && iX == -1) {
      // 12
      final int val = int.parse(playOk);
      if (val >= 1 && val <= 24) {
        return playOkNotationToMove[playOk]!;
      } else {
        throw ImportFormatException(playOk);
      }
    }

    if (iX == 0) {
      // x12
      final String sub = playOk.substring(1);
      final int val = int.parse(sub);
      if (val >= 1 && val <= 24) {
        return "-${playOkNotationToMove[sub]!}";
      } else {
        throw ImportFormatException(playOk);
      }
    }
    if (iDash != -1 && iX == -1) {
      String? move;
      // 12-13
      final String sub1 = playOk.substring(0, iDash);
      final int val1 = int.parse(sub1);
      if (val1 >= 1 && val1 <= 24) {
        move = playOkNotationToMove[sub1];
      } else {
        throw ImportFormatException(playOk);
      }

      final String sub2 = playOk.substring(iDash + 1);
      final int val2 = int.parse(sub2);
      if (val2 >= 1 && val2 <= 24) {
        return "$move->${playOkNotationToMove[sub2]!}";
      } else {
        throw ImportFormatException(playOk);
      }
    }

    logger.w("$_logTag Not support parsing format oo-ooxo PlayOK notation.");
    throw ImportFormatException(playOk);
  }

  static bool _isPureFen(String text) {
    if (text.length >=
            "********/********/******** w p p 9 0 9 0 0 0 0".length &&
        (text.contains("/") &&
            text[8] == "/" &&
            text[17] == "/" &&
            text[26] == " ")) {
      return true;
    }

    return false;
  }

  static bool _isPgnMoveList(String text) {
    if (text.length >= 15 &&
        (text.contains("[Event") ||
            text.contains("[White") ||
            text.contains("[FEN"))) {
      return true;
    }

    return false;
  }

  static bool _isFenMoveList(String text) {
    if (text.length >= 15 && (text.contains("[FEN"))) {
      return true;
    }

    return false;
  }

  static bool _isPlayOkMoveList(String text) {
    // See https://www.playok.com/en/mill/#t/f

    if (text.contains("PlayOK")) {
      return true;
    }

    final String noTag = removeTagPairs(text);

    if (noTag.contains("1.") == false) {
      return false;
    }

    if (noTag == "" ||
        noTag.contains("a") ||
        noTag.contains("b") ||
        noTag.contains("c") ||
        noTag.contains("d") ||
        noTag.contains("e") ||
        noTag.contains("f") ||
        noTag.contains("g")) {
      return false;
    }

    return true;
  }

  static bool _isGoldTokenMoveList(String text) {
    // Example: https://www.goldtoken.com/games/play?g=13097650;print=yes

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

  static String addTagPairs(String moveList) {
    final DateTime dateTime = DateTime.now();
    final String date = "${dateTime.year}.${dateTime.month}.${dateTime.day}";

    final int total = Position.score[PieceColor.white]! +
        Position.score[PieceColor.black]! +
        Position.score[PieceColor.draw]!;

    final Game gameInstance = GameController().gameInstance;
    final Player whitePlayer = gameInstance.getPlayerByColor(PieceColor.white);
    final Player blackPlayer = gameInstance.getPlayerByColor(PieceColor.black);

    String white;
    String black;
    String result;

    if (whitePlayer.isAi) {
      white = "AI";
    } else {
      white = "Human";
    }

    if (blackPlayer.isAi) {
      black = "AI";
    } else {
      black = "Human";
    }

    switch (GameController().position.winner) {
      case PieceColor.white:
        result = "1-0";
        break;
      case PieceColor.black:
        result = "0-1";
        break;
      case PieceColor.draw:
        result = "1/2-1/2";
        break;
      case PieceColor.ban:
      case PieceColor.none:
      case PieceColor.nobody:
        result = "*";
        break;
    }

    String tagPairs = '[Event "Sanmill-Game"]\r\n'
        '[Site "Sanmill"]\r\n'
        '[Date "$date"]\r\n'
        '[Round "$total"]\r\n'
        '[White "$white"]\r\n'
        '[Black "$black"]\r\n'
        '[Result "$result"]\r\n';

    if (!(moveList.length > 3 && moveList.startsWith("[FEN"))) {
      tagPairs = "$tagPairs\r\n";
    }

    return tagPairs + moveList;
  }

  static String getTagPairs(String pgn) {
    return pgn.substring(0, pgn.lastIndexOf("]") + 1);
  }

  static String removeTagPairs(String pgn) {
    if (pgn.startsWith("[") == false) {
      return pgn;
    }

    String ret = pgn.substring(pgn.lastIndexOf("]"));
    final int begin = ret.indexOf("1.");
    if (begin == -1) {
      return "";
    }
    ret = ret.substring(begin);

    return ret;
  }

  @visibleForTesting
  static void import(String moveList) {
    String ml = moveList;
    final String fen = GameController().position.fen;
    String? setupFen;

    logger.v("Clipboard text: $moveList");

    if (_isPlayOkMoveList(moveList)) {
      return _importPlayOk(moveList);
    }

    if (_isFenMoveList(moveList)) {
      setupFen = moveList.substring(moveList.indexOf("FEN"));
      setupFen = setupFen.substring(5);
      setupFen = setupFen.substring(0, setupFen.indexOf('"]'));
      GameController().position.setFen(setupFen);
    }

    if (_isPureFen(moveList)) {
      setupFen = moveList;
      GameController().position.setFen(setupFen);
      ml = "";
    }

    if (_isPgnMoveList(moveList)) {
      ml = removeTagPairs(moveList);
    }

    if (_isGoldTokenMoveList(moveList)) {
      int start = moveList.indexOf("1\t");

      if (start == -1) {
        start = moveList.indexOf("1 ");
      }

      if (start == -1) {
        start = 0;
      }

      ml = moveList.substring(start);
    }

    // TODO: Is it will cause what?
    final GameRecorder newHistory = GameRecorder(
        lastPositionWithRemove: setupFen ?? fen, setupPosition: setupFen);
    final List<String> list = ml
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
        .replaceAll("x", " x")
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

    for (String i in list) {
      i = i.trim();

      if (int.tryParse(i) != null) {
        i = "$i.";
      }

      // TODO: [Leptopoda] Deduplicate
      if (i.isNotEmpty && !i.endsWith(".")) {
        final String m = _wmdNotationToMoveString(i);
        newHistory.add(ExtMove(m));
      }
    }

    // TODO: Is this judge necessary?
    if (newHistory.isNotEmpty || setupFen != "") {
      GameController().newGameRecorder = newHistory;
    }

    // TODO: Just a patch. Let status is setupPosition.
    //  The judgment of whether it is in the setupPosition state is based on this, not newRecorder.
    if (setupFen != "") {
      GameController().gameRecorder.setupPosition = setupFen;
    }
  }

  static String removeGameResultAndReplaceLineBreaks(String moveList) {
    final String ret = moveList
        .replaceAll("\n", " ")
        .replaceAll(" 1/2-1/2", "")
        .replaceAll(" 1-0", "")
        .replaceAll(" 0-1", "")
        .replaceAll("TXT", "");
    return ret;
  }

  static String cleanup(String moveList) {
    return removeGameResultAndReplaceLineBreaks(removeTagPairs(moveList));
  }

  static void _importPlayOk(String moveList) {
    final GameRecorder newHistory =
        GameRecorder(lastPositionWithRemove: GameController().position.fen);

    final List<String> list = cleanup(moveList).split(" ");

    for (String i in list) {
      i = i.trim();

      if (i.isNotEmpty &&
          !i.endsWith(".") &&
          !i.startsWith("[") &&
          !i.endsWith("]")) {
        final int iX = i.indexOf("x");
        if (iX == -1) {
          final String m = _playOkNotationToMoveString(i);
          newHistory.add(ExtMove(m));
        } else if (iX != -1) {
          final String m1 = _playOkNotationToMoveString(i.substring(0, iX));
          newHistory.add(ExtMove(m1));

          final String m2 = _playOkNotationToMoveString(i.substring(iX));
          newHistory.add(ExtMove(m2));
        }
      }
    }

    if (newHistory.isNotEmpty) {
      GameController().newGameRecorder = newHistory;
    }
  }
}
