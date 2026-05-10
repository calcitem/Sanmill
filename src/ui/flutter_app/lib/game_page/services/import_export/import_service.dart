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

      // Pop any overlay (e.g. the action menu) before showing the dialog so
      // that the dialog appears on top of the game page.
      if (shouldPop) {
        navigator.pop();
      }

      if (!context.mounted) {
        return;
      }

      // Show the clipboard content to the user so they can inspect it
      // and, if it is a URL, open it in a browser.
      await showQrScanResultDialog(context, text, title: s.importFailed);
      return;
    }

    // Record the import event BEFORE the history-navigation events so that
    // the replay engine can reconstruct the game recorder via ImportService.import
    // before replaying the ensuing takeBackAll / stepForwardAll events.
    recordImportEvent(text, includeVariations: includeVariations);

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

  /// Records a [RecordingEventType.gameImport] event so the import can be
  /// replayed exactly.  Must be called after a successful [import] and before
  /// the subsequent history-navigation events so that the event sequence in the
  /// recording matches the order expected by the replay engine.
  static void recordImportEvent(
    String pgnText, {
    bool includeVariations = true,
  }) {
    RecordingService().recordEvent(
      RecordingEventType.gameImport,
      <String, dynamic>{
        'pgnText': pgnText,
        'includeVariations': includeVariations,
      },
    );
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
        millScore[PieceColor.white]! +
        millScore[PieceColor.black]! +
        millScore[PieceColor.draw]!;

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

    result = GameController().gameRecorder.gameResultPgn;

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
    // Legacy PlayOK importer relied on the now-deleted Dart
    // `Position` rule machine for move validation.  Replacing it
    // requires routing the parsed move list through
    // `NativeMillGameSession.applyMoveString`; that is tracked as
    // a follow-up.  For now refuse the import.
    throw const ImportFormatException(
      'PlayOK import is temporarily unavailable on this build',
    );
  }

  /// Replays all nodes to assign a boardLayout to each node's node.data.
  static void fillAllNodesBoardLayout(
    PgnNode<ExtMove> root, {
    String? setupFen,
  }) {
    // Compute boardLayout for the mainline using the Rust kernel
    // through `NativeMillRulesPort`.  The legacy `Position`-based
    // DFS over branch points was removed with the rule-machine
    // cleanup; variations no longer get a per-node boardLayout
    // assigned (consumers fall back to the leading 26 chars of
    // the active FEN).
    final NativeMillRulesPort port = NativeMillRulesPort();
    if (setupFen != null && setupFen.isNotEmpty) {
      port.setFromFen(setupFen);
    }
    PgnNode<ExtMove> cursor = root;
    while (cursor.children.isNotEmpty) {
      final PgnNode<ExtMove> child = cursor.children.first;
      if (child.data == null) {
        break;
      }
      final ExtMove move = child.data!;
      GameAction? action;
      for (final GameAction a in port.legalActions) {
        if (MillActionCodec.moveStringFrom(a) == move.move) {
          action = a;
          break;
        }
      }
      if (action == null) {
        break;
      }
      port.apply(action);
      final String fen = port.exportFen();
      // Board section is the part before the first space.
      final int spaceIdx = fen.indexOf(' ');
      if (spaceIdx > 0) {
        final String nativeBoard = fen.substring(0, spaceIdx);
        if (nativeBoard.length == 26) {
          move.boardLayout = nativeBoard;
        }
      }
      cursor = child;
    }
    port.dispose();
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

    // Retrieve FEN from headers if present
    final String? fen = game.headers['FEN'];
    _loadActiveNativeSessionFromFenIfNeeded(fen);

    // The legacy PGN tree -> ExtMove tree conversion relied on
    // the now-deleted Dart `Position` rule machine for move
    // validation and side-to-move tracking through PGN
    // variations.  Re-implementing that on top of
    // `NativeMillGameSession` requires a synchronous
    // clone-and-replay primitive that the FRB kernel does not
    // expose yet; that is tracked as a follow-up.  For now refuse
    // PGN imports that include moves and only honour the leading
    // `[FEN ...]` header (already pushed into the native session
    // via `_loadActiveNativeSessionFromFenIfNeeded`).
    if (hasValidMoves) {
      throw const ImportFormatException(
        'PGN move-list import is temporarily unavailable on this build',
      );
    }
    if (fen != null && fen.isNotEmpty) {
      GameController().gameRecorder.setupPosition = fen;
    }
  }

  static void _loadActiveNativeSessionFromFenIfNeeded(String? fen) {
    if (!true || fen == null || fen.isEmpty) {
      return;
    }
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }
    final GameSession? session = GameSessionScope.sessionOf(context);
    if (session is NativeMillGameSession) {
      final bool loaded = session.loadFen(fen);
      assert(loaded, 'Native import FEN must be validated before loading.');
    }
  }
}
