// Copyright 2021 Leptopoda. All rights reserved.
// Use of this source code is governed by an APACHE-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;
import 'package:flutter/material.dart' show Color, Locale;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sanmill/models/color.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/models/rules.dart';
import 'package:sanmill/services/storage/adapters/color_adapter.dart';
import 'package:sanmill/services/storage/adapters/locale_adapter.dart';

/// Helpers to handle local data storage
class LocalDatabaseService {
  const LocalDatabaseService._();

  /// [ColorSettings] box reference
  static late Box<ColorSettings> _colorSettingsBox;

  /// key at wich the [ColorSettings] will be saved in the [_colorSettingsBox]
  static const String _colorSettingsKey = 'settings';

  /// key at wich the [_colorSettingsBox] will be saved
  static const String _colorSettingsBoxName = 'colors';

  /// [Display] box reference
  static late Box<Display> _displayBox;

  /// key at wich the [Display] will be saved in the [_displayBox]
  static const String _displayKey = 'settings';

  /// key at wich the [_displayBox] will be saved
  static const String _displayBoxName = 'display';

  /// [Preferences] box reference
  static late Box<Preferences> _preferencesBox;

  /// key at wich the [Preferences] will be saved in the [_preferencesBox]
  static const String _preferencesKey = 'settings';

  /// key at wich the [_preferencesBox] will be saved
  static const String _preferencesBoxName = 'preferences';

  /// [Rules] box reference
  static late Box<Rules> _rulesBox;

  /// key at wich the [Rules] will be saved in the [_rulesBox]
  static const String _rulesKey = 'settings';

  /// key at wich the [_rulesBox] will be saved
  static const String _rulesBoxName = 'rules';

  /// initializes the local storage
  static Future<void> initStorage() async {
    if (!kIsWeb) await Hive.initFlutter('Sanmill');
    await _initColorSettings();
    await _initDisplay();
    await _initPreferences();
    await _initRules();
  }

  /// initilizes the [ColorSettings] reference
  static Future<void> _initColorSettings() async {
    Hive.registerAdapter<ColorSettings>(ColorSettingsAdapter());
    Hive.registerAdapter<Color>(ColorAdapter());
    _colorSettingsBox =
        await Hive.openBox<ColorSettings>(_colorSettingsBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<ColorSettings>> get listenColorSettings =>
      _colorSettingsBox.listenable(keys: [_colorSettingsKey]);

  /// saves the given [settings] to the settings Box
  static set colorSettings(ColorSettings settings) =>
      _colorSettingsBox.put(_colorSettingsKey, settings);

  /// gets the given [ColorSettings] from the settings Box
  static ColorSettings get colorSettings =>
      _colorSettingsBox.get(_colorSettingsKey) ?? ColorSettings();

  /// initilizes the [Display] reference
  static Future<void> _initDisplay() async {
    Hive.registerAdapter<Display>(DisplayAdapter());
    _displayBox = await Hive.openBox<Display>(_displayBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Display>> get listenDisplay =>
      _displayBox.listenable(keys: [_displayKey]);

  /// saves the given [settings] to the settings Box
  static set display(Display settings) =>
      _displayBox.put(_displayKey, settings);

  /// gets the given [Display] from the settings Box
  static Display get display => _displayBox.get(_displayKey) ?? Display();

  /// initilizes the [Preferences] reference
  static Future<void> _initPreferences() async {
    Hive.registerAdapter<Preferences>(PreferencesAdapter());
    Hive.registerAdapter<Locale>(LocaleAdapter());
    _preferencesBox = await Hive.openBox<Preferences>(_preferencesBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Preferences>> get listenPreferences =>
      _preferencesBox.listenable(keys: [_preferencesKey]);

  /// saves the given [settings] to the settings Box
  static set preferences(Preferences settings) =>
      _preferencesBox.put(_preferencesKey, settings);

  /// gets the given [Preferences] from the settings Box
  static Preferences get preferences =>
      _preferencesBox.get(_preferencesKey) ?? Preferences();

  /// initilizes the [Rules] reference
  static Future<void> _initRules() async {
    Hive.registerAdapter<Rules>(RulesAdapter());
    _rulesBox = await Hive.openBox<Rules>(_rulesBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Rules>> get listenRules =>
      _rulesBox.listenable(keys: [_rulesKey]);

  /// saves the given [settings] to the settings Box
  static set rules(Rules settings) => _rulesBox.put(_rulesKey, settings);

  /// gets the given [Rules] from the settings Box
  static Rules get rules => _rulesBox.get(_rulesKey) ?? Rules();
}
