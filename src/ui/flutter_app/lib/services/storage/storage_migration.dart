// ignore_for_file: deprecated_member_use_from_same_package

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

part of 'package:sanmill/services/storage/storage.dart';

/// Database Migrator
///
/// This class provides helper methods to migrate database versions.
class _DatabaseMigrator {
  const _DatabaseMigrator._();

  static const _tag = "[Database Migration]";

  /// The newest DB version.
  static const _newVersion = 2;

  /// The current DB version.
  /// It will get initialized by [migrate] with the saved value.
  static late final int _currentVersion;

  /// The list of migrations
  static const _migrations = [
    _migrateToHive,
    _migrateFromV1,
  ];

  /// Database box reference
  static late Box _databaseBox;

  /// key at which the [_databaseBox] will be saved
  static const String _databaseBoxName = "database";

  /// key at which the database info will be saved in the [_databaseBox]
  static const String _versionKey = "version";

  /// Migrates the database version to the [_newVersion].
  ///
  /// When [_currentVersion] is smaller than [_newVersion] all migrations between will be run.
  /// Migrations are called once and only once thus they should complete fast and everything should be awaited.
  static Future<void> migrate() async {
    assert(_migrations.length == _newVersion);

    _databaseBox = await Hive.openBox(_databaseBoxName);

    _currentVersion = _databaseBox.get(
      _versionKey,
      defaultValue: (!LocalDatabaseService.preferences.usesHiveDB) ? 0 : 1,
    ) as int;

    for (int i = _currentVersion; i < _newVersion; i++) {
      await _migrations[i].call();
    }

    await _databaseBox.put(_versionKey, _newVersion);
    _databaseBox.close();
  }

  /// Migration 0 - KV to Hive
  ///
  /// - Calls the [_DatabaseV1.migrateDB] to migrate from KV storage.
  static Future<void> _migrateToHive() async {
    assert(_currentVersion <= 0);

    await _DatabaseV1.migrateDB();
    debugPrint("$_tag migrated from KV");
  }

  /// Migration 1 - Sanmill version 1.1.38+2196 - 2021-11-09
  ///
  /// - **Algorithm to enum:** Migrates [LocalDatabaseService.preferences] to use the new Algorithm enum instead of an int representation.
  /// - **Drawer background color:** Migrates [LocalDatabaseService.colorSettings] to merge the drawerBackgroundColor and drawerColor.
  /// This reflects the deprecation of drawerBackgroundColor.
  /// - **Painting STyle:**: Migrates [LocalDatabaseService.display] to use Flutters [PaintingStyle] enum instead of an int representation.
  static Future<void> _migrateFromV1() async {
    assert(_currentVersion <= 1);

    final _prefs = LocalDatabaseService.preferences;
    LocalDatabaseService.preferences = _prefs.copyWith(
      algorithm: Algorithms.values[_prefs.oldAlgorithm],
    );

    final _colorSettings = LocalDatabaseService.colorSettings;
    LocalDatabaseService.colorSettings = _colorSettings.copyWith(
      drawerColor: Color.lerp(
        _colorSettings.drawerColor,
        _colorSettings.drawerBackgroundColor,
        0.5,
      )?.withAlpha(0xFF),
    );

    final _display = LocalDatabaseService.display;
    if (_display.oldPointStyle != 0) {
      LocalDatabaseService.display = _display.copyWith(
        pointStyle: PaintingStyle.values[_display.oldPointStyle - 1],
      );
    }

    debugPrint("$_tag migrated from v1");
  }
}

/// Database KV Migrator
///
/// This class provides helper methods to migrate from the old KV storage to the new hiveDB.
class _DatabaseV1 {
  const _DatabaseV1._();

  static const _tag = "[KV store Migration]";

  static Future<File> _getFile() async {
    final fileName = Constants.settingsFilename;
    final docDir = await getApplicationDocumentsDirectory();

    return File("${docDir.path}/$fileName");
  }

  /// loads the preferences from the old data store
  static Future<Map<String, dynamic>?> _loadFile(File _file) async {
    debugPrint("$_tag Loading $_file ...");

    try {
      final contents = await _file.readAsString();
      final _values = jsonDecode(contents) as Map<String, dynamic>?;
      debugPrint(_values.toString());
      return _values;
    } catch (e) {
      debugPrint("$_tag error loading file $e");
    }
  }

  /// migrates the deprecated Settings to the new [LocalDatabaseService]
  static Future<void> migrateDB() async {
    debugPrint("$_tag migrate from KV");
    final _file = await _getFile();
    final _json = await _loadFile(_file);
    if (_json != null) {
      LocalDatabaseService.colorSettings = ColorSettings.fromJson(_json);
      LocalDatabaseService.display = Display.fromJson(_json);
      LocalDatabaseService.preferences = Preferences.fromJson(_json);
      LocalDatabaseService.rules = Rules.fromJson(_json);
    }
    await _deleteFile(_file);
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
}
