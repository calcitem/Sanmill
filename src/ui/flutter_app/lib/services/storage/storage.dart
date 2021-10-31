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
import 'package:sanmill/services/storage/storage_v1.dart';

/// Helpers to handle local data storage
class LocalDatabaseService {
  const LocalDatabaseService._();

  /// [ColorSettings] box reference
  static late Box<ColorSettings> _colorSettingsBox;

  /// key at which the [ColorSettings] will be saved in the [_colorSettingsBox]
  static const String colorSettingsKey = 'settings';

  /// key at which the [_colorSettingsBox] will be saved
  static const String _colorSettingsBoxName = 'colors';

  /// [Display] box reference
  static late Box<Display> _displayBox;

  /// key at which the [Display] will be saved in the [_displayBox]
  static const String displayKey = 'settings';

  /// key at which the [_displayBox] will be saved
  static const String _displayBoxName = 'display';

  /// [Preferences] box reference
  static late Box<Preferences> _preferencesBox;

  /// key at which the [Preferences] will be saved in the [_preferencesBox]
  static const String preferencesKey = 'settings';

  /// key at which the [_preferencesBox] will be saved
  static const String _preferencesBoxName = 'preferences';

  /// [Rules] box reference
  static late Box<Rules> _rulesBox;

  /// key at which the [Rules] will be saved in the [_rulesBox]
  static const String rulesKey = 'settings';

  /// key at which the [_rulesBox] will be saved
  static const String _rulesBoxName = 'rules';

  /// initializes the local storage
  static Future<void> initStorage() async {
    if (!kIsWeb) await Hive.initFlutter('Sanmill');
    await _initColorSettings();
    await _initDisplay();
    await _initPreferences();
    await _initRules();
    DatabaseV1.initRules();
  }

  /// resets the storage
  static Future<void> resetStorage() async {
    await _colorSettingsBox.delete(colorSettingsKey);
    await _displayBox.delete(displayKey);
    await _preferencesBox.delete(preferencesKey);
    await _rulesBox.delete(rulesKey);
  }

  /// initialize the [ColorSettings] reference
  static Future<void> _initColorSettings() async {
    Hive.registerAdapter<Color>(ColorAdapter());
    Hive.registerAdapter<ColorSettings>(ColorSettingsAdapter());
    _colorSettingsBox =
        await Hive.openBox<ColorSettings>(_colorSettingsBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<ColorSettings>> get listenColorSettings =>
      _colorSettingsBox.listenable(keys: [colorSettingsKey]);

  /// saves the given [colors] to the settings Box
  static set colorSettings(ColorSettings colors) =>
      _colorSettingsBox.put(colorSettingsKey, colors);

  /// gets the given [ColorSettings] from the settings Box
  static ColorSettings get colorSettings =>
      _colorSettingsBox.get(colorSettingsKey) ?? ColorSettings();

  /// initialize the [Display] reference
  static Future<void> _initDisplay() async {
    Hive.registerAdapter<Locale?>(LocaleAdapter());
    Hive.registerAdapter<Display>(DisplayAdapter());
    _displayBox = await Hive.openBox<Display>(_displayBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Display>> get listenDisplay =>
      _displayBox.listenable(keys: [displayKey]);

  /// saves the given [display] to the settings Box
  static set display(Display display) => _displayBox.put(displayKey, display);

  /// gets the given [Display] from the settings Box
  static Display get display => _displayBox.get(displayKey) ?? Display();

  /// initialize the [Preferences] reference
  static Future<void> _initPreferences() async {
    Hive.registerAdapter<Preferences>(PreferencesAdapter());
    _preferencesBox = await Hive.openBox<Preferences>(_preferencesBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Preferences>> get listenPreferences =>
      _preferencesBox.listenable(keys: [preferencesKey]);

  /// saves the given [settings] to the settings Box
  static set preferences(Preferences settings) =>
      _preferencesBox.put(preferencesKey, settings);

  /// gets the given [Preferences] from the settings Box
  static Preferences get preferences =>
      _preferencesBox.get(preferencesKey) ?? const Preferences();

  /// initialize the [Rules] reference
  static Future<void> _initRules() async {
    Hive.registerAdapter<Rules>(RulesAdapter());
    _rulesBox = await Hive.openBox<Rules>(_rulesBoxName);
  }

  /// listens to changes inside the settings Box
  static ValueListenable<Box<Rules>> get listenRules =>
      _rulesBox.listenable(keys: [rulesKey]);

  /// saves the given [rules] to the settings Box
  static set rules(Rules rules) {
    _rulesBox.put(rulesKey, rules);
    DatabaseV1.initRules();
  }

  /// gets the given [Rules] from the settings Box
  static Rules get rules => _rulesBox.get(rulesKey) ?? Rules();
}
