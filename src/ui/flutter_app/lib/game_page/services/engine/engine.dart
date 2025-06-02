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
          // Use standard notation directly
          return EngineRet(
            "0", // Default score
            AiMoveType.openingBook,
            ExtMove(
              selectedMove,
              side: GameController().position.sideToMove,
            ),
          );
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          // Use standard notation directly
          return EngineRet(
            "0", // Default score
            AiMoveType.openingBook,
            ExtMove(
              selectedMove,
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
        best = match.group(3)!.trim();
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
      // Standard notation formats: "d5=outcome", "a1-a4=outcome", "xa1=outcome"
      final List<MoveAnalysisResult> results = <MoveAnalysisResult>[];

      // Debug: Log the raw response in dev mode
      if (EnvironmentConfig.devMode) {
        logger.i("$_logTag Raw analysis response: $response");
      }

      final List<String> rawParts =
          response.replaceFirst("info analysis ", "").split(" ");

      // Reconstruct move=outcome(...) segments that may contain spaces
      final List<String> parts = <String>[];
      String buffer = "";
      for (final String token in rawParts) {
        if (buffer.isEmpty) {
          buffer = token;
        } else {
          buffer += " $token";
        }

        // Check if we have a complete segment ending with ')'
        if (buffer.contains('=') && buffer.trim().endsWith(')')) {
          parts.add(buffer.trim());
          buffer = "";
        }
      }

      // Handle any remaining buffer without trailing ')'
      if (buffer.isNotEmpty && buffer.contains('=')) {
        parts.add(buffer.trim());
      }

      for (final String part in parts) {
        if (part.contains("=")) {
          final List<String> moveAndOutcome = part.split("=");
          if (moveAndOutcome.length == 2) {
            final String moveStr = moveAndOutcome[0];
            final GameOutcome outcome = _parseOutcome(moveAndOutcome[1]);

            // Debug: Log parsed outcome in dev mode
            if (EnvironmentConfig.devMode) {
              logger.i(
                  "$_logTag Parsed move: $moveStr, outcome: ${outcome.name}, "
                  "value: ${outcome.valueStr}, steps: ${outcome.stepCount}");
            }

            // Handle standard notation formats
            if (moveStr.startsWith('x') && moveStr.length == 3) {
              // Remove format: "xa1", "xd5"
              final String squareName =
                  moveStr.substring(1); // Remove 'x' prefix

              results.add(MoveAnalysisResult(
                move: moveStr,
                outcome: outcome,
                toSquare: pgn.Square(squareName),
              ));
            } else if (moveStr.contains('-') && moveStr.length == 5) {
              // Move format: "a1-a4", "d5-e5"
              final List<String> squares = moveStr.split('-');
              if (squares.length == 2) {
                final String fromSquare = squares[0];
                final String toSquare = squares[1];

                results.add(MoveAnalysisResult(
                  move: moveStr,
                  outcome: outcome,
                  fromSquare: pgn.Square(fromSquare),
                  toSquare: pgn.Square(toSquare),
                ));
              }
            } else if (moveStr.length == 2 &&
                RegExp(r'^[a-g][1-8]$').hasMatch(moveStr)) {
              // Place format: "d5", "a1"
              results.add(MoveAnalysisResult(
                move: moveStr,
                outcome: outcome,
                toSquare: pgn.Square(moveStr),
              ));
            } else {
              logger.w("$_logTag Unrecognized move format: $moveStr");
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
    // Debug: Log the raw outcome string in dev mode
    if (EnvironmentConfig.devMode) {
      logger.i("Parsing outcome string: '$outcomeStr'");
    }

    // Extract numerical value and step count if present
    // Format can be: "outcome(value)" or "outcome(value in N steps)"
    String value = "";
    int? stepCount;

    final RegExp valuePattern = RegExp(r'([a-z]+)\(([^)]+)\)');
    final Match? valueMatch = valuePattern.firstMatch(outcomeStr);

    if (valueMatch != null && valueMatch.groupCount >= 2) {
      outcomeStr = valueMatch.group(1)!; // Extract just the outcome part
      final String valueStr = valueMatch.group(2)!; // Extract the value part

      // Debug: Log extracted parts in dev mode
      if (EnvironmentConfig.devMode) {
        logger.i("Extracted outcome: '$outcomeStr', value part: '$valueStr'");
      }

      // Check if step count is included - Updated regex to be more flexible
      final RegExp stepPattern = RegExp(r'(-?\d+)\s+in\s+(\d+)\s+steps?');
      final Match? stepMatch = stepPattern.firstMatch(valueStr);

      if (stepMatch != null && stepMatch.groupCount >= 2) {
        value = stepMatch.group(1)!; // Extract numerical value
        stepCount = int.tryParse(stepMatch.group(2)!); // Extract step count

        // Debug: Log extracted step count in dev mode
        if (EnvironmentConfig.devMode) {
          logger.i("Extracted step count: $stepCount from value: $value");
        }
      } else {
        // No step information, just extract the numerical value
        final RegExp numPattern = RegExp(r'(-?\d+)');
        final Match? numMatch = numPattern.firstMatch(valueStr);
        if (numMatch != null) {
          value = numMatch.group(1)!;
        }

        // Debug: Log no step count found in dev mode
        if (EnvironmentConfig.devMode) {
          logger.i("No step count found, extracted value: '$value'");
        }
      }
    } else {
      // Debug: Log parsing failure in dev mode
      if (EnvironmentConfig.devMode) {
        logger.i(
            "Failed to match value pattern in outcome string: '$outcomeStr'");
      }
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

    // Create outcome with value and step count if available
    GameOutcome result;
    if (value.isNotEmpty && stepCount != null) {
      result = GameOutcome.withValueAndSteps(baseOutcome, value, stepCount);
      if (EnvironmentConfig.devMode) {
        logger.i(
            "Created outcome with steps: ${result.name}, value: ${result.valueStr}, steps: ${result.stepCount}");
      }
    } else if (value.isNotEmpty) {
      result = GameOutcome.withValue(baseOutcome, value);
      if (EnvironmentConfig.devMode) {
        logger.i(
            "Created outcome without steps: ${result.name}, value: ${result.valueStr}");
      }
    } else {
      result = baseOutcome;
      if (EnvironmentConfig.devMode) {
        logger.i("Created basic outcome: ${result.name}");
      }
    }

    return result;
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

/// Game outcome from analysis
@immutable
class GameOutcome {
  const GameOutcome(this.name, {this.valueStr, this.stepCount});

  final String name;

  // Store the value string from engine evaluation
  final String? valueStr;

  // Store step count information from perfect database
  final int? stepCount;

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

  // Factory method to create outcome with value and step count
  static GameOutcome withValueAndSteps(
      GameOutcome baseOutcome, String value, int? steps) {
    return GameOutcome(baseOutcome.name, valueStr: value, stepCount: steps);
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

  // Get display string with step information
  String get displayString {
    final StringBuffer buffer = StringBuffer(name);

    if (valueStr != null && valueStr!.isNotEmpty) {
      buffer.write(' ($valueStr');
      if (stepCount != null && stepCount! > 0) {
        buffer.write(' in $stepCount steps');
      }
      buffer.write(')');
    } else if (stepCount != null && stepCount! > 0) {
      buffer.write(' (in $stepCount steps)');
    }

    return buffer.toString();
  }
}
