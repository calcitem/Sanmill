// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
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

import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show ValueListenable, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart' show Color, Locale, PaintingStyle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/models/general_settings.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/storage/adapters/adapters.dart';
import 'package:sanmill/shared/constants.dart';

part 'package:sanmill/services/storage/storage_migration.dart';

/// Helpers to handle local data storage.
///
/// The DB act's as a singe source of truth and therefore will be consistent across calls.
class DB {
  @visibleForTesting
  static DB? instance;

  /// Gets the current DB instance.
  ///
  /// If it hasn't been set yet a new one will be created. The given [locale] is only used to set the initial rules.
  factory DB([Locale? locale]) => instance ??= DB._(locale);

  /// Locale to set the initial [Rules].
  final Locale? locale;

  /// Internal constructor used to create the instance.
  DB._([this.locale]);

  /// [ColorSettings] box reference
  static late final Box<ColorSettings> _colorSettingsBox;

  /// Key at wich the [ColorSettings] will be saved in the [_colorSettingsBox]
  static const String colorSettingsKey = "settings";

  /// Key at wich the [_colorSettingsBox] will be saved
  static const String _colorSettingsBoxName = "colors";

  /// [Display] box reference
  static late final Box<Display> _displayBox;

  /// Key at wich the [Display] will be saved in the [_displayBox]
  static const String displayKey = "settings";

  /// Key at wich the [_displayBox] will be saved
  static const String _displayBoxName = "display";

  /// [GeneralSettings] box reference
  static late final Box<GeneralSettings> _generalSettingsBox;

  /// Key at wich the [GeneralSettings] will be saved in the [_generalSettingsBox]
  static const String generalSettingsKey = "settings";

  /// Key at wich the [_generalSettingsBox] will be saved
  static const String _generalSettingsBoxName = "generalSettings";

  /// [Rules] box reference
  static late final Box<Rules> _rulesBox;

  /// Key at wich the [Rules] will be saved in the [_rulesBox]
  static const String rulesKey = "settings";

  /// Key at wich the [_rulesBox] will be saved
  static const String _rulesBoxName = "rules";

  /// Initializes the local storage
  static Future<void> initStorage() async {
    if (!kIsWeb) await Hive.initFlutter("Sanmill");
    await _initColorSettings();
    await _initDisplay();
    await _initGeneralSettings();
    await _initRules();
    await _DatabaseMigrator.migrate();
  }

  /// resets the storage
  static Future<void> resetStorage() async {
    await _colorSettingsBox.delete(colorSettingsKey);
    await _displayBox.delete(displayKey);
    await _generalSettingsBox.delete(generalSettingsKey);
    await _rulesBox.delete(rulesKey);
  }

  /// Initializes the [ColorSettings] reference
  static Future<void> _initColorSettings() async {
    Hive.registerAdapter<Color>(ColorAdapter());
    Hive.registerAdapter<ColorSettings>(ColorSettingsAdapter());
    _colorSettingsBox =
        await Hive.openBox<ColorSettings>(_colorSettingsBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<ColorSettings>> get listenColorSettings =>
      _colorSettingsBox.listenable(keys: [colorSettingsKey]);

  /// Saves the given [colors] to the settings Box
  set colorSettings(ColorSettings colors) =>
      _colorSettingsBox.put(colorSettingsKey, colors);

  /// Gets the given [ColorSettings] from the settings Box
  ColorSettings get colorSettings =>
      _colorSettingsBox.get(colorSettingsKey) ?? const ColorSettings();

  /// Initializes the [Display] reference
  static Future<void> _initDisplay() async {
    Hive.registerAdapter<Locale?>(LocaleAdapter());
    Hive.registerAdapter<PaintingStyle?>(PaintingStyleAdapter());
    Hive.registerAdapter<Display>(DisplayAdapter());
    _displayBox = await Hive.openBox<Display>(_displayBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<Display>> get listenDisplay =>
      _displayBox.listenable(keys: [displayKey]);

  /// Saves the given [display] to the settings Box
  set display(Display display) => _displayBox.put(displayKey, display);

  /// Gets the given [Display] from the settings Box
  Display get display => _displayBox.get(displayKey) ?? const Display();

  /// Initializes the [GeneralSettings] reference
  static Future<void> _initGeneralSettings() async {
    Hive.registerAdapter<GeneralSettings>(GeneralSettingsAdapter());
    Hive.registerAdapter<Algorithms>(AlgorithmsAdapter());
    _generalSettingsBox =
        await Hive.openBox<GeneralSettings>(_generalSettingsBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings =>
      _generalSettingsBox.listenable(keys: [generalSettingsKey]);

  /// Saves the given [settings] to the settings Box
  set generalSettings(GeneralSettings settings) =>
      _generalSettingsBox.put(generalSettingsKey, settings);

  /// Gets the given [GeneralSettings] from the settings Box
  GeneralSettings get generalSettings =>
      _generalSettingsBox.get(generalSettingsKey) ?? const GeneralSettings();

  /// Initializes the [Rules] reference
  static Future<void> _initRules() async {
    Hive.registerAdapter<Rules>(RulesAdapter());
    _rulesBox = await Hive.openBox<Rules>(_rulesBoxName);
  }

  /// Listens to changes inside the settings Box
  ValueListenable<Box<Rules>> get listenRules =>
      _rulesBox.listenable(keys: [rulesKey]);

  /// Saves the given [rules] to the settings Box
  set rules(Rules rules) => _rules = rules;

  /// Gets the given [Rules] from the settings Box
  ///
  /// If no Rules have been saved yet it will Initializes
  /// the box with the rules corresponding to it's [locale].
  /// This means that the first call will save the rules object for the lifespan of the db.
  /// Later changes to the locale won't result in changes.
  Rules get rules => _rules ??= Rules.fromLocale(locale);

  /// Saves the given [rules] to the settings Box
  set _rules(Rules? rules) {
    if (rules != null) {
      _rulesBox.put(rulesKey, rules);
    }
  }

  /// Gets the given [Rules] from the settings Box
  Rules? get _rules => _rulesBox.get(rulesKey);
}
