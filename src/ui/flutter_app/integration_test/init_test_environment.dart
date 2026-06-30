// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// init_test_environment.dart

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/games/built_in_game_modules.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/database/settings_repositories.dart';
import 'package:sanmill/shared/database/settings_side_effect_coordinator.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/logger.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

/// Whether the test environment has already been initialized.
bool _initialized = false;

/// Initializes environment configurations and necessary dependencies for tests.
///
/// This function is idempotent: calling it multiple times (e.g. from separate
/// test files that are all imported by comprehensive_test.dart) is safe and
/// will only perform initialization once.
Future<void> initTestEnvironment() async {
  if (_initialized) {
    return;
  }

  // Configure environment
  EnvironmentConfig.test = false;
  EnvironmentConfig.devMode = true;
  EnvironmentConfig.catcher = false;

  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  await initRustForIntegrationTest();

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize the database
  await DB.init();

  registerBuiltInGameModules(GameRegistry.instance);
  SettingsRepositories.instance.init();
  SettingsSideEffectCoordinator.instance = SettingsSideEffectCoordinator(
    updateGeneralEngineOptions: () =>
        GameRegistry.instance.current.enginePort?.updateGeneralOptions(),
    updateRuleEngineOptions: () =>
        GameRegistry.instance.current.enginePort?.updateRuleOptions(),
  );

  // Set up the database
  if (DB().generalSettings.showTutorial == true) {
    DB().generalSettings = DB().generalSettings.copyWith(showTutorial: false);
  }

  if (DB().generalSettings.firstRun == true) {
    DB().generalSettings = DB().generalSettings.copyWith(firstRun: false);
  }

  // TGF migration: exercise the Rust kernel-backed session in integration tests.
  DB().generalSettings = DB().generalSettings.copyWith(
    trapAwareness: false,
    usePerfectDatabase: false,
    useNativeMillSession: true,
  );

  _initialized = true;
}

/// Initializes the Rust bridge once for integration tests.
Future<void> initRustForIntegrationTest() async {
  if (RustLib.instance.initialized) {
    return;
  }

  await RustLib.init();
  assert(RustLib.instance.initialized, 'Rust bridge must be initialized.');
}
