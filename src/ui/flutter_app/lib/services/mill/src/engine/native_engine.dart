/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of '../../mill.dart';

// TODO: [Leptopoda] make this a utility class. There shouldn't be multiple engines running
// TODO: [calcitem] Test AI Vs. AI when the refactoring is complete.
class NativeEngine extends Engine {
  NativeEngine();

  static const _platform = MethodChannel("com.calcitem.sanmill/engine");
  bool _isActive = false;

  static const _tag = "[engine]";

  @override
  Future<void> startup() async {
    DB().listenPreferences.addListener(() => setOptions());

    await _platform.invokeMethod("startup");
    await _waitResponse(["uciok"]);
  }

  Future<void> _send(String command) async {
    logger.v("$_tag send: $command");
    await _platform.invokeMethod("send", command);
  }

  Future<void> _sendOptions(String name, dynamic option) async {
    final String command = "setoption name $name value $option";
    await _send(command);
  }

  Future<String?> _read() async {
    return _platform.invokeMethod("read");
  }

  @override
  Future<void> shutdown() async {
    DB().listenPreferences.removeListener(() => setOptions());

    _isActive = false;
    await _platform.invokeMethod("shutdown");
  }

  FutureOr<bool> _isThinking() async {
    final _isThinking = await _platform.invokeMethod<bool>("isThinking");
    if (_isThinking is bool) {
      return _isThinking;
    } else {
      throw "Invalid platform response. Expected a value of type bool";
    }
  }

  @override
  Future<EngineResponse> search(Position? position) async {
    if (await _isThinking()) {
      await _stopSearching();
    }

    if (position != null) {
      await _send(_getPositionFen(position));
      await _send("go");
      _isActive = true;
    } else {
      logger.v("$_tag Move now");
    }

    final response = await _waitResponse(["bestmove", "nobestmove"]);
    if (response == null) {
      return EngineResponse(EngineResponseType.timeout);
    }

    logger.v("$_tag response: $response");

    if (response.startsWith("bestmove")) {
      var best = response.substring("bestmove".length + 1);

      final pos = best.indexOf(" ");
      if (pos > -1) best = best.substring(0, pos);

      return EngineResponse(EngineResponseType.move, value: ExtMove(best));
    }

    if (response.startsWith("nobestmove")) {
      return EngineResponse(EngineResponseType.nobestmove);
    }

    return EngineResponse(EngineResponseType.timeout);
  }

  Future<String?> _waitResponse(
    List<String> prefixes, {
    int sleep = 100,
    int times = 0,
  }) async {
    final _pref = DB().preferences;

    var timeLimit = EnvironmentConfig.devMode ? 100 : 6000;

    if (_pref.moveTime > 0) {
      // TODO: Accurate timeLimit
      timeLimit = _pref.moveTime * 10 * 64 + 10;
    }

    if (times > timeLimit) {
      logger.v("$_tag Timeout. sleep = $sleep, times = $times");

      // Note:
      // Do not throw exception in the production environment here.
      // Because if the user sets the search depth to be very deep, but his phone performance is low, it may timeout.
      // But we have to test timeout in devMode to identify anomalies under shallow search.
      // What method is user-friendly is to be discussed.
      // TODO: [Leptopoda] seems like is isActive only checked here and only together with the DevMode.
      // we might be able to remove this
      if (EnvironmentConfig.devMode && _isActive) {
        throw Exception("$_tag waitResponse timeout.");
      }
      return null;
    }

    final response = await _read();

    if (response != null) {
      for (final prefix in prefixes) {
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

  Future<void> _stopSearching() async {
    _isActive = false;
    logger.w("$_tag Stop current thinking...");
    await _send("stop");
  }

  @override
  Future<void> setOptions() async {
    logger.i("$_tag reloaded engine options");

    final _pref = DB().preferences;
    final _rules = DB().rules;

    await _sendOptions("DeveloperMode", EnvironmentConfig.devMode);
    await _sendOptions("Algorithm", _pref.algorithm?.index ?? 2);
    await _sendOptions("DrawOnHumanExperience", _pref.drawOnHumanExperience);
    await _sendOptions("ConsiderMobility", _pref.considerMobility);
    await _sendOptions("SkillLevel", _pref.skillLevel);
    await _sendOptions("MoveTime", _pref.moveTime);
    await _sendOptions("AiIsLazy", _pref.aiIsLazy);
    await _sendOptions("Shuffling", _pref.shufflingEnabled);
    await _sendOptions("PiecesCount", _rules.piecesCount);
    await _sendOptions("FlyPieceCount", _rules.flyPieceCount);
    await _sendOptions("PiecesAtLeastCount", _rules.piecesAtLeastCount);
    await _sendOptions("HasDiagonalLines", _rules.hasDiagonalLines);
    await _sendOptions("HasBannedLocations", _rules.hasBannedLocations);
    await _sendOptions("MayMoveInPlacingPhase", _rules.mayMoveInPlacingPhase);
    await _sendOptions("IsDefenderMoveFirst", _rules.isDefenderMoveFirst);
    await _sendOptions("MayRemoveMultiple", _rules.mayRemoveMultiple);
    await _sendOptions(
      "MayRemoveFromMillsAlways",
      _rules.mayRemoveFromMillsAlways,
    );
    await _sendOptions(
      "MayOnlyRemoveUnplacedPieceInPlacingPhase",
      _rules.mayOnlyRemoveUnplacedPieceInPlacingPhase,
    );
    await _sendOptions(
      "IsWhiteLoseButNotDrawWhenBoardFull",
      _rules.isWhiteLoseButNotDrawWhenBoardFull,
    );
    await _sendOptions(
      "IsLoseButNotChangeSideWhenNoWay",
      _rules.isLoseButNotChangeSideWhenNoWay,
    );
    await _sendOptions("MayFly", _rules.mayFly);
    await _sendOptions("NMoveRule", _rules.nMoveRule);
    await _sendOptions("EndgameNMoveRule", _rules.endgameNMoveRule);
    await _sendOptions(
      "ThreefoldRepetitionRule",
      _rules.threefoldRepetitionRule,
    );
  }

  // TODO: [Leptopoda] don't pass around the position object as we can access it through [controller.position]
  String _getPositionFen(Position position) {
    final startPosition = position._fen;
    final moves = position.movesSinceLastRemove;

    final posFenStr = StringBuffer("position fen $startPosition");

    if (moves != null) {
      posFenStr.write(" moves $moves");
    }

    return posFenStr.toString();
  }
}
