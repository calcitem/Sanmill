// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// engine.dart

part of '../mill.dart';

class Engine {
  Engine();

  static const MethodChannel _platform =
      MethodChannel("com.calcitem.sanmill/engine");

  bool get _isPlatformChannelAvailable => !kIsWeb;

  static const String _logTag = "[engine]";

  Future<void> startup() async {
    await setOptions();

    if (!_isPlatformChannelAvailable) {
      return;
    }

    await _platform.invokeMethod("startup");
    await _waitResponse(<String>["uciok"]);
  }

  Future<void> _send(String command) async {
    if (!_isPlatformChannelAvailable) {
      return;
    }

    logger.t("$_logTag send: $command");
    await _platform.invokeMethod("send", command);
  }

  Future<void> _sendOptions(String name, dynamic option) async {
    if (!_isPlatformChannelAvailable) {
      return;
    }

    final String command = "setoption name $name value $option";
    await _send(command);

    if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
      final Catcher2Options options = catcher.getCurrentConfig()!;
      options.customParameters[name] = command;
    }
  }

  Future<String?> _read() async {
    if (!_isPlatformChannelAvailable) {
      return "";
    }

    return _platform.invokeMethod("read");
  }

  Future<void> shutdown() async {
    if (!_isPlatformChannelAvailable) {
      return;
    }

    await _platform.invokeMethod("shutdown");
  }

  /*
  Future<String?> _isReady() async {
    if (!_isPlatformChannelAvailable) return "";

    return _platform.invokeMethod("isReady");
  }
  */

  FutureOr<bool> isThinking() async {
    if (!_isPlatformChannelAvailable) {
      return false;
    }

    final bool? isThinking = await _platform.invokeMethod<bool>("isThinking");

    if (isThinking is bool) {
      return isThinking;
    } else {
      // ignore: only_throw_errors
      throw "Invalid platform response. Expected a value of type bool";
    }
  }

  /// Saves the given FEN string to a local file named 'fen.txt'.
  /// If the file already exists, the FEN is appended with a newline.
  Future<void> _saveFenToFile(String fen) async {
    try {
      // Get the application documents directory.
      final Directory directory = await getApplicationDocumentsDirectory();

      // Define the path to 'fen.txt'.
      final String path = '${directory.path}/fen.txt';

      final File file = File(path);

      // Append the FEN string with a newline. If the file doesn't exist, it will be created.
      await file.writeAsString('$fen\n', mode: FileMode.append);

      logger.i("Successfully saved FEN to $path");
    } catch (e) {
      logger.e("Failed to save FEN to file: $e");
      // Handle the error as needed, possibly rethrow or notify the user.
    }
  }

  Future<EngineRet> search({bool moveNow = false}) async {
    // Clear any existing analysis markers when AI makes a move
    AnalysisMode.disable();

    String? fen;
    final String normalizedFen;

    if (await isThinking()) {
      await stopSearching();
    } else if (moveNow) {
      // TODO: Check why go here.
      await stopSearching();
      final String? fen = _getPositionFen();
      if (fen == null) {
        // ignore: only_throw_errors
        throw const EngineNoBestMove();
      }
      await _send(fen);
      await _send("go");
      await stopSearching();
    }

    if (!moveNow) {
      fen = GameController().position.fen;
      if (fen == null) {
        // ignore: only_throw_errors
        throw const EngineNoBestMove();
      }

      final List<String> fenFields = fen.split(' ');
      if (fenFields.length < 2) {
        normalizedFen = fen;
      } else {
        // Replace the second last field with '0'
        fenFields[fenFields.length - 2] = '0';
        // Replace the third last field with '0'
        fenFields[fenFields.length - 3] = '0';
        normalizedFen = fenFields.join(' ');
      }

      logger.i("FEN = $normalizedFen");

      // Check if the normalized FEN exists in the fenToBestMoves map
      if (isRuleSupportingOpeningBook() &&
          DB().generalSettings.useOpeningBook &&
          (nineMensMorrisFenToBestMoves.containsKey(normalizedFen) ||
              elFiljaFenToBestMoves.containsKey(normalizedFen))) {
        final List<String> bestMoves;

        if (DB().ruleSettings.isLikelyNineMensMorris()) {
          bestMoves = nineMensMorrisFenToBestMoves[normalizedFen]!;
        } else if (DB().ruleSettings.isLikelyElFilja()) {
          bestMoves = elFiljaFenToBestMoves[normalizedFen]!;
        } else {
          bestMoves = nineMensMorrisFenToBestMoves[normalizedFen]!;
        }

        // Retrieve the shufflingEnabled setting
        final bool shufflingEnabled = DB().generalSettings.shufflingEnabled;

        String selectedMove;

        if (shufflingEnabled) {
          // Shuffle is enabled: select a random move from the list
          final int seed = DateTime.now().millisecondsSinceEpoch;
          final Random random = Random(seed);
          selectedMove = bestMoves[random.nextInt(bestMoves.length)];
        } else {
          // Shuffle is disabled: select the first move
          selectedMove = bestMoves.first;
        }

        // Check if the first character of selectedMove is 'x'
        if (selectedMove.startsWith('x')) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          // Extract the part after 'x', query wmdNotationToMove, and prepend '-'
          final String move = wmdNotationToMove[selectedMove.substring(1)]!;
          return EngineRet(
            "0", // Default score
            AiMoveType.openingBook,
            ExtMove(
              '-$move',
              side: GameController().position.sideToMove,
            ),
          );
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          // Default logic for selectedMove
          return EngineRet(
            "0", // Default score
            AiMoveType.openingBook,
            ExtMove(
              wmdNotationToMove[selectedMove]!,
              side: GameController().position.sideToMove,
            ),
          );
        }
      } else {
        // FEN not found in predefined map: proceed with engine search
        fen = _getPositionFen();
        if (fen == null) {
          // ignore: only_throw_errors
          throw const EngineNoBestMove();
        }
        await _send(fen);
        await _send("go");
      }
    } else {
      logger.t("$_logTag Move now");
    }

    final String? response =
        await _waitResponse(<String>["bestmove", "nobestmove"]);

    if (response == null) {
      // ignore: only_throw_errors
      throw const EngineTimeOut();
    }

    logger.t("$_logTag response: $response");

    if (response.contains("bestmove")) {
      final RegExp regex =
          RegExp(r"info score (-?\d+)(?: aimovetype (\w+))? bestmove (.*)");
      final Match? match = regex.firstMatch(response);
      String value = "";
      String aiMoveTypeStr = "";
      String best = "";
      AiMoveType aiMoveType = AiMoveType.unknown;

      if (match != null) {
        value = match.group(1)!;
        aiMoveTypeStr = match.group(2) ?? "";
        best = match.group(3)!.trim(); // Trim any extra whitespace
        logger.i("$_logTag Parsed bestmove: '$best'");
      } else {
        // Fallback: try to extract bestmove directly
        final int bestmoveIndex = response.indexOf("bestmove ");
        if (bestmoveIndex != -1) {
          best = response.substring(bestmoveIndex + 9).trim();
          logger.i("$_logTag Fallback parsed bestmove: '$best'");
        }
      }

      if (best.isEmpty) {
        logger.e("$_logTag Empty bestmove!");
        throw const EngineNoBestMove();
      }

      if (aiMoveTypeStr == "" || aiMoveTypeStr == "traditional") {
        aiMoveType = AiMoveType.traditional;
      } else if (aiMoveTypeStr == "perfect") {
        aiMoveType = AiMoveType.perfect;
        if (EnvironmentConfig.devMode == true) {
          final String? saveFen = GameController().position.fen;

          // Save saveFen to local file if it does not contain " m ".
          if (saveFen != null) {
            if (!saveFen.contains(" m ")) {
              await _saveFenToFile(saveFen);
            } else {
              logger.w("$_logTag saveFen contains ' m ', not saving to file.");
            }
          } else {
            logger.w("$_logTag saveFen is null, cannot save to file.");
          }
        }
      } else if (aiMoveTypeStr == "consensus") {
        aiMoveType = AiMoveType.consensus;
      }

      return EngineRet(
          value,
          aiMoveType,
          ExtMove(
            best,
            side: GameController().position.sideToMove.opponent,
          ));
    }

    if (response.contains("nobestmove")) {
      // ignore: only_throw_errors
      throw const EngineNoBestMove();
    }

    // ignore: only_throw_errors
    throw const EngineTimeOut();
  }

  Future<String?> _waitResponse(
    List<String> prefixes, {
    int sleep = 100,
    int times = 0,
  }) async {
    final GeneralSettings settings = DB().generalSettings;

    int timeLimit = EnvironmentConfig.devMode ? 100 : 6000;

    if (settings.moveTime > 0) {
      // TODO: Accurate timeLimit
      timeLimit = settings.moveTime * 10 * 64 + 10;
    }

    if (times > timeLimit) {
      logger.t("$_logTag Timeout. sleep = $sleep, times = $times");

      // Note:
      // Do not throw exception in the production environment here.
      // Because if the user sets the search depth to be very deep, but his phone performance is low, it may timeout.
      // But we have to test timeout in devMode to identify anomalies under shallow search.
      // What method is user-friendly is to be discussed.
      if (EnvironmentConfig.devMode) {
        throw TimeoutException("$_logTag waitResponse timeout.");
      }
      return null;
    }

    final String? response = await _read();

    if (response != null) {
      for (final String prefix in prefixes) {
        if (response.contains(prefix)) {
          return response;
        } else {
          if (response == "") {
            if (EnvironmentConfig.devMode) {
              logger.w("$_logTag Empty response");
            }
          } else {
            logger.w("$_logTag Unexpected engine response: $response");
          }
        }
      }
    }

    return Future<String?>.delayed(
      Duration(milliseconds: sleep),
      () => _waitResponse(prefixes, times: times + 1),
    );
  }

  Future<void> stopSearching() async {
    logger.w("$_logTag Stop current thinking...");
    await _send("stop");
  }

  Future<void> setGeneralOptions() async {
    if (kIsWeb) {
      return;
    }

    final GeneralSettings generalSettings = DB().generalSettings;

    // First Move
    // No need to tell engine.

    // Difficulty
    await _sendOptions("SkillLevel", generalSettings.skillLevel);
    await _sendOptions("MoveTime", generalSettings.moveTime);

    // AI's play style
    await _sendOptions(
        "Algorithm",
        generalSettings.searchAlgorithm?.index ??
            SearchAlgorithm.mtdf.index); // TODO: enum

    bool usePerfectDatabase = false;

    if (isRuleSupportingPerfectDatabase()) {
      usePerfectDatabase = generalSettings.usePerfectDatabase;
    } else {
      usePerfectDatabase = false;
      if (generalSettings.usePerfectDatabase) {
        DB().generalSettings =
            generalSettings.copyWith(usePerfectDatabase: false);
      }
    }

    await _sendOptions(
      "UsePerfectDatabase",
      usePerfectDatabase,
    );

    final Directory? dir = (!kIsWeb && Platform.isAndroid)
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final String perfectDatabasePath = '${dir?.path ?? ""}/strong';
    await _sendOptions(
      "PerfectDatabasePath",
      perfectDatabasePath,
    );
    await _sendOptions(
      "DrawOnHumanExperience",
      generalSettings.drawOnHumanExperience,
    );
    await _sendOptions("ConsiderMobility", generalSettings.considerMobility);
    await _sendOptions(
        "FocusOnBlockingPaths", generalSettings.focusOnBlockingPaths);
    await _sendOptions("AiIsLazy", generalSettings.aiIsLazy);
    await _sendOptions("Shuffling", generalSettings.shufflingEnabled);

    // Control via environment configuration
    await _sendOptions("DeveloperMode", EnvironmentConfig.devMode);
  }

  Future<void> setRuleOptions() async {
    final RuleSettings ruleSettings = DB().ruleSettings;

    // General
    await _sendOptions("PiecesCount", ruleSettings.piecesCount);
    await _sendOptions("HasDiagonalLines", ruleSettings.hasDiagonalLines);
    await _sendOptions("NMoveRule", ruleSettings.nMoveRule);
    await _sendOptions("EndgameNMoveRule", ruleSettings.endgameNMoveRule);
    await _sendOptions(
      "ThreefoldRepetitionRule",
      ruleSettings.threefoldRepetitionRule,
    );
    // Not available to user settings
    await _sendOptions("PiecesAtLeastCount", ruleSettings.piecesAtLeastCount);

    // Placing
    await _sendOptions(
        "BoardFullAction",
        ruleSettings.boardFullAction?.index ??
            BoardFullAction.firstPlayerLose.index); // TODO: enum
    await _sendOptions(
        "MillFormationActionInPlacingPhase",
        ruleSettings.millFormationActionInPlacingPhase?.index ??
            MillFormationActionInPlacingPhase
                .removeOpponentsPieceFromBoard.index); // TODO: enum
    await _sendOptions(
      "MayMoveInPlacingPhase",
      ruleSettings.mayMoveInPlacingPhase,
    ); // Not yet implemented

    // Moving
    await _sendOptions(
      "IsDefenderMoveFirst",
      ruleSettings.isDefenderMoveFirst,
    );
    await _sendOptions(
      "RestrictRepeatedMillsFormation",
      ruleSettings.restrictRepeatedMillsFormation,
    );
    await _sendOptions(
        "StalemateAction",
        ruleSettings.stalemateAction?.index ??
            StalemateAction.endWithStalemateLoss.index); // TODO: enum

    // Flying
    await _sendOptions("MayFly", ruleSettings.mayFly);
    await _sendOptions("FlyPieceCount", ruleSettings.flyPieceCount);

    // Removing
    await _sendOptions(
      "MayRemoveFromMillsAlways",
      ruleSettings.mayRemoveFromMillsAlways,
    );
    await _sendOptions("MayRemoveMultiple", ruleSettings.mayRemoveMultiple);
    await _sendOptions("OneTimeUseMill", ruleSettings.oneTimeUseMill);
  }

  Future<void> setOptions() async {
    logger.i("$_logTag reloaded engine options");

    await setGeneralOptions();
    await setRuleOptions();
  }

  static bool isRuleSupportingOpeningBook() {
    final RuleSettings ruleSettings = DB().ruleSettings;

    if (ruleSettings.isLikelyNineMensMorris() ||
        ruleSettings.isLikelyElFilja()) {
      return true;
    } else {
      return false;
    }
  }

  String? _getPositionFen() {
    final String? startPosition =
        GameController().gameRecorder.lastPositionWithRemove;

    if (startPosition == null ||
        GameController().position.validateFen(startPosition) == false) {
      logger.e("Invalid FEN: $startPosition");
      return null;
    }

    final String? moves = GameController().position.movesSinceLastRemove;

    final StringBuffer posFenStr = StringBuffer("position fen $startPosition");

    if (moves != null) {
      posFenStr.write(" moves $moves");
    }

    final String ret = posFenStr.toString();

    // WAR
    if (GameController().gameRecorder.lastPositionWithRemove ==
        GameController().gameRecorder.setupPosition) {
      if (GameController().position.action == Act.remove) {
        // Remove this to Fix #818
        // TODO: Why commit 8d2f084 did this?
        //ret = ret.replaceFirst(" s ", " r ");
      }
    }

    if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
      final Catcher2Options options = catcher.getCurrentConfig()!;
      options.customParameters["PositionFen"] = ret;
    }

    return ret;
  }

  /// Analyze the current position using the perfect database
  Future<PositionAnalysisResult> analyzePosition() async {
    final String? fen = GameController().position.fen;
    if (fen == null) {
      return PositionAnalysisResult.error("Invalid board position");
    }

    // Prepare the command to send to the engine
    final String command = "analyze fen $fen";

    try {
      // Send command to engine
      await _send(command);

      // Wait for and parse response
      final String? response = await _waitResponse(<String>["info analysis"]);
      if (response == null) {
        return PositionAnalysisResult.error("Engine did not respond");
      }

      // Parse the analysis result
      // Expected format: "info analysis move1=win move2=draw move3=loss ..."
      // Or format: "info analysis (x,y)=outcome ..."
      // Also handles formats like "(x,y)->(a,b)=outcome" and "-(x,y)=outcome"
      final List<MoveAnalysisResult> results = <MoveAnalysisResult>[];

      // Remove prefix "info analysis " and split by space
      final List<String> parts =
          response.replaceFirst("info analysis ", "").split(" ");

      for (final String part in parts) {
        if (part.contains("=")) {
          final List<String> moveAndOutcome = part.split("=");
          if (moveAndOutcome.length == 2) {
            final String moveStr = moveAndOutcome[0];
            final GameOutcome outcome = _parseOutcome(moveAndOutcome[1]);

            // Handle different move formats
            if (moveStr.contains("->")) {
              // Move format: (x,y)->(a,b)
              final RegExp movePattern =
                  RegExp(r'\(([\d]+),([\d]+)\)->\(([\d]+),([\d]+)\)');
              final Match? match = movePattern.firstMatch(moveStr);

              if (match != null && match.groupCount >= 4) {
                final int fromX = int.parse(match.group(1)!);
                final int fromY = int.parse(match.group(2)!);
                final int toX = int.parse(match.group(3)!);
                final int toY = int.parse(match.group(4)!);

                final String fromSquare = "${_coordToFile(fromX)}$fromY";
                final String toSquare = "${_coordToFile(toX)}$toY";

                results.add(MoveAnalysisResult(
                  move: moveStr,
                  outcome: outcome,
                  fromSquare: pgn.Square(fromSquare),
                  toSquare: pgn.Square(toSquare),
                ));
              }
            } else if (moveStr.startsWith("-")) {
              // Remove format: -(x,y)
              final RegExp removePattern = RegExp(r'-\(([\d]+),([\d]+)\)');
              final Match? match = removePattern.firstMatch(moveStr);

              if (match != null && match.groupCount >= 2) {
                final int x = int.parse(match.group(1)!);
                final int y = int.parse(match.group(2)!);

                final String squareName = "${_coordToFile(x)}$y";

                results.add(MoveAnalysisResult(
                  move: moveStr,
                  outcome: outcome,
                  toSquare: pgn.Square(squareName),
                ));
              }
            } else {
              // Place format: (x,y)
              final _MoveSquares? fromTo = _parseMoveString(moveStr);
              if (fromTo != null) {
                results.add(MoveAnalysisResult(
                  move: moveStr,
                  outcome: outcome,
                  fromSquare: fromTo.from,
                  toSquare: fromTo.to,
                ));
              }
            }
          }
        }
      }

      if (results.isEmpty) {
        return PositionAnalysisResult.error("No analysis results available");
      }

      return PositionAnalysisResult(possibleMoves: results);
    } catch (e) {
      logger.e("$_logTag Error during analysis: $e");
      return PositionAnalysisResult.error("Error during analysis: $e");
    }
  }

  /// Parse the outcome string from the engine
  static GameOutcome _parseOutcome(String outcomeStr) {
    // Extract numerical value if present (format: "outcome(value)")
    String value = "";
    final RegExp valuePattern = RegExp(r'([a-z]+)\((-?\d+)\)');
    final Match? valueMatch = valuePattern.firstMatch(outcomeStr);

    if (valueMatch != null && valueMatch.groupCount >= 2) {
      outcomeStr = valueMatch.group(1)!; // Extract just the outcome part
      value = valueMatch.group(2)!; // Extract the numerical value
    }

    // Determine the outcome type
    GameOutcome baseOutcome;
    switch (outcomeStr.toLowerCase()) {
      case "win":
        baseOutcome = GameOutcome.win;
        break;
      case "draw":
        baseOutcome = GameOutcome.draw;
        break;
      case "loss":
        baseOutcome = GameOutcome.loss;
        break;
      case "advantage":
        baseOutcome = GameOutcome.advantage;
        break;
      case "disadvantage":
        baseOutcome = GameOutcome.disadvantage;
        break;
      case "unknown":
      default:
        baseOutcome = GameOutcome.unknown;
        break;
    }

    // If we have a numerical value, create outcome with the value
    if (value.isNotEmpty) {
      return GameOutcome.withValue(baseOutcome, value);
    }

    return baseOutcome;
  }

  /// Parse a move string in the format "(x,y)" and convert to Square objects
  static _MoveSquares? _parseMoveString(String moveStr) {
    // Support for format like "(2,1)"
    final RegExp coordPattern = RegExp(r'\((\d+),(\d+)\)');
    final Match? match = coordPattern.firstMatch(moveStr);

    if (match != null && match.groupCount == 2) {
      final int x = int.parse(match.group(1)!);
      final int y = int.parse(match.group(2)!);

      // Convert coordinates to PGN squares
      // Use the coordinates as-is without conversion for Nine Men's Morris
      final String squareName = "${_coordToFile(x)}$y";
      final pgn.Square toSquare = pgn.Square(squareName);

      return _MoveSquares(null, toSquare);
    }

    // Handle other move formats if needed
    return null;
  }

  /// Helper to convert numeric coordinates to algebraic notation file
  static String _coordToFile(int x) {
    // Convert 1-based coordinates to algebraic notation
    // Typically: x → file (a, b, c...), y → rank (1, 2, 3...)
    return String.fromCharCode('a'.codeUnitAt(0) + (x - 1));
  }
}

