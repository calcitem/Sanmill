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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';

@Deprecated('use [LocalDatabaseService] instead')
class Settings {
  static final settingsFileName = Constants.settingsFilename;
  static Settings? _instance;

  late File _file;
  Map<String, dynamic>? _values = {};

  // TODO: add constructor
  static Future<Settings> instance() async {
    if (_instance == null) {
      _instance = Settings();
      await _instance!._load(settingsFileName);
      debugPrint("[settings] $settingsFileName loaded.");
    }

    return _instance!;
  }

  dynamic operator [](String key) => _values![key];

  void operator []=(String key, dynamic value) => _values![key] = value;

  /// migrates the deprecated [Settings] to the new [LocalDatabaseService]
  Future<void> migrate() async {}

  Future<bool> _load(String fileName) async {
    // TODO: main() ExternalStorage
    // var docDir = await getExternalStorageDirectory();
    final docDir = await getApplicationDocumentsDirectory();

    _file = File('${docDir.path}/$fileName');

    debugPrint("[settings] Loading $_file ...");

    try {
      final contents = await _file.readAsString();
      _values = jsonDecode(contents) as Map<String, dynamic>?;
      debugPrint(_values.toString());
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }

    return true;
  }

  Future<void> restore() async {
    debugPrint("[settings] Restoring Settings...");

    if (_file.existsSync()) {
      _file.deleteSync();
      debugPrint("[settings] $_file deleted");
    } else {
      debugPrint("[settings] $_file does not exist");
    }
  }

  void initRules() {
    // Rules
    rule.piecesCount = LocalDatabaseService.rules.piecesCount;
    rule.flyPieceCount = LocalDatabaseService.rules.flyPieceCount;
    rule.piecesAtLeastCount = LocalDatabaseService.rules.piecesAtLeastCount;
    rule.hasDiagonalLines = LocalDatabaseService.rules.hasDiagonalLines;
    rule.hasBannedLocations = LocalDatabaseService.rules.hasBannedLocations;
    rule.mayMoveInPlacingPhase =
        LocalDatabaseService.rules.mayMoveInPlacingPhase;
    rule.isDefenderMoveFirst = LocalDatabaseService.rules.isDefenderMoveFirst;
    rule.mayRemoveMultiple = LocalDatabaseService.rules.mayRemoveMultiple;
    rule.mayRemoveFromMillsAlways =
        LocalDatabaseService.rules.mayRemoveFromMillsAlways;
    rule.mayOnlyRemoveUnplacedPieceInPlacingPhase =
        LocalDatabaseService.rules.mayOnlyRemoveUnplacedPieceInPlacingPhase;
    rule.isWhiteLoseButNotDrawWhenBoardFull =
        LocalDatabaseService.rules.isWhiteLoseButNotDrawWhenBoardFull;
    rule.isLoseButNotChangeSideWhenNoWay =
        LocalDatabaseService.rules.isLoseButNotChangeSideWhenNoWay;
    rule.mayFly = LocalDatabaseService.rules.mayFly;
    rule.nMoveRule = LocalDatabaseService.rules.nMoveRule;
    rule.endgameNMoveRule = LocalDatabaseService.rules.endgameNMoveRule;
    rule.threefoldRepetitionRule =
        LocalDatabaseService.rules.threefoldRepetitionRule;
  }
}
