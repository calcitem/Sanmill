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

part of '../mill.dart';

// TODO: [Leptopoda] add constructor
final MillController controller = MillController();

// TODO: [Leptopoda] maybe make this a utility class ¿?
class MillController {
  static const _tag = "[Controller]";

  late final _Game gameInstance;
  late final Position position;
  late final Engine engine;
  // late _GameRecorder recorder;

  bool _initialized = false;
  bool get initialized => _initialized;

  MillController() {
    gameInstance = _Game(this);
    position = Position(this);
    engine = NativeEngine(this);
  }

  Future<void> start() async {
    if (_initialized) return;

    await engine.startup();

    _initialized = true;
    logger.i("$_tag initialized");
  }

  void dispose() {
    engine.shutdown();

    _initialized = false;
    logger.i("$_tag disposed");
  }
}
