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

enum EngineType {
  humanVsAi,
  humanVsHuman,
  aiVsAi,

  /// Not Implemented
  humanVsCloud,

  /// Not Implemented
  humanVsLAN,

  /// Not Implemented
  testViaLAN,
  none
}

extension EngineTypeExtension on EngineType {
  IconData get leftHeaderIcon {
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
        throw Exception("No engine selected");
    }
  }

  IconData get rightHeaderIcon {
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
        throw Exception("No engine selected");
    }
  }

  Map<PieceColor, bool> get whoIsAI {
    switch (this) {
      case EngineType.humanVsAi:
      case EngineType.testViaLAN:
        return {
          PieceColor.white: LocalDatabaseService.preferences.aiMovesFirst,
          PieceColor.black: !LocalDatabaseService.preferences.aiMovesFirst,
        };
      case EngineType.humanVsHuman:
      case EngineType.humanVsLAN:
      case EngineType.humanVsCloud:
        return {
          PieceColor.white: false,
          PieceColor.black: false,
        };
      case EngineType.aiVsAi:
        return {
          PieceColor.white: true,
          PieceColor.black: true,
        };
      default:
        throw Exception("No engine to set");
    }
  }
}

enum EngineResponseType { move, timeout, nobestmove }

class EngineResponse {
  // TODO: extract the value as it is only needed by the move
  final EngineResponseType type;
  final Move? value;
  EngineResponse(this.type, {this.value});
}

abstract class Engine {
  const Engine();

  Future<void> setOptions() async {}
  Future<void> startup() async {}
  Future<void> shutdown() async {}
  Future<EngineResponse> search(Position? position);
}
