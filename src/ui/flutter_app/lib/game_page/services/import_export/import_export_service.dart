// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_export_service.dart

// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

/// A tree structure representing a variation (sequence of moves).
/// It can contain nested sub-variations and comments.
class Variation {
  /// List of moves (each move can have comments and nested variations).
  final List<MoveNode> moves = <MoveNode>[];

  /// Returns a nicely formatted string with indentations and line breaks,
  /// including comments { ... } and branches ( ... ).
  String toPrettyString({int depth = 0}) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < moves.length; i++) {
      final MoveNode node = moves[i];
      // Print move number + move text (if present).
      // node.moveNumberText might be something like "1.", "1...", etc.
      if (node.moveNumberText != null && node.moveNumberText!.isNotEmpty) {
        sb.write('\n${'  ' * depth}${node.moveNumberText!} ');
      }

      if (node.moveText != null && node.moveText!.isNotEmpty) {
        sb.write('${node.moveText!} ');
      }

      // If the node has a comment, print it in curly braces
      if (node.comment != null && node.comment!.isNotEmpty) {
        sb.write('{${node.comment!}} ');
      }

      // If the node has any sub-variations, print them in parentheses,
      // with an increased indentation.
      for (final Variation subVar in node.subVariations) {
        sb.write('(');
        sb.write(subVar.toPrettyString(depth: depth + 1).trim());
        sb.write(') ');
      }
    }

    return sb.toString();
  }
}

/// Represents one move in a variation, possibly with a preceding move number,
/// a comment, and nested sub-variations.
class MoveNode {
  MoveNode({
    this.moveNumberText,
    this.moveText,
    this.comment,
    List<Variation>? subVariations,
  }) : subVariations = subVariations ?? <Variation>[];

  /// e.g. "1." or "1..." or "10." or null if it is a continuation.
  final String? moveNumberText;

  /// The actual move text, e.g. "d6", "d5-c5", "d5xd7", "f4", ...
  /// This may include special notations like "?" or "!" if the user typed them.
  final String? moveText;

  /// A single comment string for this move. (Extended usage could store multiple
  /// comment blocks in a list if needed.)
  final String? comment;

  /// Any nested sub-variations that branch off from this move.
  final List<Variation> subVariations;
}

// TODO: [Leptopoda] Clean up the file
class ImportService {
  const ImportService._();

  static const String _logTag = "[Importer]";

