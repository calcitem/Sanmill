// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_service.dart

part of '../mill.dart';

class ImportService {
  const ImportService._();

  static const String _logTag = "[Importer]";

  /// Tries to import the game saved in the device's clipboard.
  /// If the PGN contains variations, asks the user whether to include them.
  static Future<void> importGame(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    // Clear snack bars before clipboard read
    rootScaffoldMessengerKey.currentState?.clearSnackBars();

    // Pre-fetch context-dependent data
    final S s = S.of(context);
    final NavigatorState navigator = Navigator.of(context);

    // Read clipboard data (async)
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    // Immediately check if context is still valid
    if (!context.mounted) {
      return;
    }

    // Check if data is null - show error message
    if (data == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        s.cannotImport("null"),
      );
      GameController().headerTipNotifier.showTip(s.cannotImport("null"));

      if (shouldPop) {
        navigator.pop();
      }
      return;
    }

    final String? text = data.text;

    // If clipboard is empty or missing text, pop and return
    if (text == null) {
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(
        s.cannotImport("null"),
      );
      GameController().headerTipNotifier.showTip(s.cannotImport("null"));

      if (shouldPop) {
        navigator.pop();
      }
      return;
    }

    // Check if the PGN contains variations before importing
    bool includeVariations = true;
    bool hasVariations = false;
    if (_pgnContainsVariations(text)) {
      hasVariations = true;
      // Ask user whether to include variations
      includeVariations = await _showVariationsDialog(context);
    }

    if (!context.mounted) {
      return;
    }

    // Perform import logic
    try {
      import(text, includeVariations: includeVariations);
    } catch (exception) {
      if (!context.mounted) {
        return;
      }

      // Include experimental warning in error message if variations were selected
      final String errorMsg = s.cannotImport(exception.toString());
      final String tip = (hasVariations && includeVariations)
          ? '$errorMsg ${s.experimental}'
          : errorMsg;
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(tip);
      GameController().headerTipNotifier.showTip(tip);

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

    if (!context.mounted) {
      return;
    }

    if (historyResult == const HistoryOK()) {
      // Include experimental warning in success message if variations were selected
      final String message = (hasVariations && includeVariations)
          ? '${s.gameImported} ${s.experimental}'
          : s.gameImported;
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(message);
      GameController().headerTipNotifier.showTip(message);
    } else {
      final String tip = s.cannotImport(HistoryNavigator.importFailedStr);
      rootScaffoldMessengerKey.currentState?.showSnackBarClear(tip);
      GameController().headerTipNotifier.showTip(tip);

      HistoryNavigator.importFailedStr = "";
    }

    if (shouldPop) {
      navigator.pop();
    }
  }

  /// Checks if the PGN text contains variations (without fully importing).
  static bool _pgnContainsVariations(String text) {
    try {
      // Quick check: variations in PGN are denoted by parentheses
      // This is a fast pre-check before full parsing
      if (!text.contains('(')) {
        return false;
      }

      // Parse the PGN to accurately detect variations
      final PgnGame<PgnNodeData> game = PgnGame.parsePgn(text);
      return game.hasVariations();
    } catch (_) {
      return false;
    }
  }

