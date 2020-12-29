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

import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/mill/position.dart';

import 'engine.dart';

class NativeEngine extends AiEngine {
  static const platform = const MethodChannel('com.calcitem.sanmill/engine');

  Future<void> startup() async {
    try {
      await platform.invokeMethod('startup');
    } catch (e) {
      print('Native startup Error: $e');
    }

    await waitResponse(['uciok'], sleep: 1, times: 30);
  }

  Future<void> send(String command) async {
    try {
      print("send: $command");
      await platform.invokeMethod('send', command);
    } catch (e) {
      print('Native sendCommand Error: $e');
    }
  }

  Future<String> read() async {
    try {
      return await platform.invokeMethod('read');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

  Future<void> shutdown() async {
    try {
      await platform.invokeMethod('shutdown');
    } catch (e) {
      print('Native shutdown Error: $e');
    }
  }

  Future<bool> isReady() async {
    try {
      return await platform.invokeMethod('isReady');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

  Future<bool> isThinking() async {
    try {
      return await platform.invokeMethod('isThinking');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

  @override
  Future<EngineResponse> search(Position position, {bool byUser = true}) async {
    if (await isThinking()) await stopSearching();

    send(getPositionFen(position));
    send('go');

    final response = await waitResponse(['bestmove', 'nobestmove']);

    print("response: $response");

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
      {sleep = 100, times = 100}) async {
    if (times <= 0) return '';

    final response = await read();

    if (response != null) {
      for (var prefix in prefixes) {
        if (response.startsWith(prefix)) return response;
      }
    }

    return Future<String>.delayed(
      Duration(milliseconds: sleep),
      () => waitResponse(prefixes, times: times - 1),
    );
  }

  Future<void> stopSearching() async {
    await send('stop');
  }

  Future<void> setOptions() async {
    await send('setoption name Shuffling value ${Config.shufflingEnabled}');
    await send(
        'setoption name nTotalPiecesEachSide value ${Config.nTotalPiecesEachSide}');
    await send('setoption name nPiecesAtLeast value ${Config.nPiecesAtLeast}');
    await send(
        'setoption name hasObliqueLines value ${Config.hasObliqueLines}');
    await send(
        'setoption name hasBannedLocations value ${Config.hasBannedLocations}');
    await send(
        'setoption name isDefenderMoveFirst value ${Config.isDefenderMoveFirst}');
    await send(
        'setoption name allowRemoveMultiPiecesWhenCloseMultiMill value ${Config.allowRemoveMultiPiecesWhenCloseMultiMill}');
    await send(
        'setoption name allowRemovePieceInMill value ${Config.allowRemovePieceInMill}');
    await send(
        'setoption name isBlackLoseButNotDrawWhenBoardFull value ${Config.isBlackLoseButNotDrawWhenBoardFull}');
    await send(
        'setoption name isLoseButNotChangeSideWhenNoWay value ${Config.isLoseButNotChangeSideWhenNoWay}');
    await send('setoption name flyingAllowed value ${Config.flyingAllowed}');
    await send(
        'setoption name maxStepsLedToDraw value ${Config.maxStepsLedToDraw}');
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

    print("posFenStr: $posFenStr");

    return posFenStr;
  }
}
