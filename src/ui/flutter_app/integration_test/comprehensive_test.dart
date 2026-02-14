// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// comprehensive_test.dart
//
// Master runner for the complete integration test suite.
// This file imports and runs all individual feature test files,
// providing a single entry point for executing the full test suite.
//
// Usage:
//   flutter test integration_test/comprehensive_test.dart
//
// To run individual test files:
//   flutter test integration_test/tests/drawer_navigation_test.dart
//   flutter test integration_test/tests/general_settings_test.dart
//   ... etc.

import 'package:integration_test/integration_test.dart';

// Import all test files
import 'about_page_test.dart' as about_page;
import 'appearance_settings_test.dart' as appearance_settings;
import 'drawer_navigation_test.dart' as drawer_navigation;
import 'game_options_modal_test.dart' as game_options_modal;
import 'game_page_ai_vs_ai_test.dart' as game_page_ai_vs_ai;
import 'game_page_human_vs_ai_test.dart' as game_page_human_vs_ai;
import 'game_page_human_vs_human_test.dart' as game_page_human_vs_human;
import 'game_page_setup_position_test.dart' as game_page_setup_position;
import 'game_toolbar_test.dart' as game_toolbar;
import 'general_settings_test.dart' as general_settings;
import 'history_navigation_test.dart' as history_navigation;
import 'info_dialog_test.dart' as info_dialog;
import 'rule_settings_test.dart' as rule_settings;
import 'statistics_page_test.dart' as statistics_page;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run all test suites sequentially
  drawer_navigation.main();
  game_page_human_vs_ai.main();
  game_page_human_vs_human.main();
  game_page_ai_vs_ai.main();
  game_page_setup_position.main();
  game_toolbar.main();
  game_options_modal.main();
  history_navigation.main();
  general_settings.main();
  rule_settings.main();
  appearance_settings.main();
  statistics_page.main();
  about_page.main();
  info_dialog.main();
}