enum GameMode {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  setupPosition,
  humanVsCloud, // Not Implemented
  humanVsLAN,
  testViaLAN, // Not Implemented
}

Map<AiMoveType, IconData> aiMoveTypeIcons = <AiMoveType, IconData>{
  AiMoveType.traditional: FluentIcons.bot_24_filled,
  AiMoveType.perfect: FluentIcons.database_24_filled,
  AiMoveType.consensus: FluentIcons.bot_add_24_filled,
  AiMoveType.openingBook: FluentIcons.book_24_filled,
  AiMoveType.unknown: FluentIcons.bot_24_filled,
};

extension GameModeExtension on GameMode {
  IconData get leftHeaderIcon {
    final IconData botIcon = aiMoveTypeIcons[GameController().aiMoveType] ??
        FluentIcons.bot_24_filled;

    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return botIcon;
        } else {
          return FluentIcons.person_24_filled;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return botIcon;
      case GameMode.setupPosition:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.bot_24_regular;
        } else {
          return FluentIcons.person_24_regular;
        }
      case GameMode.humanVsCloud:
        return FluentIcons.person_24_filled;
      case GameMode.humanVsLAN:
        return FluentIcons.person_24_filled;
      case GameMode.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
    }
  }

  IconData get rightHeaderIcon {
    final IconData botIcon = aiMoveTypeIcons[GameController().aiMoveType] ??
        FluentIcons.bot_24_filled;

    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.person_24_filled;
        } else {
          return botIcon;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return botIcon;
      case GameMode.setupPosition:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.person_24_regular;
        } else {
          return FluentIcons.bot_24_regular;
        }
      case GameMode.humanVsCloud:
        return FluentIcons.cloud_24_filled;
      case GameMode.humanVsLAN:
        return FluentIcons.wifi_1_24_filled;
      case GameMode.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
    }
  }

  Map<PieceColor, bool> get whoIsAI {
    switch (this) {
      case GameMode.humanVsAi:
      case GameMode.testViaLAN:
        return <PieceColor, bool>{
          PieceColor.white: DB().generalSettings.aiMovesFirst,
          PieceColor.black: !DB().generalSettings.aiMovesFirst,
        };
      case GameMode.setupPosition:
      case GameMode.humanVsHuman:
      case GameMode.humanVsLAN:
      case GameMode.humanVsCloud:
        return <PieceColor, bool>{
          PieceColor.white: false,
          PieceColor.black: false,
        };
      case GameMode.aiVsAi:
        return <PieceColor, bool>{
          PieceColor.white: true,
          PieceColor.black: true,
        };
    }
  }
}

