// ignore_for_file: deprecated_member_use_from_same_package

// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of 'package:sanmill/services/database/database.dart';

/// Database Migration Values
///
/// Values that define how much the DB is altered.
class MigrationValues {
  const MigrationValues._();

  /// [DisplaySettings.pieceWidth] migration value.
  static const pieceWidth = 7.0;

  /// [DisplaySettings.fontScale] migration value.
  static const fontScale = 16.0;
}

/// Database Migration
///
/// This class provides helper methods to migrate database versions.
class _DatabaseMigration {
  const _DatabaseMigration._();

  static const _tag = "[Database Migration]";

  /// The newest DB version.
  static const _newVersion = 2;

  /// The current DB version.
  /// It will get initialized by [migrate] with the saved value.
  static late final int? _currentVersion;

  /// The list of migrations
  static const _migrations = [
    _migrateToHive,
    _migrateFromV1,
  ];

  /// Database Box reference
  static late Box _databaseBox;

  /// Key at which the [_databaseBox] will be saved
  static const String _databaseBoxName = "database";

  /// Key at which the database info will be saved in the [_databaseBox]
  static const String _versionKey = "version";

  /// Migrates the database version to the [_newVersion].
  ///
  /// When [_currentVersion] is smaller than [_newVersion] all migrations between will be run.
  /// Migrations are called once and only once thus they should complete fast and everything should be awaited.
  static Future<void> migrate() async {
    assert(_migrations.length == _newVersion);

    _databaseBox = await Hive.openBox(_databaseBoxName);

    _currentVersion = _databaseBox.get(_versionKey) as int?;

    if (_currentVersion != null) {
      if (await _DatabaseV1.usesV1) {
        _currentVersion = 0;
      } else if (DB().generalSettings.usesHiveDB) {
        _currentVersion = 1;
      }
      logger.v("$_tag: Current version is $_currentVersion");

      for (int i = _currentVersion!; i < _newVersion; i++) {
        await _migrations[i].call();
      }
    }

    await _databaseBox.put(_versionKey, _newVersion);
    _databaseBox.close();
  }

  /// Migration 0 - KV to Hive
  ///
  /// - Calls the [_DatabaseV1.migrateDB] to migrate from KV database.
  static Future<void> _migrateToHive() async {
    assert(_currentVersion! <= 0);

    await _DatabaseV1.migrateDB();
    logger.i("$_tag Migrated from KV to DB");
  }

  /// Migration 1 - Sanmill version 1.x.x
  ///
  /// - **Algorithm to enum:** Migrates [DB.generalSettings] to use the new Algorithm enum instead of an int representation.
  /// - **Drawer background color:** Migrates [DB.colorSettings] to merge the drawerBackgroundColor and drawerColor.
  /// This reflects the deprecation of drawerBackgroundColor.
  /// - **Painting Style:** Migrates [DB.displaySettings] to use Flutters [PaintingStyle] enum instead of an int representation.
  /// - **Piece Width:** Migrates [DB.displaySettings] to use a more direct piece width representation so no further calculation is needed.
  /// - **Font Size:** Migrates [DB.displaySettings] store a font scale factor instead of the absolute size.
  static Future<void> _migrateFromV1() async {
    assert(_currentVersion! <= 1);

    final _generalSettings = DB().generalSettings;
    DB().generalSettings = _generalSettings.copyWith(
      algorithm: Algorithms.values[_generalSettings.oldAlgorithm],
    );

    final _displaySettings = DB().displaySettings;
    DB().displaySettings = _displaySettings.copyWith(
      pointStyle: (_displaySettings.oldPointStyle != 0)
          ? PaintingStyle.values[_displaySettings.oldPointStyle - 1]
          : null,
      pieceWidth: _displaySettings.pieceWidth / MigrationValues.pieceWidth,
      fontScale: _displaySettings.fontScale / MigrationValues.fontScale,
    );

    final _colorSettings = DB().colorSettings;
    DB().colorSettings = _colorSettings.copyWith(
      drawerColor: Color.lerp(
        _colorSettings.drawerColor,
        _colorSettings.drawerBackgroundColor,
        0.5,
      )?.withAlpha(0xFF),
    );

    logger.v("$_tag Migrated from v1");
  }
}

/// Database KV Migration
///
/// This class provides helper methods to migrate from the old KV database to the new hiveDB.
class _DatabaseV1 {
  const _DatabaseV1._();

  static const _tag = "[KV store Migration]";

  static Future<File?> _getFile() async {
    final fileName = Constants.settingsFilename;
    final docDir = await getApplicationDocumentsDirectory();

    final file = File("${docDir.path}/$fileName");
    if (await file.exists()) {
      return file;
    }
  }

  /// Checks whether the current DB is still the old KV store by checking the availability of the json file
  static Future<bool> get usesV1 async {
    final file = await _getFile();
    logger.i("$_tag still uses v1: ${file != null}");
    return file != null;
  }

  /// Loads the generalSettings from the old data store
  static Future<Map<String, dynamic>?> _loadFile(File _file) async {
    assert(await usesV1);
    logger.v("$_tag Loading $_file ...");

    try {
      final contents = await _file.readAsString();
      final _values = jsonDecode(contents) as Map<String, dynamic>?;
      logger.v(_values.toString());
      return _values;
    } catch (e) {
      logger.e("$_tag error loading file $e");
    }
  }

  /// Migrates the deprecated Settings to the new [LocalDatabaseService]
  /// TODO: it won't do anything if the
  static Future<void> migrateDB() async {
    logger.i("$_tag migrate from KV to DB");
    final _file = await _getFile();
    assert(_file != null);

    final _json = await _loadFile(_file!);
    if (_json != null) {
      DB().generalSettings = GeneralSettings.fromJson(_json);
      DB().ruleSettings = RuleSettings.fromJson(_json);
      DB().displaySettings = DisplaySettings.fromJson(_json);
      DB().colorSettings = ColorSettings.fromJson(_json);
    }
    await _deleteFile(_file);
  }

  /// Deletes the old settings file
  static Future<void> _deleteFile(File _file) async {
    assert(await usesV1);
    logger.v("$_tag Deleting old settings file...");

    await _file.delete();
    logger.i("$_tag $_file Deleted");
  }
}
