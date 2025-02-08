// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_service.dart

part of '../mill.dart';

class ImportService {
  const ImportService._();

  static const String _logTag = "[Importer]";

  /// Tries to import the game saved in the device's clipboard.
  static Future<void> importGame(BuildContext context,
      {bool shouldPop = true}) async {
    // Clear snack bars before clipboard read
    rootScaffoldMessengerKey.currentState?.clearSnackBars();

    // Pre-fetch context-dependent data
    final S s = S.of(context);
    final NavigatorState navigator = Navigator.of(context);

    // Read clipboard data (async)
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;

    // Immediately check if context is still valid
    if (!context.mounted) {
      return;
    }

    // If clipboard is empty or missing text, pop and return
    if (text == null) {
      if (shouldPop) {
        navigator.pop();
      }
      return;
    }

    // Perform import logic
    try {
      import(text); // GameController().newRecorder = newHistory;
    } catch (exception) {
      if (!context.mounted) {
        return;
      }
      final String tip = s.cannotImport(text);
      GameController().headerTipNotifier.showTip(tip);
      //GameController().animationController.forward();
      if (shouldPop) {
        navigator.pop();
      }
      return;
    }

    // Check context again before using it in navigation or showing tips
    if (!context.mounted) {
      return;
    }

    // Navigation or UI updates
    await HistoryNavigator.takeBackAll(context, pop: false);

    if (!context.mounted) {
      return;
    }

    final HistoryResponse? historyResult =
        await HistoryNavigator.stepForwardAll(context, pop: false);

    if (historyResult == const HistoryOK()) {
      GameController().headerTipNotifier.showTip(s.gameImported);
    } else {
      final String tip = s.cannotImport(HistoryNavigator.importFailedStr);
      GameController().headerTipNotifier.showTip(tip);
      HistoryNavigator.importFailedStr = "";
    }

    if (shouldPop) {
      navigator.pop();
    }
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

    String variantTag;
    if (DB().ruleSettings.isLikelyNineMensMorris()) {
      variantTag = '[Variant "Nine Men\'s Morris"]\r\n';
    } else if (DB().ruleSettings.isLikelyTwelveMensMorris()) {
      variantTag = '[Variant "Twelve Men\'s Morris"]\r\n';
    } else if (DB().ruleSettings.isLikelyElFilja()) {
      variantTag = '[Variant "El Filja"]\r\n';
    } else {
      variantTag = '';
    }

    final String plyCountTag =
        '[PlyCount "${GameController().gameRecorder.mainlineMoves.length}"]\r\n';

    String tagPairs = '[Event "Sanmill-Game"]\r\n'
        '[Site "Sanmill"]\r\n'
        '[Date "$date"]\r\n'
        '[Round "$total"]\r\n'
        '[White "$white"]\r\n'
        '[Black "$black"]\r\n'
        '[Result "$result"]\r\n'
        '$variantTag'
        '$plyCountTag';

    // Ensure an extra CRLF if moveList does not start with "[FEN"
    if (!(moveList.length > 3 && moveList.startsWith("[FEN"))) {
      tagPairs = "$tagPairs\r\n";
    }

    return tagPairs + moveList;
  }

  static void import(String moveList) {
    moveList = moveList.trim();
    String ml = moveList;

    logger.t("Clipboard text: $moveList");

    // TODO: Improve this logic
    if (isPlayOkMoveList(ml)) {
      return _importPlayOk(ml);
    }

    if (isPureFen(ml)) {
      ml = '[FEN "$ml"]\r\n[SetUp "1"]';
    }

    if (isGoldTokenMoveList(ml)) {
      int start = ml.indexOf("1\t");

      if (start == -1) {
        start = ml.indexOf("1 ");
      }

      if (start == -1) {
        start = 0;
      }

      ml = ml.substring(start);

      // Remove "Quick Jump" and any text after it to ensure successful import
      final int quickJumpIndex = ml.indexOf("Quick Jump");
      if (quickJumpIndex != -1) {
        ml = ml.substring(0, quickJumpIndex).trim();
      }
    }

    final Map<String, String> replacements = <String, String>{
      "\n": " ",
      "()": " ",
      "white": " ",
      "black": " ",
      "win": " ",
      "lose": " ",
      "draw": " ",
      "resign": " ",
      "-/x": "x",
      "/x": "x",
      ".a": ". a",
      ".b": ". b",
      ".c": ". c",
      ".d": ". d",
      ".e": ". e",
      ".f": ". f",
      ".g": ". g",
      // GoldToken
      "\t": " ",
      "Place to ": "",
      ", take ": "x",
      " -> ": "-"
    };

    ml = processOutsideBrackets(ml, replacements);
    _importPgn(ml);
  }

