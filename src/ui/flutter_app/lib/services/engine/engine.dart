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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/services/storage/storage.dart';

enum EngineType {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  humanVsCloud, // Not Implemented
  humanVsLAN, // Not Implemented
  testViaLAN, // Not Implemented
  none
}

extension EngineTypeExtensiont on EngineType {
  IconData? get leftHeaderIcon {
    switch (this) {
      case EngineType.humanVsAi:
        if (LocalDatabaseService.preferences.aiMovesFirst) {
          return FluentIcons.bot_24_filled;
        } else {
          return FluentIcons.person_24_filled;
        }
      case EngineType.humanVsHuman:
        return FluentIcons.person_24_filled;

      case EngineType.aiVsAi:
        return FluentIcons.bot_24_filled;
      case EngineType.humanVsCloud:
        return FluentIcons.person_24_filled;
      case EngineType.humanVsLAN:
        return FluentIcons.person_24_filled;
      case EngineType.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
      case EngineType.none:
        assert(false);
    }
  }

  IconData? get rightHeaderIcon {
    switch (this) {
      case EngineType.humanVsAi:
        if (LocalDatabaseService.preferences.aiMovesFirst) {
          return FluentIcons.person_24_filled;
        } else {
          return FluentIcons.bot_24_filled;
        }
      case EngineType.humanVsHuman:
        return FluentIcons.person_24_filled;
      case EngineType.aiVsAi:
        return FluentIcons.bot_24_filled;
      case EngineType.humanVsCloud:
        return FluentIcons.cloud_24_filled;
      case EngineType.humanVsLAN:
        return FluentIcons.wifi_1_24_filled;
      case EngineType.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
      case EngineType.none:
        assert(false);
    }
  }
}

class EngineResponse {
  final String type;
  final dynamic value;
  EngineResponse(this.type, {this.value});
}

abstract class Engine {
  Future<void> setOptions() async {}
  Future<void> startup() async {}
  Future<void> shutdown() async {}
  Future<EngineResponse> search(Position? position);
}
