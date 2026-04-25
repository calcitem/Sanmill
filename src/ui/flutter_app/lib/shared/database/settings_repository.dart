// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/models/display_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import 'database.dart';

/// Repository boundary for user-facing settings.
///
/// The legacy implementation delegates to [Database], preserving all current
/// Hive box names, migrations, and setter side effects.
abstract class SettingsRepository {
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings;
  GeneralSettings get generalSettings;
  set generalSettings(GeneralSettings value);

  ValueListenable<Box<RuleSettings>> get listenRuleSettings;
  RuleSettings get ruleSettings;
  set ruleSettings(RuleSettings value);

  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings;
  DisplaySettings get displaySettings;
  set displaySettings(DisplaySettings value);

  ValueListenable<Box<ColorSettings>> get listenColorSettings;
  ColorSettings get colorSettings;
  set colorSettings(ColorSettings value);
}

class DatabaseSettingsRepository implements SettingsRepository {
  DatabaseSettingsRepository(this._db);

  final Database _db;

  @override
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings =>
      _db.listenGeneralSettings;

  @override
  GeneralSettings get generalSettings => _db.generalSettings;

  @override
  set generalSettings(GeneralSettings value) => _db.generalSettings = value;

  @override
  ValueListenable<Box<RuleSettings>> get listenRuleSettings =>
      _db.listenRuleSettings;

  @override
  RuleSettings get ruleSettings => _db.ruleSettings;

  @override
  set ruleSettings(RuleSettings value) => _db.ruleSettings = value;

  @override
  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings =>
      _db.listenDisplaySettings;

  @override
  DisplaySettings get displaySettings => _db.displaySettings;

  @override
  set displaySettings(DisplaySettings value) => _db.displaySettings = value;

  @override
  ValueListenable<Box<ColorSettings>> get listenColorSettings =>
      _db.listenColorSettings;

  @override
  ColorSettings get colorSettings => _db.colorSettings;

  @override
  set colorSettings(ColorSettings value) => _db.colorSettings = value;
}
