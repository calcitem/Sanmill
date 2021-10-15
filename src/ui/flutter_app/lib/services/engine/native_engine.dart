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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/storage/storage.dart';

class NativeEngine extends Engine {
  static const platform = MethodChannel('com.calcitem.sanmill/engine');
  bool isActive = false;

  @override
  Future<void> startup() async {
    await platform.invokeMethod('startup');
    await waitResponse(['uciok']);
  }

  Future<void> send(String command) async {
    debugPrint("[engine] send: $command");
    await platform.invokeMethod('send', command);
  }

  Future<String?> read() async {
    return platform.invokeMethod('read');
  }

  @override
  Future<void> shutdown() async {
    isActive = false;
    await platform.invokeMethod('shutdown');
  }

  Future<bool?> isReady() async {
    return platform.invokeMethod('isReady');
  }

  FutureOr<bool> isThinking() async {
    final _isThinking = await platform.invokeMethod<bool>('isThinking');
    if (_isThinking is bool) {
      return _isThinking;
    } else {
      throw 'Invalid platform response. Expected a value of type bool';
    }
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
      debugPrint("[engine] Move now");
    }

    final response = await waitResponse(['bestmove', 'nobestmove']);

    debugPrint("[engine] response: $response");

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

  Future<String> waitResponse(
    List<String> prefixes, {
    int sleep = 100,
    int times = 0,
  }) async {
    var timeLimit = LocalDatabaseService.preferences.developerMode ? 100 : 6000;

    if (LocalDatabaseService.preferences.moveTime > 0) {
      // TODO: Accurate timeLimit
      timeLimit = LocalDatabaseService.preferences.moveTime * 10 * 64 + 10;
    }

    if (times > timeLimit) {
      debugPrint("[engine] Timeout. sleep = $sleep, times = $times");
      if (LocalDatabaseService.preferences.developerMode && isActive) {
        throw "Exception: waitResponse timeout.";
      }
      return '';
    }

    final response = await read();

    if (response != null) {
      for (final prefix in prefixes) {
        if (response.startsWith(prefix)) {
          return response;
        } else {
          debugPrint("[engine] Unexpected engine response: $response");
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
    debugPrint("[engine] Stop current thinking...");
    await send('stop');
  }

  @override
  Future<void> setOptions(BuildContext context) async {
    await send(
      'setoption name DeveloperMode value ${LocalDatabaseService.preferences.developerMode}',
    );
    await send(
      'setoption name Algorithm value ${LocalDatabaseService.preferences.algorithm}',
    );
    await send(
      'setoption name DrawOnHumanExperience value ${LocalDatabaseService.preferences.drawOnHumanExperience}',
    );
    await send(
      'setoption name ConsiderMobility value ${LocalDatabaseService.preferences.considerMobility}',
    );
    await send(
      'setoption name SkillLevel value ${LocalDatabaseService.preferences.skillLevel}',
    );
    await send(
      'setoption name MoveTime value ${LocalDatabaseService.preferences.moveTime}',
    );
    await send(
      'setoption name AiIsLazy value ${LocalDatabaseService.preferences.aiIsLazy}',
    );
    await send(
      'setoption name Shuffling value ${LocalDatabaseService.preferences.shufflingEnabled}',
    );
    await send(
      'setoption name PiecesCount value ${LocalDatabaseService.rules.piecesCount}',
    );
    await send(
      'setoption name FlyPieceCount value ${LocalDatabaseService.rules.flyPieceCount}',
    );
    await send(
      'setoption name PiecesAtLeastCount value ${LocalDatabaseService.rules.piecesAtLeastCount}',
    );
    await send(
      'setoption name HasDiagonalLines value ${LocalDatabaseService.rules.hasDiagonalLines}',
    );
    await send(
      'setoption name HasBannedLocations value ${LocalDatabaseService.rules.hasBannedLocations}',
    );
    await send(
      'setoption name MayMoveInPlacingPhase value ${LocalDatabaseService.rules.mayMoveInPlacingPhase}',
    );
    await send(
      'setoption name IsDefenderMoveFirst value ${LocalDatabaseService.rules.isDefenderMoveFirst}',
    );
    await send(
      'setoption name MayRemoveMultiple value ${LocalDatabaseService.rules.mayRemoveMultiple}',
    );
    await send(
      'setoption name MayRemoveFromMillsAlways value ${LocalDatabaseService.rules.mayRemoveFromMillsAlways}',
    );
    await send(
      'setoption name MayOnlyRemoveUnplacedPieceInPlacingPhase value ${LocalDatabaseService.rules.mayOnlyRemoveUnplacedPieceInPlacingPhase}',
    );
    await send(
      'setoption name IsWhiteLoseButNotDrawWhenBoardFull value ${LocalDatabaseService.rules.isWhiteLoseButNotDrawWhenBoardFull}',
    );
    await send(
      'setoption name IsLoseButNotChangeSideWhenNoWay value ${LocalDatabaseService.rules.isLoseButNotChangeSideWhenNoWay}',
    );
    await send(
      'setoption name MayFly value ${LocalDatabaseService.rules.mayFly}',
    );
    await send(
      'setoption name NMoveRule value ${LocalDatabaseService.rules.nMoveRule}',
    );
    await send(
      'setoption name EndgameNMoveRule value ${LocalDatabaseService.rules.endgameNMoveRule}',
    );
    await send(
      'setoption name ThreefoldRepetitionRule value ${LocalDatabaseService.rules.threefoldRepetitionRule}',
    );
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
