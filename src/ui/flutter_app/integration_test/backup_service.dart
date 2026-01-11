// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// backup_service.dart

import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import 'test_constants.dart';

/// Backs up the current database settings to memory.
Future<Map<String, dynamic>> backupDatabase() async {
  return <String, dynamic>{
    ruleSettingsKey: DB().ruleSettings,
    generalSettingsKey: DB().generalSettings,
  };
}

/// Restores the database settings from a backup.
Future<void> restoreDatabase(Map<String, dynamic> backup) async {
  DB().ruleSettings = backup[ruleSettingsKey] as RuleSettings;
  DB().generalSettings = backup[generalSettingsKey] as GeneralSettings;
}
