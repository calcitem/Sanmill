/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/services.dart';

import '../mill/mill.dart';
import '../mill/position.dart';
import 'engine.dart';

class NativeEngine extends AiEngine {
  //
  static const platform = const MethodChannel('com.calcitem.sanmill/engine');

  Future<void> startup() async {
    //
    try {
      await platform.invokeMethod('startup');
    } catch (e) {
      print('Native startup Error: $e');
    }

    //await setBookFile();

    await waitResponse(['uciok'], sleep: 1, times: 30);
  }

  Future<void> send(String command) async {
    //
    try {
      print("send: $command");
      await platform.invokeMethod('send', command);
    } catch (e) {
      print('Native sendCommand Error: $e');
    }
  }

  Future<String> read() async {
    //
    try {
      return await platform.invokeMethod('read');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

  Future<void> shutdown() async {
    //
    try {
      await platform.invokeMethod('shutdown');
    } catch (e) {
      print('Native shutdown Error: $e');
    }
  }

  Future<bool> isReady() async {
    //
    try {
      return await platform.invokeMethod('isReady');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

  Future<bool> isThinking() async {
    //
    try {
      return await platform.invokeMethod('isThinking');
    } catch (e) {
      print('Native readResponse Error: $e');
    }

    return null;
  }

/*
  Future setBookFile() async {
    //
    final docDir = await getApplicationDocumentsDirectory();
    final bookFile = File('${docDir.path}/book.dat');

    try {
      if (!await bookFile.exists()) {
        await bookFile.create(recursive: true);
        final bytes = await rootBundle.load("assets/book.dat");
        await bookFile.writeAsBytes(bytes.buffer.asUint8List());
      }
    } catch (e) {
      print(e);
    }

    await send("setoption bookfiles ${bookFile.path}");
  }
  */

  @override
  Future<EngineResponse> search(Position position, {bool byUser = true}) async {
    //
    if (await isThinking()) await stopSearching();

    send(buildPositionCommand(position));
    send('go');

    final response = await waitResponse(['bestmove', 'nobestmove']);

    print("response: $response");

    if (response.startsWith('bestmove')) {
      //
      var step = response.substring('bestmove'.length + 1);

      final pos = step.indexOf(' ');
      if (pos > -1) step = step.substring(0, pos);

      return EngineResponse('move', value: Move.fromEngineMove(step));
    }

    if (response.startsWith('nobestmove')) {
      return EngineResponse('nobestmove');
    }

    return EngineResponse('timeout');
  }

  Future<String> waitResponse(List<String> prefixes,
      {sleep = 100, times = 100}) async {
    //
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

  String buildPositionCommand(Position position) {
    /*
    final startPosition = position.lastCapturedPosition;
    final moves = position.movesSinceLastCaptured();

    if (moves.isEmpty) return 'position fen $startPosition';

    return 'position fen $startPosition moves $moves';
    */

    String fenStr = position.fen();

    return "position fen $fenStr";
  }
}
