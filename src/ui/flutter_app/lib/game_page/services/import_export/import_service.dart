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

  /// Maps the rules-port active seat onto the legacy [PieceColor] domain
  /// used by [ExtMove.side].
  static PieceColor _sideToMoveOf(NativeMillRulesPort port) {
    final PlayerSeat seat = port.snapshot.activeSeat;
    assert(
      seat == PlayerSeat.first || seat == PlayerSeat.second,
      "$_logTag Cannot derive a mover from seat $seat.",
    );
    return seat == PlayerSeat.first ? PieceColor.white : PieceColor.black;
  }

  /// Finds the legal action whose canonical move string equals [move]
  /// (e.g. "d6", "a1-a4", "xa1") in [port]'s current position, or null
  /// when the move is illegal there.
  static GameAction? _legalActionForMoveString(
    NativeMillRulesPort port,
    String move,
  ) {
    for (final GameAction action in port.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == move) {
        return action;
      }
    }
    return null;
  }

  /// Validates [move] against [port], appends it to [history], and advances
  /// the port.  Throws [ImportFormatException] when the move is illegal in
  /// the current position ([token] names the offending source token).
  static void _applyValidatedMove(
    NativeMillRulesPort port,
    GameRecorder history,
    String move,
    String token,
  ) {
    final GameAction? action = _legalActionForMoveString(port, move);
    if (action == null) {
      throw ImportFormatException(" $token → $move");
    }
    history.appendMove(ExtMove(move, side: _sideToMoveOf(port)));
    port.apply(action);
  }

  /// Creates a private validation port configured with the user's active
  /// rule settings.  Import validation must run under the same variant as
  /// the active session (created from `DB().ruleSettings` by
  /// `MillGameModule.startSession`); a default-constructed port would
  /// reject legal moves from variants such as Twelve Men's Morris.
  static NativeMillRulesPort _newValidationPort() {
    return NativeMillRulesPort(
      ruleSettings: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
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

    final NativeMillRulesPort localPort = _newValidationPort();
    try {
      final GameRecorder newHistory = GameRecorder(
        lastPositionWithRemove: GameController().activeFen,
      );

      final List<String> list = cleanUpPlayOkMoveList(moveList).split(" ");

      for (String token in list) {
        token = token.trim();
        if (token.isEmpty ||
            token.endsWith(".") ||
            token.startsWith("[") ||
            token.endsWith("]")) {
          continue;
        }

        // A leading "x" marks a standalone capture move (e.g. "x12").
        if (token.startsWith("x")) {
          _applyValidatedMove(
            localPort,
            newHistory,
            _playOkNotationToMoveString(token),
            token,
          );
        }
        // No "x" at all: a plain place / move token.
        else if (!token.contains("x")) {
          _applyValidatedMove(
            localPort,
            newHistory,
            _playOkNotationToMoveString(token),
            token,
          );
        }
        // An embedded "x" (e.g. "18x21") encodes a move immediately
        // followed by a capture; split and apply both halves.
        else {
          final int idx = token.indexOf("x");
          final String preMove = token.substring(0, idx);
          final String captureMove = token.substring(idx); // contains 'x'
          _applyValidatedMove(
            localPort,
            newHistory,
            _playOkNotationToMoveString(preMove),
            preMove,
          );
          _applyValidatedMove(
            localPort,
            newHistory,
            _playOkNotationToMoveString(captureMove),
            captureMove,
          );
        }
      }

      if (newHistory.mainlineMoves.isEmpty) {
        throw const ImportFormatException.coded(
          ImportErrorCode.noValidMovesFound,
        );
      }

      GameController().newGameRecorder = newHistory;
    } finally {
      localPort.dispose();
    }
  }

  /// Replays all nodes to assign a boardLayout to each node's node.data.
  ///
  /// The whole PGN tree (mainline and variations) is walked depth-first on
  /// a private Rust-kernel port; the kernel undo stack restores the parent
  /// position when backtracking out of a branch, mirroring the clone-based
  /// DFS the legacy `Position` rule machine used.
  static void fillAllNodesBoardLayout(
    PgnNode<ExtMove> root, {
    String? setupFen,
  }) {
    final NativeMillRulesPort port = _newValidationPort();
    try {
      if (setupFen != null && setupFen.isNotEmpty) {
        port.setFromFen(setupFen);
      }
      _fillBoardLayoutDfs(root, port);
    } finally {
      port.dispose();
    }
  }

  static void _fillBoardLayoutDfs(
    PgnNode<ExtMove> node,
    NativeMillRulesPort port,
  ) {
    for (final PgnNode<ExtMove> child in node.children) {
      final ExtMove? move = child.data;
      if (move == null) {
        continue;
      }
      final GameAction? action = _legalActionForMoveString(port, move.move);
      if (action == null) {
        // Mirrors the legacy DFS: an unreplayable move (e.g. from a
        // hand-edited or rule-mismatched save) skips that subtree
        // instead of failing the whole load; consumers fall back to
        // the leading 26 chars of the active FEN.
        continue;
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
      _fillBoardLayoutDfs(child, port);
      port.undo();
    }
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

    final NativeMillRulesPort localPort = _newValidationPort();
    try {
      // Set up the board position using FEN if available; an invalid FEN
      // surfaces as an exception and aborts the import before any global
      // state is touched.
      if (fen != null && fen.isNotEmpty) {
        localPort.setFromFen(fen);
      }

      final GameRecorder newHistory = GameRecorder(
        lastPositionWithRemove: fen ?? GameController().activeFen,
        setupPosition: fen,
      );

      // Convert the entire PGN tree (with variations) to an ExtMove tree,
      // validating every move against the Rust kernel along the way.
      _convertPgnNodeToExtMove(game.moves, newHistory.pgnRoot, localPort);

      if (newHistory.mainlineMoves.isEmpty && (fen == null || fen.isEmpty)) {
        throw const ImportFormatException.coded(
          ImportErrorCode.noValidMovesFound,
        );
      }

      fillAllNodesBoardLayout(newHistory.pgnRoot, setupFen: fen);

      // The parse succeeded; only now touch controller / session state.
      _loadActiveNativeSessionFromFenIfNeeded(fen);
      GameController().newGameRecorder = newHistory;

      if (fen != null && fen.isNotEmpty) {
        GameController().gameRecorder.setupPosition = fen;
      }
    } finally {
      localPort.dispose();
    }
  }

  /// Splits a SAN token into its primitive move segments: an optional
  /// place / move part followed by zero or more "x.." capture parts
  /// (e.g. "b4xb2xc3" → ["b4", "xb2", "xc3"]).
  static List<String> _splitSan(String san) {
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
        // 'x' is known to be present and not at index 0 here.
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
      }
    } else {
      // No 'x', process as single segment
      segments.add(san);
    }

    return segments;
  }

  /// Recursively converts a parsed PGN tree into the ExtMove tree rooted at
  /// [targetParent], validating every move against [port].
  ///
  /// Each child branch is applied on the shared kernel port and undone after
  /// its subtree has been processed, which replaces the `Position.clone()`
  /// per-variation isolation the legacy Dart rule machine provided.
  static void _convertPgnNodeToExtMove(
    PgnNode<PgnNodeData> sourceNode,
    PgnNode<ExtMove> targetParent,
    NativeMillRulesPort port,
  ) {
    // Process all children (mainline first, then variations)
    for (final PgnNode<PgnNodeData> child in sourceNode.children) {
      if (child.data == null) {
        continue;
      }

      final String san = child.data!.san.trim().toLowerCase();
      if (san.isEmpty || san == "p") {
        // Skip empty or pass moves.
        // Note: "*", "x", "xx", "xxx" are not produced by the PGN
        // parser's token regex so they do not need to be checked here.
        continue;
      }

      final List<String> segments = _splitSan(san);
      PgnNode<ExtMove> lastAddedNode = targetParent;
      int appliedCount = 0;

      // Process all segments of this move
      for (int i = 0; i < segments.length; i++) {
        final String segment = segments[i];
        if (segment.isEmpty) {
          continue;
        }

        try {
          final String uciMove = _wmdNotationToMoveString(segment);

          final GameAction? action = _legalActionForMoveString(port, uciMove);
          if (action == null) {
            throw ImportFormatException(" $segment → $uciMove");
          }

          // If this is a place / move segment followed by a remove segment
          // (like "b4xb2"), record the preferred target so replay selects
          // the correct intervention-capture line.
          final bool nextSegmentRemoves =
              !segment.startsWith('x') &&
              i + 1 < segments.length &&
              segments[i + 1].startsWith('x');

          // Only attach comments, nags, and startingComments to the last segment.
          final bool isLastSegment = i == segments.length - 1;

          final ExtMove extMove = ExtMove(
            uciMove,
            side: _sideToMoveOf(port),
            preferredRemoveTarget: nextSegmentRemoves
                ? ExtMove._parseToSquare(
                    _wmdNotationToMoveString(segments[i + 1]),
                  )
                : null,
            nags: isLastSegment ? child.data!.nags : null,
            startingComments: isLastSegment
                ? child.data!.startingComments
                : null,
            comments: isLastSegment ? child.data!.comments : null,
          );

          // Create new node and add to target tree
          final PgnNode<ExtMove> newNode = PgnNode<ExtMove>(extMove);
          newNode.parent = lastAddedNode;
          lastAddedNode.children.add(newNode);
          lastAddedNode = newNode;

          port.apply(action);
          appliedCount++;
        } catch (e) {
          logger.e("$_logTag Failed to parse move segment '$segment': $e");
          throw ImportFormatException(" $segment");
        }
      }

      // Recursively process children (sub-variations)
      _convertPgnNodeToExtMove(child, lastAddedNode, port);

      // Backtrack out of this branch so siblings start from the same
      // parent position.
      for (int i = 0; i < appliedCount; i++) {
        port.undo();
      }
    }
  }

  static void _loadActiveNativeSessionFromFenIfNeeded(String? fen) {
    if (fen == null || fen.isEmpty) {
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

  // ---------------------------------------------------------------------
  // Notation conversion helpers (restored from the legacy
  // `notation_parsing.dart` after the rule-machine cleanup deleted it).
  // ---------------------------------------------------------------------

  /// Validates a WMD-style token and returns the canonical move string
  /// ("a1", "a1-a4", "xa1").  Throws [ImportFormatException] otherwise.
  static String _wmdNotationToMoveString(String wmd) {
    if (wmd.startsWith('x') && wmd.length == 3) {
      // Remove move format: "xa1", "xd5", etc.
      return wmd;
    }

    if (wmd.length == 5 && wmd[2] == '-') {
      // Move format: "a1-a4", "d5-e5", etc.
      return wmd;
    }

    if (wmd.length == 2 && RegExp(r'^[a-g][1-7]$').hasMatch(wmd)) {
      // Place move format: "a1", "d5", etc.
      return wmd;
    }

    // Unsupported format
    logger.w("$_logTag Unsupported move format: $wmd");
    throw ImportFormatException(wmd);
  }

  /// Converts PlayOK numeric notation ("12", "x12", "12-13") to the
  /// standard notation used by the engine.
  static String _playOkNotationToMoveString(String playOk) {
    if (playOk.isEmpty) {
      throw ImportFormatException(playOk);
    }

    final int iDash = playOk.indexOf("-");
    final int iX = playOk.indexOf("x");

    if (iDash == -1 && iX == -1) {
      // Simple place move: "12" -> "c4"
      final int val = int.parse(playOk);
      if (val >= 1 && val <= 24) {
        final String? standardNotation =
            playOkNotationToStandardNotation[playOk];
        if (standardNotation != null) {
          return standardNotation;
        }
      }
      throw ImportFormatException(playOk);
    }

    if (iX == 0) {
      // Remove move: "x12" -> "xc4"
      final String sub = playOk.substring(1);
      final int val = int.parse(sub);
      if (val >= 1 && val <= 24) {
        final String? standardNotation = playOkNotationToStandardNotation[sub];
        if (standardNotation != null) {
          return "x$standardNotation";
        }
      }
      throw ImportFormatException(playOk);
    }

    if (iDash != -1 && iX == -1) {
      // Move: "12-13" -> "c4-e4"
      final String sub1 = playOk.substring(0, iDash);
      final int val1 = int.parse(sub1);
      if (val1 < 1 || val1 > 24) {
        throw ImportFormatException(playOk);
      }

      final String sub2 = playOk.substring(iDash + 1);
      final int val2 = int.parse(sub2);
      if (val2 < 1 || val2 > 24) {
        throw ImportFormatException(playOk);
      }

      final String? fromSquare = playOkNotationToStandardNotation[sub1];
      final String? toSquare = playOkNotationToStandardNotation[sub2];

      if (fromSquare != null && toSquare != null) {
        return "$fromSquare-$toSquare";
      }
      throw ImportFormatException(playOk);
    }

    logger.w("$_logTag Not support parsing format oo-ooxo PlayOK notation.");
    throw ImportFormatException(playOk);
  }
}
