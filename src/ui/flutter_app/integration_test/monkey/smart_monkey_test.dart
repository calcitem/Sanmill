// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// smart_monkey_test.dart
//
// Native-session smart monkey integration test (migrated from master).
// Exercises placing, moving, and removing phases via board taps.

// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../backup_service.dart';
import '../helpers.dart';
import '../init_test_environment.dart';
import 'game_state_reader.dart';
import 'smart_actions.dart';

const int kActionsPerHvHGame = 80;
const int kActionsPerHvAIGame = 20;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic>? dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Smart Monkey Tests', () {
    testWidgets(
      'HvH - placing, moving, and removing phases',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
        await startNewGame(tester);

        final SmartActions actions = SmartActions(seed: 42);

        for (int i = 0; i < kActionsPerHvHGame; i++) {
          final ActionResult result = await actions.performAction(
            tester,
            gameActionProbability: 0.95,
          );

          if (result == ActionResult.gameOver || GameStateReader.isGameOver) {
            await startNewGame(tester);
          }

          if (i % 20 == 0) {
            GameStateReader.printState();
          }
        }

        actions.printSummary();

        expect(
          actions.movingActions,
          greaterThan(0),
          reason: 'Smart monkey should perform moving actions',
        );
        expect(
          actions.placingActions,
          greaterThan(0),
          reason: 'Smart monkey should perform placing actions',
        );

        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'HvAI - human moves with AI responses',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await startNewGame(tester);

        final SmartActions actions = SmartActions(seed: 123);

        for (int i = 0; i < kActionsPerHvAIGame; i++) {
          await tester.pump(const Duration(milliseconds: 100));

          if (GameController().isEngineRunning) {
            await tester.pump(const Duration(milliseconds: 500));
            continue;
          }

          await actions.performAction(tester);

          try {
            await tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 3),
            );
          } on FlutterError {
            await tester.pump(const Duration(milliseconds: 200));
          }
        }

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

Future<void> _setupFastGame(WidgetTester tester) async {
  await initApp(tester);

  DB().generalSettings = DB().generalSettings.copyWith(
    skillLevel: 1,
    moveTime: 0,
    shufflingEnabled: false,
    showTutorial: false,
    firstRun: false,
    useNativeMillSession: true,
  );
}
