// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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
            ExtMove('-$move'),
          );
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          // Default logic for selectedMove
          return EngineRet(
            "0", // Default score
            AiMoveType.openingBook,
            ExtMove(wmdNotationToMove[selectedMove]!),
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
        best = match.group(3)!;
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

      return EngineRet(value, aiMoveType, ExtMove(best));
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

  static bool isRuleSupportingPerfectDatabase() {
    final RuleSettings ruleSettings = DB().ruleSettings;

    // TODO: WAR: Perfect Database only support standard 9mm and 12mm and Lasker Morris.
    if ((ruleSettings.piecesCount == 9 &&
            !ruleSettings.hasDiagonalLines &&
            ruleSettings.mayMoveInPlacingPhase == false) ||
        (ruleSettings.piecesCount == 10 &&
            !ruleSettings.hasDiagonalLines &&
            ruleSettings.mayMoveInPlacingPhase == true) ||
        (ruleSettings.piecesCount == 12 &&
                ruleSettings.hasDiagonalLines &&
                ruleSettings.mayMoveInPlacingPhase == false) &&
            ruleSettings.flyPieceCount == 3 &&
            ruleSettings.piecesAtLeastCount == 3 &&
            ruleSettings.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase
                    .removeOpponentsPieceFromBoard &&
            ruleSettings.boardFullAction == BoardFullAction.firstPlayerLose &&
            ruleSettings.restrictRepeatedMillsFormation == false &&
            ruleSettings.stalemateAction ==
                StalemateAction.endWithStalemateLoss &&
            ruleSettings.mayFly == true &&
            ruleSettings.mayRemoveFromMillsAlways == false &&
            ruleSettings.mayRemoveMultiple == false &&
            ruleSettings.oneTimeUseMill == false) {
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
}

enum GameMode {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  setupPosition,

  /// Not Implemented
  humanVsCloud,

  /// Not Implemented
  humanVsLAN,

  /// Not Implemented
  testViaLAN,
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
