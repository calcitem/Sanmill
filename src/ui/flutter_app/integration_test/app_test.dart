// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// app_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/shared/services/logger.dart';

// Local imports
import 'init_test_environment.dart';
import 'test_runner.dart';
import 'test_scenarios.dart';

void main() {
  // Make the warning fatal
  WidgetController.hitTestWarningShouldBeFatal = true;

  // Make sure integration test binding is initialized
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    logger.i('Initializing test environment...');
    await initTestEnvironment();

    // Additional setup if needed
    initBitboards();
    _initUI();
  });

  group('App Integration Tests (Data Driven)', () {
    for (final Map<String, dynamic> scenario in testScenarios) {
      final String scenarioDescription = scenario['description'] as String;
      final List<Map<String, String>> steps =
          scenario['steps'] as List<Map<String, String>>;

      testWidgets(scenarioDescription, (WidgetTester tester) async {
        // Pump the app once per test
        await tester.pumpWidget(const app.SanmillApp());
        await tester.pumpAndSettle();

        // Run the scenario steps
        await runScenarioSteps(tester, steps);
      });
    }
  });
}

/// Initializes UI settings before running tests (e.g., preferred orientations).
void _initUI() {
  // For example, set preferred orientations if needed:
  // SystemChrome.setPreferredOrientations([
  //   DeviceOrientation.portraitUp,
  //   DeviceOrientation.portraitDown,
  // ]);
}