/// Result of the analysis for a single move
class MoveAnalysisResult {
  MoveAnalysisResult({
    required this.move,
    required this.outcome,
    this.fromSquare,
    required this.toSquare,
  });

  final String move;
  final GameOutcome outcome;
  final pgn.Square? fromSquare;
  final pgn.Square toSquare;
}

/// Result of the position analysis
class PositionAnalysisResult {
  PositionAnalysisResult({
    required this.possibleMoves,
    this.isValid = true,
    this.errorMessage,
  });

  factory PositionAnalysisResult.error(String message) {
    return PositionAnalysisResult(
      possibleMoves: <MoveAnalysisResult>[],
      isValid: false,
      errorMessage: message,
    );
  }

  final List<MoveAnalysisResult> possibleMoves;
  final bool isValid;
  final String? errorMessage;
}

/// Helper class to store move squares
class _MoveSquares {
  _MoveSquares(this.from, this.to);

  final pgn.Square? from;
  final pgn.Square to;
}

/// Game outcome from analysis
@immutable
class GameOutcome {
  const GameOutcome(this.name, {this.valueStr});

  final String name;

  // Store the value string from engine evaluation
  final String? valueStr;

  // Predefined outcome constants
  static const GameOutcome win = GameOutcome('win');
  static const GameOutcome draw = GameOutcome('draw');
  static const GameOutcome loss = GameOutcome('loss');
  static const GameOutcome advantage = GameOutcome('advantage');
  static const GameOutcome disadvantage = GameOutcome('disadvantage');
  static const GameOutcome unknown = GameOutcome('unknown');

  // Factory method to create outcome with value
  static GameOutcome withValue(GameOutcome baseOutcome, String value) {
    return GameOutcome(baseOutcome.name, valueStr: value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is GameOutcome && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}
