// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// database.dart

import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart'
    show ValueListenable, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart' show Color, Locale;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/models/display_settings.dart';
import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../statistics/model/stats_settings.dart';
import '../config/constants.dart';
import '../services/logger.dart';
import 'adapters/adapters.dart';

part 'database_migration.dart';

typedef DB = Database;

/// Helpers to handle local data database.
///
/// The DB act's as a singe source of truth and therefore will be consistent across calls.
class Database {
  /// Gets the current DB instance.
  ///
  /// If it hasn't been set yet a new one will be created. The given [locale] is only used to set the initial rules.
  factory Database([Locale? locale]) => instance ??= Database._(locale);

  /// Internal constructor used to create the instance.
  Database._([this.locale]);

  @visibleForTesting
  static Database? instance;

  /// Locale to set the initial [RuleSettings].
  final Locale? locale;

  /// [GeneralSettings] Box reference
  static late final Box<GeneralSettings> _generalSettingsBox;

  /// Key at which the [GeneralSettings] will be saved in the [_generalSettingsBox]
  static const String generalSettingsKey = "settings";

  /// Key at which the [_generalSettingsBox] will be saved
  static const String _generalSettingsBoxName = "generalSettings";

  /// [RuleSettings] Box reference
  static late final Box<RuleSettings> _ruleSettingsBox;

  /// Key at which the [RuleSettings] will be saved in the [_ruleSettingsBox]
  static const String ruleSettingsKey = "settings";

  /// Key at which the [_ruleSettingsBox] will be saved
  static const String _ruleSettingsBoxName = "ruleSettings";

  /// [DisplaySettings] Box reference
  static late final Box<DisplaySettings> _displaySettingsBox;

  /// Key at which the [DisplaySettings] will be saved in the [_displaySettingsBox]
  static const String displaySettingsKey = "settings";

  /// Key at which the [_displaySettingsBox] will be saved
  static const String _displaySettingsBoxName = "displaySettings";

  /// [ColorSettings] Box reference
  static late final Box<ColorSettings> _colorSettingsBox;

  /// Key at which the [ColorSettings] will be saved in the [_colorSettingsBox]
  static const String colorSettingsKey = "settings";

  /// Key at which the [_colorSettingsBox] will be saved
  static const String _colorSettingsBoxName = "colorSettings";

  /// Database boxes to store custom themes
  static late final Box<dynamic> _customThemesBox;
  static const String _customThemesBoxName = "customThemes";
  static const String customThemesKey = "customThemes";

  /// [StatsSettings] Box reference
  static late final Box<StatsSettings> _statsSettingsBox;

  /// Key at which the [StatsSettings] will be saved in the [_statsSettingsBox]
  static const String statsSettingsKey = "settings";

  /// Key at which the [_statsSettingsBox] will be saved
  static const String _statsSettingsBoxName = "statsSettings";

  /// Initializes the local database
  static Future<void> init() async {
    await Hive.initFlutter("Sanmill");

    await _initGeneralSettings();
    await _initRuleSettings();
    await _initDisplaySettings();
    await _initColorSettings();
    await _initCustomThemes();
    await _initStatsSettings();

    if (await _DatabaseMigration.migrate() == true) {
      DB().generalSettings = DB().generalSettings.copyWith(firstRun: false);
    }
  }

  /// Resets the database
  static Future<void> reset() async {
    await _generalSettingsBox.delete(generalSettingsKey);
    await _ruleSettingsBox.delete(ruleSettingsKey);
    await _colorSettingsBox.delete(colorSettingsKey);
    await _displaySettingsBox.delete(displaySettingsKey);
    await _customThemesBox.delete(customThemesKey);
    await _statsSettingsBox.delete(statsSettingsKey);
  }

  /// GeneralSettings

