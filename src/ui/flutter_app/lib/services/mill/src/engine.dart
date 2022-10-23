// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

  bool get _isPlatformChannelAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  static const String _tag = "[engine]";

  Future<void> startup() async {
    await setOptions();

    if (!_isPlatformChannelAvailable) return;

    await _platform.invokeMethod("startup");
    await _waitResponse(["uciok"]);
  }

  Future<void> _send(String command) async {
    if (!_isPlatformChannelAvailable) return;

    logger.v("$_tag send: $command");
    await _platform.invokeMethod("send", command);
  }

  Future<void> _sendOptions(String name, dynamic option) async {
    if (!_isPlatformChannelAvailable) return;

    final String command = "setoption name $name value $option";
    await _send(command);

    if (EnvironmentConfig.catcher == true) {
      CatcherOptions options = catcher.getCurrentConfig()!;
      options.customParameters[name] = command;
    }
  }

  Future<String?> _read() async {
    if (!_isPlatformChannelAvailable) return "";

    return _platform.invokeMethod("read");
  }

  Future<void> shutdown() async {
    if (kIsWeb) return;
    if (!_isPlatformChannelAvailable) return;

    await _platform.invokeMethod("shutdown");
  }

  /*
  Future<String?> _isReady() async {
    if (!_isPlatformChannelAvailable) return "";

    return _platform.invokeMethod("isReady");
  }
  */

  FutureOr<bool> isThinking() async {
    if (!_isPlatformChannelAvailable) return false;

    final bool? isThinking = await _platform.invokeMethod<bool>("isThinking");

    if (isThinking is bool) {
      return isThinking;
    } else {
      throw "Invalid platform response. Expected a value of type bool";
    }
  }

  Future<ExtMove> search({bool moveNow = false}) async {
    if (await isThinking()) {
      await stopSearching();
    } else if (moveNow) {
      // TODO: Check why go here.
      // assert(false);
      await stopSearching();
      await _send(_getPositionFen());
      await _send("go");
      await stopSearching();
    }

    if (!moveNow) {
      await _send(_getPositionFen());
      await _send("go");
    } else {
      logger.v("$_tag Move now");
    }

    final String? response = await _waitResponse(["bestmove", "nobestmove"]);

    if (response == null) {
      throw const EngineTimeOut();
    }

    logger.v("$_tag response: $response");

    if (response.startsWith("bestmove")) {
      String best = response.substring("bestmove".length + 1);

      final pos = best.indexOf(" ");
      if (pos > -1) best = best.substring(0, pos);

      return ExtMove(best);
    }

    if (response.startsWith("nobestmove")) {
      throw const EngineNoBestMove();
    }

    throw const EngineTimeOut();
  }

  Future<String?> _waitResponse(
    List<String> prefixes, {
    int sleep = 100,
    int times = 0,
  }) async {
    final settings = DB().generalSettings;

    var timeLimit = EnvironmentConfig.devMode ? 100 : 6000;

    if (settings.moveTime > 0) {
      // TODO: Accurate timeLimit
      timeLimit = settings.moveTime * 10 * 64 + 10;
    }

    if (times > timeLimit) {
      logger.v("$_tag Timeout. sleep = $sleep, times = $times");

      // Note:
      // Do not throw exception in the production environment here.
      // Because if the user sets the search depth to be very deep, but his phone performance is low, it may timeout.
      // But we have to test timeout in devMode to identify anomalies under shallow search.
      // What method is user-friendly is to be discussed.
      if (EnvironmentConfig.devMode) {
        throw TimeoutException("$_tag waitResponse timeout.");
      }
      return null;
    }

    final response = await _read();

    if (response != null) {
      for (final String prefix in prefixes) {
        if (response.startsWith(prefix)) {
          return response;
        } else {
          logger.w("$_tag Unexpected engine response: $response");
        }
      }
    }

    return Future<String?>.delayed(
      Duration(milliseconds: sleep),
      () => _waitResponse(prefixes, times: times + 1),
    );
  }

  Future<void> stopSearching() async {
    logger.w("$_tag Stop current thinking...");
    await _send("stop");
  }

  Future<void> setGeneralOptions() async {
    final generalSettings = DB().generalSettings;

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
    await _sendOptions(
      "DrawOnHumanExperience",
      generalSettings.drawOnHumanExperience,
    );
    await _sendOptions("ConsiderMobility", generalSettings.considerMobility);
    await _sendOptions("AiIsLazy", generalSettings.aiIsLazy);
    await _sendOptions("Shuffling", generalSettings.shufflingEnabled);

    // Control via environment configuration
    await _sendOptions("DeveloperMode", EnvironmentConfig.devMode);
  }

  Future<void> setRuleOptions() async {
    final ruleSettings = DB().ruleSettings;

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
    await _sendOptions("HasBannedLocations", ruleSettings.hasBannedLocations);
    await _sendOptions(
      "IsWhiteLoseButNotDrawWhenBoardFull",
      ruleSettings.isWhiteLoseButNotDrawWhenBoardFull,
    );
    await _sendOptions(
      "MayOnlyRemoveUnplacedPieceInPlacingPhase",
      ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase,
    );
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
      "IsLoseButNotChangeSideWhenNoWay",
      ruleSettings.isLoseButNotChangeSideWhenNoWay,
    );

    // Flying
    await _sendOptions("MayFly", ruleSettings.mayFly);
    await _sendOptions("FlyPieceCount", ruleSettings.flyPieceCount);

    // Removing
    await _sendOptions(
      "MayRemoveFromMillsAlways",
      ruleSettings.mayRemoveFromMillsAlways,
    );
    await _sendOptions("MayRemoveMultiple", ruleSettings.mayRemoveMultiple);
  }

  Future<void> setOptions() async {
    logger.i("$_tag reloaded engine options");

    await setGeneralOptions();
    await setRuleOptions();
  }

  String _getPositionFen() {
    // TODO: Check position
    final String? startPosition =
        MillController().recorder.lastPositionWithRemove;
    final String? moves = MillController().position.movesSinceLastRemove;

    final posFenStr = StringBuffer("position fen $startPosition");

    if (moves != null) {
      posFenStr.write(" moves $moves");
    }

    String ret = posFenStr.toString();

    if (EnvironmentConfig.catcher == true) {
      CatcherOptions options = catcher.getCurrentConfig()!;
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

extension GameModeExtension on GameMode {
  IconData get leftHeaderIcon {
    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.bot_24_filled;
        } else {
          return FluentIcons.person_24_filled;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return FluentIcons.bot_24_filled;
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
    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.person_24_filled;
        } else {
          return FluentIcons.bot_24_filled;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return FluentIcons.bot_24_filled;
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
        return {
          PieceColor.white: DB().generalSettings.aiMovesFirst,
          PieceColor.black: !DB().generalSettings.aiMovesFirst,
        };
      case GameMode.setupPosition:
      case GameMode.humanVsHuman:
      case GameMode.humanVsLAN:
      case GameMode.humanVsCloud:
        return {
          PieceColor.white: false,
          PieceColor.black: false,
        };
      case GameMode.aiVsAi:
        return {
          PieceColor.white: true,
          PieceColor.black: true,
        };
    }
  }
}