  static void _importPlayOk(String moveList) {
    String cleanUpPlayOkMoveList(String moveList) {
      moveList = removeTagPairs(moveList);
      final String ret = moveList
          .replaceAll("\n", " ")
          .replaceAll(" 1/2-1/2", "")
          .replaceAll(" 1-0", "")
          .replaceAll(" 0-1", "")
          .replaceAll("TXT", "");
      return ret;
    }

    final Position localPos = Position();
    localPos.reset();

    final GameRecorder newHistory =
        GameRecorder(lastPositionWithRemove: GameController().position.fen);

    final List<String> list = cleanUpPlayOkMoveList(moveList).split(" ");

    for (String i in list) {
      i = i.trim();

      if (i.isNotEmpty &&
          !i.endsWith(".") &&
          !i.startsWith("[") &&
          !i.endsWith("]")) {
        final int iX = i.indexOf("x");
        if (iX == -1) {
          final String m = _playOkNotationToMoveString(i);

          newHistory.appendMove(ExtMove(
            m,
            side: localPos.sideToMove,
          ));

          final bool ok = localPos.doMove(m);
          if (!ok) {
            throw ImportFormatException("Invalid move: $m");
          }
        } else if (iX != -1) {
          final String m1 = _playOkNotationToMoveString(i.substring(0, iX));

          newHistory.appendMove(ExtMove(
            m1,
            side: localPos.sideToMove,
          ));

          final bool ok1 = localPos.doMove(m1);
          if (!ok1) {
            throw ImportFormatException("Invalid move: $m1");
          }

          final String m2 = _playOkNotationToMoveString(i.substring(iX));

          newHistory.appendMove(ExtMove(
            m2,
            side: localPos.sideToMove,
          ));

          final bool ok2 = localPos.doMove(m2);
          if (!ok2) {
            throw ImportFormatException("Invalid move: $m2");
          }
        }
      }
    }

    if (newHistory.mainlineMoves.isNotEmpty) {
      GameController().newGameRecorder = newHistory;
    }
  }

  /// Replays all nodes to assign a boardLayout to each node's node.data.
  static void fillAllNodesBoardLayout(PgnNode<ExtMove> root,
      {String? setupFen}) {
    final Position pos = Position();

    // If there is a specific initial FEN, set it first.
    if (setupFen != null && setupFen.isNotEmpty) {
      pos.setFen(setupFen);
    } else {
      // If no custom FEN is provided, use the standard starting FEN
      // or an empty board FEN, depending on rules.
      pos.reset();
    }

    void dfs(PgnNode<ExtMove> node, Position currentPos) {
      // If node.data is not null, it represents a move.
      if (node.data != null) {
        final ExtMove move = node.data!;
        // Execute this move in the current position.
        final bool ok = currentPos.doMove(move.move);
        if (!ok) {
          // If an illegal move is encountered, choose to throw an
          // exception or skip it based on requirements.
          // throw StateError("Unable to replay move: ${move.move}");
          return;
        }
        // After replaying, store the current board layout in node.data.
        move.boardLayout = currentPos.generateBoardLayoutAfterThisMove();
      }

      // Iterate through child nodes.
      for (final PgnNode<ExtMove> child in node.children) {
        // Clone the current position state before recursion.
        final Position saved = currentPos.clone();
        // Recursively process child nodes.
        dfs(child, currentPos);
        // Restore the position after recursion.
        currentPos.copyWith(saved);
      }
    }

    // Start a depth-first traversal from the root.
    dfs(root, pos);
  }

