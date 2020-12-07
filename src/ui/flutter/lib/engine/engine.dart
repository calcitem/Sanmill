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

import 'package:sanmill/mill/position.dart';

enum EngineType {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  humanVsCloud,
  humanVsLAN,
  testViaLAN
}

class EngineResponse {
  final String type;
  final dynamic value;
  EngineResponse(this.type, {this.value});
}

abstract class AiEngine {
  Future<void> setOptions() async {}
  Future<void> startup() async {}
  Future<void> shutdown() async {}
  Future<EngineResponse> search(Position position, {bool byUser = true});
}
