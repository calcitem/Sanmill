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
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';

@Deprecated('use [LocalDatabaseService] instead')
class Settings {}

class DatabaseV1 {
  const DatabaseV1._();

  static const _tag = "[Database Migration]";

  static Future<File> _getFile() async {
    final fileName = Constants.settingsFilename;
    final docDir = await getApplicationDocumentsDirectory();

    return File('${docDir.path}/$fileName');
  }

  /// loads the preferences from the old datastore
  static Future<Map<String, dynamic>?> _loadFile(File _file) async {
    debugPrint("$_tag Loading $_file ...");

    try {
      final contents = await _file.readAsString();
      final _values = jsonDecode(contents) as Map<String, dynamic>?;
      debugPrint(_values.toString());
      return _values;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  /// migrates the deprecated Settings to the new [LocalDatabaseService]
  static Future<void> migrateDB() async {
    final _pref = LocalDatabaseService.preferences;
    if (!_pref.usesHiveDB) {
      debugPrint("$_tag migrate DB");
      final _file = await _getFile();
      final _json = await _loadFile(_file);
      if (_json != null) {
        LocalDatabaseService.colorSettings = ColorSettings.fromJson(_json);
        LocalDatabaseService.display = Display.fromJson(_json);
        LocalDatabaseService.preferences = Preferences.fromJson(_json);
        LocalDatabaseService.rules = Rules.fromJson(_json);
      }
      await _deleteFile(_file);
      LocalDatabaseService.preferences = _pref.copyWith(usesHiveDB: true);
    } else {
      debugPrint("$_tag we already use HiveDB. Skipping migration.");
    }
  }

  /// deletes the old settings file
  static Future<void> _deleteFile(File _file) async {
    debugPrint("$_tag deleting Settings...");

    if (await _file.exists()) {
      await _file.delete();
      debugPrint("$_tag $_file deleted");
    } else {
      debugPrint("$_tag $_file does not exist");
    }
  }

  /// initializes the [Rules] object with the contents of [LocalDatabaseService.rules]
  static void initRules() {
    final _rules = LocalDatabaseService.rules;
    // Rules
    rule.piecesCount = _rules.piecesCount;
    rule.flyPieceCount = _rules.flyPieceCount;
    rule.piecesAtLeastCount = _rules.piecesAtLeastCount;
    rule.hasDiagonalLines = _rules.hasDiagonalLines;
    rule.hasBannedLocations = _rules.hasBannedLocations;
    rule.mayMoveInPlacingPhase = _rules.mayMoveInPlacingPhase;
    rule.isDefenderMoveFirst = _rules.isDefenderMoveFirst;
    rule.mayRemoveMultiple = _rules.mayRemoveMultiple;
    rule.mayRemoveFromMillsAlways = _rules.mayRemoveFromMillsAlways;
    rule.mayOnlyRemoveUnplacedPieceInPlacingPhase =
        _rules.mayOnlyRemoveUnplacedPieceInPlacingPhase;
    rule.isWhiteLoseButNotDrawWhenBoardFull =
        _rules.isWhiteLoseButNotDrawWhenBoardFull;
    rule.isLoseButNotChangeSideWhenNoWay =
        _rules.isLoseButNotChangeSideWhenNoWay;
    rule.mayFly = _rules.mayFly;
    rule.nMoveRule = _rules.nMoveRule;
    rule.endgameNMoveRule = _rules.endgameNMoveRule;
    rule.threefoldRepetitionRule = _rules.threefoldRepetitionRule;
  }
}
