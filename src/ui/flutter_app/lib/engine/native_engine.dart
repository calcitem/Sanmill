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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/types.dart';

import 'engine.dart';

class NativeEngine extends Engine {
  static const platform = const MethodChannel('com.calcitem.sanmill/engine');
  bool isActive = false;

  Future<void> startup() async {
    await platform.invokeMethod('startup');
    await waitResponse(['uciok'], sleep: 100, times: 0);
  }

  Future<void> send(String command) async {
    print("[engine] send: $command");
    await platform.invokeMethod('send', command);
  }

  Future<String?> read() async {
    return await platform.invokeMethod('read');
  }

  Future<void> shutdown() async {
    isActive = false;
    await platform.invokeMethod('shutdown');
  }

  Future<bool?> isReady() async {
    return await platform.invokeMethod('isReady');
  }

  FutureOr<bool> isThinking() async {
    return await platform.invokeMethod('isThinking');
  }

  @override
  Future<EngineResponse> search(Position? position) async {
    if (await isThinking()) {
      await stopSearching();
    }

    if (position != null) {
      await send(getPositionFen(position));
      await send('go');
      isActive = true;
    } else {
      print("[engine] Move now");
    }

    final response = await waitResponse(['bestmove', 'nobestmove']);

    print("[engine] response: $response");

    if (response.startsWith('bestmove')) {
      var best = response.substring('bestmove'.length + 1);

      final pos = best.indexOf(' ');
      if (pos > -1) best = best.substring(0, pos);

      return EngineResponse('move', value: Move.set(best));
    }

    if (response.startsWith('nobestmove')) {
      return EngineResponse('nobestmove');
    }

    return EngineResponse('timeout');
  }

  Future<String> waitResponse(List<String> prefixes,
      {sleep = 100, times = 0}) async {
    var timeLimit = Config.developerMode ? 100 : 6000;

    if (Config.moveTime > 0) {
      // TODO: Accurate timeLimit
      timeLimit = Config.moveTime * 10 * 64 + 10;
    }

    if (times > timeLimit) {
      print("[engine] Timeout. sleep = $sleep, times = $times");
      if (Config.developerMode && isActive) {
        throw ("Exception: waitResponse timeout.");
      }
      return '';
    }

    final response = await read();

    if (response != null) {
      for (var prefix in prefixes) {
        if (response.startsWith(prefix)) {
          return response;
        } else {
          print("[engine] Unexpected engine response: $response");
        }
      }
    }

    return Future<String>.delayed(
      Duration(milliseconds: sleep),
      () => waitResponse(prefixes, times: times + 1),
    );
  }

  Future<void> stopSearching() async {
    isActive = false;
    print("[engine] Stop current thinking...");
    await send('stop');
  }

  Future<void> setOptions() async {
    if (Config.settingsLoaded == false) {
      print("[engine] Settings is not loaded yet, now load settings...");
      await Config.loadSettings();
    }

    await send('setoption name DeveloperMode value ${Config.developerMode}');
    await send(
        'setoption name DrawOnHumanExperience value ${Config.drawOnHumanExperience}');
    await send('setoption name SkillLevel value ${Config.skillLevel}');
    await send('setoption name MoveTime value ${Config.moveTime}');
    await send('setoption name AiIsLazy value ${Config.aiIsLazy}');
    await send('setoption name Shuffling value ${Config.shufflingEnabled}');
    await send('setoption name PiecesCount value ${Config.piecesCount}');
    await send('setoption name FlyPieceCount value ${Config.flyPieceCount}');
    await send(
        'setoption name PiecesAtLeastCount value ${Config.piecesAtLeastCount}');
    await send(
        'setoption name HasDiagonalLines value ${Config.hasDiagonalLines}');
    await send(
        'setoption name HasBannedLocations value ${Config.hasBannedLocations}');
    await send(
        'setoption name IsDefenderMoveFirst value ${Config.isDefenderMoveFirst}');
    await send(
        'setoption name MayRemoveMultiple value ${Config.mayRemoveMultiple}');
    await send(
        'setoption name MayRemoveFromMillsAlways value ${Config.mayRemoveFromMillsAlways}');
    await send(
        'setoption name IsWhiteLoseButNotDrawWhenBoardFull value ${Config.isWhiteLoseButNotDrawWhenBoardFull}');
    await send(
        'setoption name IsLoseButNotChangeSideWhenNoWay value ${Config.isLoseButNotChangeSideWhenNoWay}');
    await send('setoption name MayFly value ${Config.mayFly}');
    await send(
        'setoption name MaxStepsLedToDraw value ${Config.maxStepsLedToDraw}');
  }

  String getPositionFen(Position position) {
    final startPosition = position.lastPositionWithRemove;
    final moves = position.movesSinceLastRemove();

    String posFenStr;

    if (moves.isEmpty) {
      posFenStr = "position fen $startPosition";
    } else {
      posFenStr = "position fen $startPosition moves $moves";
    }

    return posFenStr;
  }
}
