// ignore_for_file: deprecated_member_use_from_same_package

// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

part of 'database.dart';

/// Database Migration
///
/// This class provides helper methods to migrate database versions.
class _DatabaseMigration {
  const _DatabaseMigration._();

  static const String _logTag = "[Database Migration]";

  /// The newest DB version.
  static const int _newVersion = 2;

  /// The current DB version.
  /// It will get initialized by [migrate] with the saved value.
  static late int? _currentVersion;

  /// The list of migrations
  static const List<Future<void> Function()> _migrations =
      <Future<void> Function()>[
    _migrateToHive,
    _migrateFromV1,
  ];

  /// Database Box reference
  // ignore: always_specify_types
  static late Box<dynamic> _databaseBox;

  /// Key at which the [_databaseBox] will be saved
  static const String _databaseBoxName = "database";

  /// Key at which the database info will be saved in the [_databaseBox]
  static const String _versionKey = "version";

  /// Migrates the database version to the [_newVersion].
  ///
  /// When [_currentVersion] is smaller than [_newVersion] all migrations between will be run.
  /// Migrations are called once and only once thus they should complete fast and everything should be awaited.
  static Future<bool> migrate() async {
    if (kIsWeb || Platform.isMacOS) {
      return false;
    }

    assert(_migrations.length == _newVersion);

    bool migrated = false;

    _databaseBox = await Hive.openBox(_databaseBoxName);

    _currentVersion = _databaseBox.get(_versionKey) as int?;

    if (_currentVersion == null) {
      if (await _DatabaseV1.usesV1) {
        _currentVersion = 0;
      } else if (DB().generalSettings.usesHiveDB) {
        _currentVersion = 1;
      }
      logger.v("$_logTag: Current version is $_currentVersion");

      if (_currentVersion != null) {
        for (int i = _currentVersion!; i < _newVersion; i++) {
          await _migrations[i].call();
        }

        migrated = true;
      }
    }

    await _migrateFromDeprecation();

    await _databaseBox.put(_versionKey, _newVersion);
    _databaseBox.close();

    return migrated;
  }

  /// Migration 0 - KV to Hive
  ///
  /// - Calls the [_DatabaseV1.migrateDB] to migrate from KV database.
  static Future<void> _migrateToHive() async {
    assert(_currentVersion! <= 0);

    await _DatabaseV1.migrateDB();
    logger.i("$_logTag Migrated from KV to DB");
  }

  /// Migration 1 - Sanmill version 1.x.x
  ///
  /// - **Algorithm to enum:** Migrates [DB.generalSettings] to use the new Algorithm enum instead of an int representation.
  /// - **Drawer background color:** Migrates [DB.colorSettings] to merge the drawerBackgroundColor and drawerColor.
  /// This reflects the deprecation of drawerBackgroundColor.
  /// - **Painting Style:** Migrates [DB.displaySettings] to use [PointPaintingStyle] enum instead of an int representation.
  /// - **Piece Width:** Migrates [DB.displaySettings] to use a more direct piece width representation so no further calculation is needed.
  /// - **Font Size:** Migrates [DB.displaySettings] store a font scale factor instead of the absolute size.
  static Future<void> _migrateFromV1() async {
    assert(_currentVersion! <= 1);

    final GeneralSettings generalSettings = DB().generalSettings;
    DB().generalSettings = generalSettings.copyWith(
      searchAlgorithm: SearchAlgorithm.values[generalSettings.algorithm],
    );

    final DisplaySettings displaySettings = DB().displaySettings;
    DB().displaySettings = displaySettings.copyWith(
      locale: DB().displaySettings.languageCode == "Default"
          ? null
          : Locale(DB().displaySettings.languageCode),
      pointPaintingStyle: PointPaintingStyle.values[displaySettings.pointStyle],
      fontScale: displaySettings.fontSize / 16,
    );

    final ColorSettings colorSettings = DB().colorSettings;
    DB().colorSettings = colorSettings.copyWith(
      drawerColor: Color.lerp(
        colorSettings.drawerColor,
        colorSettings.drawerBackgroundColor,
        0.5,
      )?.withAlpha(0xFF),
    );

    logger.v("$_logTag Migrated from v1");
  }

  /// Migration  - Sanmill version 3.3.2+
  /// If the deprecated setting item is not the default value,
  /// execute the migration operation and set the deprecated setting item
  /// to the default value.
  static Future<void> _migrateFromDeprecation() async {
    // Migrates isWhiteLoseButNotDrawWhenBoardFull to boardFullAction
    if (DB().ruleSettings.isWhiteLoseButNotDrawWhenBoardFull == false) {
      DB().ruleSettings = DB().ruleSettings.copyWith(
            boardFullAction: BoardFullAction.agreeToDraw,
          );
      DB().ruleSettings = DB().ruleSettings.copyWith(
            isWhiteLoseButNotDrawWhenBoardFull: true,
          );
    }

    // Migrates isLoseButNotChangeSideWhenNoWay to stalemateAction
    if (DB().ruleSettings.isLoseButNotChangeSideWhenNoWay == false) {
      DB().ruleSettings = DB().ruleSettings.copyWith(
            stalemateAction: StalemateAction.changeSideToMove,
          );
      DB().ruleSettings = DB().ruleSettings.copyWith(
            isLoseButNotChangeSideWhenNoWay: true,
          );
    }

    logger.v("$_logTag Migrated from deprecation");
  }
}

/// Database KV Migration
///
/// This class provides helper methods to migrate from the old KV database to the new hiveDB.
class _DatabaseV1 {
  const _DatabaseV1._();

  static const String _logTag = "[KV store Migration]";

  static Future<File?> _getFile() async {
    final String fileName = Constants.settingsFile;
    final Directory docDir = await getApplicationDocumentsDirectory();

    final File file = File("${docDir.path}/$fileName");
    // ignore: avoid_slow_async_io
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Checks whether the current DB is still the old KV store by checking the availability of the json file
  static Future<bool> get usesV1 async {
    final File? file = await _getFile();
    logger.i("$_logTag still uses v1: ${file != null}");
    return file != null;
  }

  /// Loads the generalSettings from the old data store
  static Future<Map<String, dynamic>?> _loadFile(File file) async {
    assert(await usesV1);
    logger.v("$_logTag Loading $file ...");

    try {
      final String contents = await file.readAsString();
      final Map<String, dynamic>? values =
          jsonDecode(contents) as Map<String, dynamic>?;
      logger.v(values.toString());
      return values;
    } catch (e) {
      logger.e("$_logTag error loading file $e");
    }
    return null;
  }

  /// Migrates the deprecated Settings to the new [LocalDatabaseService]
  /// TODO: it won't do anything if the
  static Future<void> migrateDB() async {
    logger.i("$_logTag migrate from KV to DB");
    final File? file = await _getFile();
    assert(file != null);

    final Map<String, dynamic>? json = await _loadFile(file!);
    if (json != null) {
      DB().generalSettings = GeneralSettings.fromJson(json);
      DB().ruleSettings = RuleSettings.fromJson(json);
      DB().displaySettings = DisplaySettings.fromJson(json);
      DB().colorSettings = ColorSettings.fromJson(json);
    }
    await _deleteFile(file);
  }

  /// Deletes the old settings file
  static Future<void> _deleteFile(File file) async {
    assert(await usesV1);
    logger.v("$_logTag Deleting old settings file...");

    await file.delete();
    logger.i("$_logTag $file Deleted");
  }
}