  /// Initializes the [GeneralSettings] reference
  static Future<void> _initGeneralSettings() async {
    Hive.registerAdapter<SearchAlgorithm>(SearchAlgorithmAdapter());
    Hive.registerAdapter<SoundTheme>(SoundThemeAdapter());
    Hive.registerAdapter<LlmProvider>(LlmProviderAdapter());
    Hive.registerAdapter<GeneralSettings>(GeneralSettingsAdapter());
    _generalSettingsBox =
        await Hive.openBox<GeneralSettings>(_generalSettingsBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings =>
      _generalSettingsBox.listenable(keys: <String>[generalSettingsKey]);

  /// Saves the given [generalSettings] to the settings Box
  set generalSettings(GeneralSettings generalSettings) {
    _generalSettingsBox.put(generalSettingsKey, generalSettings);
    GameController().engine.setGeneralOptions();
  }

  /// Gets the given [GeneralSettings] from the settings Box
  GeneralSettings get generalSettings =>
      _generalSettingsBox.get(generalSettingsKey) ?? const GeneralSettings();

  /// RuleSettings

  /// Initializes the [RuleSettings] reference
  static Future<void> _initRuleSettings() async {
    Hive.registerAdapter<MillFormationActionInPlacingPhase>(
        MillFormationActionInPlacingPhaseAdapter());
    Hive.registerAdapter<BoardFullAction>(BoardFullActionAdapter());
    Hive.registerAdapter<StalemateAction>(StalemateActionAdapter());
    Hive.registerAdapter<RuleSettings>(RuleSettingsAdapter());
    _ruleSettingsBox = await Hive.openBox<RuleSettings>(_ruleSettingsBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<RuleSettings>> get listenRuleSettings =>
      _ruleSettingsBox.listenable(keys: <String>[ruleSettingsKey]);

  /// Saves the given [ruleSettings] to the settings Box
  set _ruleSettings(RuleSettings? ruleSettings) {
    if (ruleSettings != null) {
      _ruleSettingsBox.put(ruleSettingsKey, ruleSettings);
      GameController().engine.setRuleOptions();
    }
  }

  /// Gets the given [RuleSettings] from the settings Box
  RuleSettings? get _ruleSettings => _ruleSettingsBox.get(ruleSettingsKey);

  /// Saves the given [ruleSettings] to the settings Box
  set ruleSettings(RuleSettings ruleSettings) => _ruleSettings = ruleSettings;

  /// Gets the given [RuleSettings] from the settings Box
  ///
  /// If no Rule Settings have been saved yet it will Initializes
  /// the box with the rule settings corresponding to it's [locale].
  /// This means that the first call will save the ruleSettings object for the lifespan of the DB.
  /// Later changes to the locale won't result in changes.
  RuleSettings get ruleSettings =>
      _ruleSettings ??= RuleSettings.fromLocale(locale);

  /// DisplaySettings

  /// Initializes the [DisplaySettings] reference
  static Future<void> _initDisplaySettings() async {
    Hive.registerAdapter<Locale?>(LocaleAdapter());
    Hive.registerAdapter<PointPaintingStyle>(PointPaintingStyleAdapter());
    Hive.registerAdapter<MovesViewLayout>(MovesViewLayoutAdapter());
    Hive.registerAdapter<DisplaySettings>(DisplaySettingsAdapter());
    _displaySettingsBox =
        await Hive.openBox<DisplaySettings>(_displaySettingsBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings =>
      _displaySettingsBox.listenable(keys: <String>[displaySettingsKey]);

  /// Saves the given [displaySettings] to the settings Box
  set displaySettings(DisplaySettings displaySettings) =>
      _displaySettingsBox.put(displaySettingsKey, displaySettings);

  /// Gets the given [DisplaySettings] from the settings Box
  DisplaySettings get displaySettings =>
      _displaySettingsBox.get(displaySettingsKey) ?? const DisplaySettings();

  /// ColorSettings
  static Future<void> _initColorSettings() async {
    Hive.registerAdapter<Color>(ColorAdapter());
    Hive.registerAdapter<ColorSettings>(ColorSettingsAdapter());

    try {
      _colorSettingsBox =
          await Hive.openBox<ColorSettings>(_colorSettingsBoxName);
    } catch (e) {
      logger.e('Initialization failed: $e');
      // If the initialization fails, try to delete and recreate the box
      await _deleteAndRecreateColorSettingsBox();
    }
  }

  static Future<void> _deleteAndRecreateColorSettingsBox() async {
    try {
      // Close the box if it is open
      if (Hive.isBoxOpen(_colorSettingsBoxName)) {
        final Box<ColorSettings> box =
            Hive.box<ColorSettings>(_colorSettingsBoxName);
        await box.close();
        logger.i('Box closed successfully.');
      }
      // Wait for the file system to release all handles
      await Future<void>.delayed(const Duration(seconds: 1));

      // Delete the box from disk
      await Hive.deleteBoxFromDisk(_colorSettingsBoxName);
      logger.i('Box deleted from disk.');

      // Wait before recreating the box
      await Future<void>.delayed(const Duration(seconds: 1));

      // Recreate the box
      _colorSettingsBox =
          await Hive.openBox<ColorSettings>(_colorSettingsBoxName);
      logger.i('Box has been recreated successfully.');
    } catch (e) {
      logger.e('Failed to delete or recreate box: $e');
    }
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<ColorSettings>> get listenColorSettings =>
      _colorSettingsBox.listenable(keys: <String>[colorSettingsKey]);

  /// Saves the given [colorSettings] to the settings Box
  set colorSettings(ColorSettings colorSettings) =>
      _colorSettingsBox.put(colorSettingsKey, colorSettings);

  /// Gets the given [ColorSettings] from the settings Box
  ColorSettings get colorSettings =>
      _colorSettingsBox.get(colorSettingsKey) ?? const ColorSettings();

  /// Initialize custom themes box
  static Future<void> _initCustomThemes() async {
    _customThemesBox = await Hive.openBox<dynamic>(_customThemesBoxName);
  }

  /// Get stored custom themes
  List<ColorSettings> get customThemes {
    final dynamic rawData = _customThemesBox.get(customThemesKey);

    if (rawData == null) {
      return <ColorSettings>[];
    }

    // Convert List<dynamic> to List<ColorSettings>
    if (rawData is List) {
      return rawData.map<ColorSettings>((dynamic item) {
        if (item is ColorSettings) {
          return item;
        } else {
          return const ColorSettings();
        }
      }).toList();
    }

    return <ColorSettings>[];
  }

  /// Save custom themes list
  set customThemes(List<ColorSettings> themes) {
    _customThemesBox.put(customThemesKey, themes);
  }

  /// StatsSettings

  /// Initializes the [StatsSettings] reference
  static Future<void> _initStatsSettings() async {
    Hive.registerAdapter<PlayerStats>(PlayerStatsAdapter());
    Hive.registerAdapter<StatsSettings>(StatsSettingsAdapter());
    _statsSettingsBox =
        await Hive.openBox<StatsSettings>(_statsSettingsBoxName);
  }

  /// Listens to changes inside the StatsSettings Box
  ValueListenable<Box<StatsSettings>> get listenStatsSettings =>
      _statsSettingsBox.listenable(keys: <String>[statsSettingsKey]);

  /// Saves the given [settings] to the StatsSettings Box
  set statsSettings(StatsSettings settings) =>
      _statsSettingsBox.put(statsSettingsKey, settings);

  /// Gets the stored [StatsSettings] or returns a default value
  StatsSettings get statsSettings =>
      _statsSettingsBox.get(statsSettingsKey) ?? const StatsSettings();
}