  /// Exports the game to the device's clipboard.
  static Future<void> exportGame(BuildContext context) async {
    final GameRecorder gameRec = GameController().gameRecorder;
    String exportText;
    if (gameRec.parsedRootVariation != null) {
      // Export the pretty string with branches and comments
      exportText = gameRec.parsedRootVariation!.toPrettyString().trim();
    } else {
      // Fallback to old logic
      exportText = gameRec.moveHistoryText;
    }

    await Clipboard.setData(ClipboardData(text: exportText));
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
      import(data!.text!); // parse the annotated movelist (with variations)
    } catch (exception) {
      final String tip = S.of(context).cannotImport(data!.text!);
      GameController().headerTipNotifier.showTip(tip);
      //GameController().animationController.forward();
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

  /// Main import entry with support for annotations and branches.
  /// It parses the entire text (including parentheses for variations and curly braces for comments).
  /// Then sets the main line moves into GameRecorder (for real gameplay),
  /// and also keeps the Variation tree in `gameRecorder.parsedRootVariation` for re-export or display.
  static void import(String moveList) {
    moveList = moveList.trim();
    logger.t("Clipboard text: $moveList");

    // 1) parse full annotated text into a Variation tree
    final Variation rootVar = _parseAnnotatedMoveList(moveList);

    // 2) find the main line from rootVar (top-level only),
    //    convert them to internal ExtMove, ignoring sub-variations.
    final GameRecorder newHistory = GameRecorder();
    for (final MoveNode moveNode in rootVar.moves) {
      if (moveNode.moveText != null && moveNode.moveText!.isNotEmpty) {
        // Convert move text to internal extMove with your existing logic
        // e.g. using _wmdNotationToMoveString or _playOkNotationToMoveString, etc.
        final String normalized = _tryNormalizeMoveText(moveNode.moveText!);
        newHistory.add(ExtMove(normalized));
      }
      // sub-variations are intentionally ignored here
    }

    // 3) Save the newly created recorder to GameController
    GameController().newGameRecorder = newHistory;
    // 4) Keep the Variation tree for future export or display
    GameController().gameRecorder.parsedRootVariation = rootVar;
  }

  /// Attempt to convert a raw move string to the standardized internal move string.
  /// For demonstration, only calls `_wmdNotationToMoveString` as an example.
  static String _tryNormalizeMoveText(String rawMove) {
    final String move =
        rawMove.toLowerCase().replaceAll(',', '').replaceAll(';', '');
    // This example tries the existing _wmdNotationToMoveString logic.
    // Or you might want to detect if it's playOk notation etc.
    try {
      return _wmdNotationToMoveString(move);
    } catch (e) {
      // fallback or rethrow
      logger.w("$_logTag Could not parse move: $move");
      throw ImportFormatException(move);
    }
  }

  /// A simple parser that can handle parentheses for branches, curly braces for comments.
  /// Returns the top-level Variation containing all the moves.
  static Variation _parseAnnotatedMoveList(String text) {
    final _Parser parser = _Parser(text);
    return parser.parseVariation(); // top-level parse
  }

  /// Convert WMD notation (like "d6", "x13", "d2-b4" etc.) to internal notation.
  /// This is your existing logic from the code snippet, truncated for brevity.
  static String _wmdNotationToMoveString(String wmd) {
    if (wmd.isEmpty) {
      throw ImportFormatException(wmd);
    }
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
            "********/********/******** w p p 9 0 9 0 0 0 0 0 0 0 0 0".length &&
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

    if (noTag == "" ||
        noTag.contains("A") ||
        noTag.contains("B") ||
        noTag.contains("C") ||
        noTag.contains("D") ||
        noTag.contains("E") ||
        noTag.contains("F") ||
        noTag.contains("G")) {
      return false;
    }

    return true;
  }

  static bool _isGoldTokenMoveList(String text) {
    // Example: https://www.goldtoken.com/games/play?g=13097650;print=yes

    return text.contains("GoldToken") ||
        text.contains("Past Moves") ||
        text.contains("Go to") ||
        text.contains("Turn") ||
        text.contains("(Player ");
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
      case PieceColor.marked:
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
    // If the string does not start with '[', return it as is
    if (pgn.startsWith("[") == false) {
      return pgn;
    }

    // Find the position of the last ']'
    final int lastBracketPos = pgn.lastIndexOf("]");
    if (lastBracketPos == -1) {
      return pgn; // Return as is if there is no ']'
    }

    // Get the substring after the last ']'
    String ret = pgn.substring(lastBracketPos + 1);

    // Find the first position that is not a space or newline after the last ']'
    int begin = 0;
    while (begin < ret.length &&
        (ret[begin] == ' ' || ret[begin] == '\r' || ret[begin] == '\n')) {
      begin++;
    }

    // If no valid position is found, return an empty string
    if (begin == ret.length) {
      return "";
    }

    // Get the substring from the first non-space and non-newline character
    ret = ret.substring(begin);

    return ret;
  }

  static void importLegacy(String moveList) {
    moveList = moveList.replaceAll(RegExp(r'^\s*[\r\n]+'), '');
    String ml = moveList;
    final String? fen = GameController().position.fen;
    String? setupFen;

    logger.t("Clipboard text: $moveList");

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

      // Remove "Quick Jump" and any text after it to ensure successful import
      final int quickJumpIndex = ml.indexOf("Quick Jump");
      if (quickJumpIndex != -1) {
        ml = ml.substring(0, quickJumpIndex).trim();
      }
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
        .replaceAll("  take ", " x")
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

/// A helper parser class to parse a string with brackets () and braces {}.
class _Parser {
  _Parser(this.text);

  final String text;
  int _index = 0;

  Variation parseVariation() {
    final Variation variation = Variation();
    while (!isEOF) {
      final String token = _peekToken();
      if (token.isEmpty) {
        break;
      }

      // Handle sub-variation start: '('
      if (token == '(') {
        _consumeToken();
        final Variation subVar = parseVariation();
        variation.moves.add(
          MoveNode(subVariations: <Variation>[subVar]),
        );
        continue;
      }

      // End of a sub-variation: ')'
      if (token == ')') {
        _consumeToken();
        break;
      }

      // A possible curly-brace comment
      if (token == '{') {
        _consumeToken();
        final String commentText = _readUntil('}');
        // We attach the comment to the last move if possible,
        // or create a new move node if none exist yet.
        if (variation.moves.isNotEmpty) {
          final MoveNode last = variation.moves.last;
          final MoveNode newLast = MoveNode(
            moveNumberText: last.moveNumberText,
            moveText: last.moveText,
            comment: commentText.trim(),
            subVariations: last.subVariations,
          );
          variation.moves.removeLast();
          variation.moves.add(newLast);
        } else {
          // If there's no move yet, create a dummy move
          variation.moves.add(MoveNode(comment: commentText.trim()));
        }
        continue;
      }

      // Move number text (something like "1.", "1...", etc.)
      if (_isMoveNumber(token)) {
        // e.g. "1." or "10." or "1..."
        _consumeToken();
        // next token might be the actual move
        final String? nextTk = !_isSymbolAhead() ? _peekToken() : null;
        if (nextTk != null && nextTk.isNotEmpty) {
          // We'll store the move number text in a separate field
          final MoveNode node = MoveNode(moveNumberText: token);
          // but we won't consume the next token here, let the loop handle it as move text
          variation.moves.add(node);
        } else {
          // just a move number with no move text?
          variation.moves.add(MoveNode(moveNumberText: token));
        }
        continue;
      }

      // If we get here, we treat the token as move text
      _consumeToken();
      variation.moves.add(MoveNode(moveText: token));
    }
    return variation;
  }

  bool get isEOF => _index >= text.length;

  /// Peek next token without consuming
  String _peekToken() {
    _skipSpaces();
    if (isEOF) {
      return "";
    }
    final String char = text[_index];
    // Single-character tokens
    if (char == '(' || char == ')' || char == '{' || char == '}') {
      return char;
    }
    // Possible move number like "1." or "12..." or "1...?"
    // Or a normal token until next space, bracket, etc.
    final int start = _index;
    while (!isEOF) {
      final String c = text[_index];
      if (c == '(' ||
          c == ')' ||
          c == '{' ||
          c == '}' ||
          c == ' ' ||
          c == '\n' ||
          c == '\r' ||
          c == '\t') {
        break;
      }
      _index++;
    }
    final String tok = text.substring(start, _index);
    // roll back the _index for further handle in _consumeToken
    return tok;
  }

  /// Actually consume the token returned by _peekToken
  void _consumeToken() {
    // just skip the token length
    _skipSpaces();
    if (isEOF) {
      return;
    }
    final String char = text[_index];
    if (char == '(' || char == ')' || char == '{' || char == '}') {
      // single char token
      _index++;
    } else {
      // or skip until we see space/bracket
      while (!isEOF) {
        final String c = text[_index];
        if (c == '(' ||
            c == ')' ||
            c == '{' ||
            c == '}' ||
            c == ' ' ||
            c == '\n' ||
            c == '\r' ||
            c == '\t') {
          break;
        }
        _index++;
      }
    }
    _skipSpaces();
  }

  /// Read until a specific char is found, ignoring nested for now.
  String _readUntil(String endChar) {
    final StringBuffer sb = StringBuffer();
    while (!isEOF) {
      final String c = text[_index];
      if (c == endChar) {
        // consume endChar
        _index++;
        break;
      }
      sb.write(c);
      _index++;
    }
    return sb.toString();
  }

  void _skipSpaces() {
    while (!isEOF &&
        (text[_index] == ' ' ||
            text[_index] == '\n' ||
            text[_index] == '\r' ||
            text[_index] == '\t')) {
      _index++;
    }
  }

  bool _isMoveNumber(String token) {
    // very naive check: if token ends with '.' or '...' etc, treat it as move number.
    // e.g. "1.", "1...", "10."
    return RegExp(r'^\d+\.*\.*$').hasMatch(token);
  }

  bool _isSymbolAhead() {
    _skipSpaces();
    if (isEOF) {
      return false;
    }
    final String c = text[_index];
    return c == '(' || c == ')' || c == '{' || c == '}';
  }
}