  /// For standard PGN strings containing headers and moves, parse them
  /// with the pgn.dart parser, convert SAN moves to UCI notation, and store.
  static void _importPgn(String moveList) {
    // Parse entire PGN (including headers)
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(moveList);

    final Position localPos = Position();

    // Retrieve FEN from headers if present
    final String? fen = game.headers['FEN'];
    if (fen != null && fen.isNotEmpty) {
      localPos.setFen(fen);
    } else {
      localPos.reset();
    }

    final GameRecorder newHistory = GameRecorder(
      lastPositionWithRemove: fen ?? GameController().position.fen,
      setupPosition: fen,
    );

    // Set up the board position using FEN if available
    if (fen != null && fen.isNotEmpty) {
      GameController().position.setFen(fen);
    }

    /// Helper function to split a SAN move into segments
    List<String> splitSan(String san) {
      List<String> segments = <String>[];

      if (san.contains('x')) {
        if (san.startsWith('x')) {
          // All segments start with 'x'
          final RegExp regex = RegExp(r'(x[a-g][1-7])');
          segments = regex
              .allMatches(san)
              .map((RegExpMatch m) => m.group(0)!)
              .toList();
        } else {
          final int firstX = san.indexOf('x');
          if (firstX > 0) {
            // First segment is before the first 'x'
            final String firstSegment = san.substring(0, firstX);
            segments.add(firstSegment);
            // Remaining part: extract all 'x' followed by two characters
            final RegExp regex = RegExp(r'(x[a-g][1-7])');
            final String remainingSan = san.substring(firstX);
            segments.addAll(regex
                .allMatches(remainingSan)
                .map((RegExpMatch m) => m.group(0)!)
                .toList());
          } else {
            // 'x' exists but at position 0
            final RegExp regex = RegExp(r'(x[a-g][1-7])');
            segments = regex
                .allMatches(san)
                .map((RegExpMatch m) => m.group(0)!)
                .toList();
          }
        }
      } else {
        // No 'x', process as single segment
        segments.add(san);
      }

      return segments;
    }

    // Convert each SAN move to internal move string and add to newHistory
    for (final PgnNodeData node in game.moves.mainline()) {
      final String san = node.san.trim().toLowerCase();
      if (san.isEmpty ||
          san == "*" ||
          san == "x" ||
          san == "xx" ||
          san == "xxx" ||
          san == "p") {
        // Skip pass moves or asterisks
        continue;
      }

      final List<String> segments = splitSan(san);

      for (final String segment in segments) {
        if (segment.isEmpty) {
          continue;
        }
        try {
          final String uciMove = _wmdNotationToMoveString(segment);
          // Create ExtMove with parsed NAGs and comments from node
          newHistory.appendMove(ExtMove(
            uciMove,
            side: localPos.sideToMove,
            nags: node.nags,
            startingComments: node.startingComments,
            comments: node.comments,
          ));

          final bool ok = localPos.doMove(uciMove);
          if (!ok) {
            throw ImportFormatException("Invalid move: $uciMove");
          }
        } catch (e) {
          logger.e("$_logTag Failed to parse move segment '$segment': $e");
          throw ImportFormatException("Invalid move segment: $segment");
        }
      }
    }

    if (newHistory.mainlineMoves.isNotEmpty ||
        (fen != null && fen.isNotEmpty)) {
      fillAllNodesBoardLayout(newHistory.pgnRoot, setupFen: fen);
      GameController().newGameRecorder = newHistory;
    }

    if (fen != null && fen.isNotEmpty) {
      GameController().gameRecorder.setupPosition = fen;
    }
  }
}
