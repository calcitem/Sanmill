// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// init_test_environment.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/logger.dart';

/// Initializes environment configurations and necessary dependencies for tests.
Future<void> initTestEnvironment() async {
  // Configure environment
  EnvironmentConfig.test = false;
  EnvironmentConfig.devMode = true;
  EnvironmentConfig.catcher = false;

  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize the database
  await DB.init();

  // Set up the database
  if (DB().generalSettings.showTutorial == true) {
    DB().generalSettings = DB().generalSettings.copyWith(showTutorial: false);
  }

  if (DB().generalSettings.firstRun == true) {
    DB().generalSettings = DB().generalSettings.copyWith(firstRun: false);
  }
}