  /// Shows a dialog asking the user whether to include variations.
  /// Returns true if user wants to include variations, false if mainline only.
  static Future<bool> _showVariationsDialog(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).variationsDetected),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(S.of(context).moveListContainsVariations),
              const SizedBox(height: 16),
              Text(S.of(context).includeVariations),
              const SizedBox(height: 20),
              SizedBox(
                width: double.maxFinite,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.show_chart),
                  label: Text(S.of(context).includeVariationsMainline),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.maxFinite,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.account_tree),
                  label: Text(S.of(context).includeVariationsAll),
                ),
              ),
            ],
          ),
          actions: const <Widget>[],
        );
      },
    );
    return result ?? false;
  }

  static String addTagPairs(String moveList) {
    final DateTime dateTime = DateTime.now();
    final String date = "${dateTime.year}.${dateTime.month}.${dateTime.day}";

    final int total =
        Position.score[PieceColor.white]! +
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

    String tagPairs =
        '[Event "Sanmill-Game"]\r\n'
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

  static void import(String moveList, {bool includeVariations = true}) {
    moveList = moveList.trim();
    String ml = moveList;

    logger.t("Clipboard text: $moveList");

    // Check if import content is valid
    if (moveList.isEmpty) {
      throw const ImportFormatException("Clipboard content is empty");
    }

    try {
      // TODO: Improve this logic
      if (isPlayOkMoveList(ml)) {
        _importPlayOk(ml);
        return;
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
        " -> ": "-",
      };

      ml = processOutsideBrackets(ml, replacements);
      _importPgn(ml, includeVariations: includeVariations);
    } catch (e) {
      // Log the specific error for debugging
      logger.e("$_logTag Import failed: $e");

      // Log the complete move list that was being imported
      logger.e("$_logTag Original move list to import:\n$moveList");
      logger.e("$_logTag Processed move list:\n$ml");

      // Rethrow to allow handling by the calling method
      rethrow;
    }
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

    final GameRecorder newHistory = GameRecorder(
      lastPositionWithRemove: GameController().position.fen,
    );

    final List<String> list = cleanUpPlayOkMoveList(moveList).split(" ");

    // Check if parsed notation is empty
    bool hasValidMoves = false;

    for (String token in list) {
      token = token.trim();
      if (token.isEmpty ||
          token.endsWith(".") ||
          token.startsWith("[") ||
          token.endsWith("]")) {
        continue;
      }

      // If the move starts with "x", it means it is a capture move (e.g. "xd3"), and is directly processed as a single move
      if (token.startsWith("x")) {
        final String move = _playOkNotationToMoveString(token);
        newHistory.appendMove(ExtMove(move, side: localPos.sideToMove));
        final bool ok = localPos.doMove(move);
        if (!ok) {
          throw ImportFormatException(" $token → $move");
        }
      }
      // If there is no "x" in the move, proceed normally
      else if (!token.contains("x")) {
        final String move = _playOkNotationToMoveString(token);
        newHistory.appendMove(ExtMove(move, side: localPos.sideToMove));
        final bool ok = localPos.doMove(move);
        if (!ok) {
          throw ImportFormatException("$token → $move");
        }
      }
      // If the move contains "x" and is not at the beginning, for example "b6xd3"
      else {
        final int idx = token.indexOf("x");
        final String preMove = token.substring(0, idx);
        final String captureMove = token.substring(idx); // contains 'x'
        final String m1 = _playOkNotationToMoveString(preMove);
        newHistory.appendMove(ExtMove(m1, side: localPos.sideToMove));
        final bool ok1 = localPos.doMove(m1);
        if (!ok1) {
          throw ImportFormatException(" $preMove → $m1");
        }

        final String m2 = _playOkNotationToMoveString(captureMove);
        newHistory.appendMove(ExtMove(m2, side: localPos.sideToMove));
        final bool ok2 = localPos.doMove(m2);
        if (!ok2) {
          throw ImportFormatException(" $captureMove → $m2");
        }
      }
    }

    if (newHistory.mainlineMoves.isNotEmpty) {
      GameController().newGameRecorder = newHistory;
      hasValidMoves = true;
    }

    // Throw exception if no valid moves found
    if (!hasValidMoves) {
      throw const ImportFormatException(
        "Cannot import: No valid moves found in the notation",
      );
    }
  }

  /// Replays all nodes to assign a boardLayout to each node's node.data.
  static void fillAllNodesBoardLayout(
    PgnNode<ExtMove> root, {
    String? setupFen,
  }) {
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
        // If this move recorded a preferredRemoveTarget (from a preceding place+remove notation),
        // set it into the position before executing, so the engine will choose the intended line.
        if (move.preferredRemoveTarget != null) {
          currentPos.preferredRemoveTarget = move.preferredRemoveTarget;
        }

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
  /// If [includeVariations] is false, only the mainline will be imported.
  static void _importPgn(String moveList, {bool includeVariations = true}) {
    // Parse entire PGN (including headers)
    PgnGame<PgnNodeData> game = PgnGame.parsePgn(moveList);

    // If user chose not to include variations, strip them
    if (!includeVariations && game.hasVariations()) {
      game = game.withoutVariations();
    }

    // Check if parsed game is empty or invalid
    final bool hasValidMoves = game.moves.mainline().isNotEmpty;
    final bool hasValidFen =
        game.headers.containsKey('FEN') &&
        game.headers['FEN'] != null &&
        game.headers['FEN']!.isNotEmpty;

    if (!hasValidMoves && !hasValidFen) {
      logger.e(
        "$_logTag Failed to parse PGN: Empty game with no moves and no FEN",
      );
      throw const ImportFormatException("");
    }

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
      san = san.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();

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
            segments.addAll(
              regex
                  .allMatches(remainingSan)
                  .map((RegExpMatch m) => m.group(0)!)
                  .toList(),
            );
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

    /// Recursively convert PGN tree to ExtMove tree with all variations
    void convertPgnNodeToExtMove(
      PgnNode<PgnNodeData> sourceNode,
      PgnNode<ExtMove> targetParent,
      Position position,
    ) {
      // Process all children (mainline first, then variations)
      for (final PgnNode<PgnNodeData> child in sourceNode.children) {
        if (child.data == null) {
          continue;
        }

        final String san = child.data!.san.trim().toLowerCase();
        if (san.isEmpty ||
            san == "*" ||
            san == "x" ||
            san == "xx" ||
            san == "xxx" ||
            san == "p") {
          // Skip pass moves or asterisks
          continue;
        }

        // Clone position for this variation to avoid state interference
        final Position branchPos = position.clone();
        final List<String> segments = splitSan(san);
        PgnNode<ExtMove>? lastAddedNode = targetParent;

        // Process all segments of this move
        for (int i = 0; i < segments.length; i++) {
          final String segment = segments[i];
          if (segment.isEmpty) {
            continue;
          }

          try {
            final String uciMove = _wmdNotationToMoveString(segment);

            // If this is a place move followed by a remove move (like "b4xb2"),
            // set preferred target so intervention capture selects the correct line
            if (!segment.startsWith('x') &&
                i + 1 < segments.length &&
                segments[i + 1].startsWith('x')) {
              final String nextRemoveMove = _wmdNotationToMoveString(
                segments[i + 1],
              );
              final int targetSquare = ExtMove._parseToSquare(nextRemoveMove);
              if (targetSquare != -1) {
                branchPos.preferredRemoveTarget = targetSquare;
              }
            }

            // Only attach comments, nags, and startingComments to the last segment.
            final List<int>? nags = (i == segments.length - 1)
                ? child.data!.nags
                : null;
            final List<String>? startingComments = (i == segments.length - 1)
                ? child.data!.startingComments
                : null;
            final List<String>? comments = (i == segments.length - 1)
                ? child.data!.comments
                : null;

            final ExtMove extMove = ExtMove(
              uciMove,
              side: branchPos.sideToMove,
              // Carry preferredRemoveTarget only for the place segment when followed by remove
              preferredRemoveTarget:
                  (!segment.startsWith('x') &&
                      i + 1 < segments.length &&
                      segments[i + 1].startsWith('x'))
                  ? ExtMove._parseToSquare(
                      _wmdNotationToMoveString(segments[i + 1]),
                    )
                  : null,
              nags: nags,
              startingComments: startingComments,
              comments: comments,
            );

            // Create new node and add to target tree
            final PgnNode<ExtMove> newNode = PgnNode<ExtMove>(extMove);
            newNode.parent = lastAddedNode;
            lastAddedNode!.children.add(newNode);
            lastAddedNode = newNode;

            final bool ok = branchPos.doMove(uciMove);
            if (!ok) {
              throw ImportFormatException(" $segment → $uciMove");
            }
          } catch (e) {
            logger.e("$_logTag Failed to parse move segment '$segment': $e");
            throw ImportFormatException(" $segment");
          }
        }

        // Recursively process children (sub-variations)
        if (lastAddedNode != null) {
          convertPgnNodeToExtMove(child, lastAddedNode, branchPos);
        }
      }
    }

    // Convert the entire PGN tree starting from the root
    convertPgnNodeToExtMove(game.moves, newHistory.pgnRoot, localPos);

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
