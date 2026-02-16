// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// smart_monkey_test.dart
//
// Smart monkey integration test for the Sanmill Flutter app.
//
// Unlike the traditional adb monkey test which generates purely random
// touch events, this test understands the game's state machine and
// generates targeted actions for each game phase:
//
// - Placing phase: taps empty board positions to place pieces.
// - Moving phase: selects an owned piece then taps an adjacent empty
//   position (the key scenario that random monkey testing cannot reach).
// - Removing phase: taps an opponent piece after forming a mill.
// - Game over: dismisses result dialogs and starts new games.
//
// Between game actions it also performs random UI interactions (toolbar,
// drawer, settings) to stress-test the app in realistic usage patterns.
//
// Usage:
//   flutter test integration_test/monkey/smart_monkey_test.dart -d linux
//   flutter test integration_test/monkey/smart_monkey_test.dart -d android

// ignore_for_file: avoid_print

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../backup_service.dart';
import '../helpers.dart';
import '../init_test_environment.dart';
import 'game_state_reader.dart';
import 'smart_actions.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Number of actions per test scenario.
/// Increase for longer stress runs.
const int kActionsPerHvHGame = 200;
const int kActionsPerHvAIGame = 120;
const int kActionsPerAiVsAiGame = 60;
const int kActionsPerMultiMode = 150;
const int kActionsPerRuleVariant = 80;
const int kActionsPerSettingsChaos = 80;

// ---------------------------------------------------------------------------
// Test entry point
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic>? dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Smart Monkey Tests', () {
    // -----------------------------------------------------------------------
    // Scenario 1: Human vs Human full game lifecycle (PRIMARY)
    //
    // This is the most important scenario because it exercises the moving
    // phase which random monkey testing cannot reach.
    // -----------------------------------------------------------------------
    testWidgets(
      'HvH - full game with placing, moving, and removing',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
        await startNewGame(tester);

        final SmartActions actions = SmartActions(seed: 42);
        int gamesCompleted = 0;

        for (int i = 0; i < kActionsPerHvHGame; i++) {
          final ActionResult result = await actions.performAction(
            tester,
            gameActionProbability: 0.95,
          );

          if (result == ActionResult.gameOver ||
              GameStateReader.isGameOver) {
            gamesCompleted++;
            print('[HvH] Game #$gamesCompleted completed at action $i '
                '(winner=${GameStateReader.winner})');
          }

          // Periodic state logging.
          if (i % 20 == 0) {
            print('[HvH] Action $i/$kActionsPerHvHGame');
            GameStateReader.printState();
          }
        }

        actions.printSummary();
        _printPhaseStats(actions, gamesCompleted);

        // Verify that we actually exercised the moving phase.
        expect(
          actions.movingActions,
          greaterThan(0),
          reason: 'Smart monkey should have performed moving actions',
        );

        // Verify that we exercised placing.
        expect(
          actions.placingActions,
          greaterThan(0),
          reason: 'Smart monkey should have performed placing actions',
        );

        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 2: Human vs AI mixed interaction
    // -----------------------------------------------------------------------
    testWidgets(
      'HvAI - placing and moving with AI responses',
      (WidgetTester tester) async {
        await _setupFastGame(tester);

        // Default mode is Human vs AI; just start a new game.
        await startNewGame(tester);

        final SmartActions actions = SmartActions(seed: 123);

        for (int i = 0; i < kActionsPerHvAIGame; i++) {
          // Wait a bit for AI moves to complete.
          await tester.pump(const Duration(milliseconds: 100));

          // Skip if AI is currently thinking.
          if (GameController().isEngineRunning) {
            await tester.pump(const Duration(milliseconds: 500));
            continue;
          }

          await actions.performAction(tester, gameActionProbability: 0.80);

          // After each action, let the AI respond.
          // Use try-catch since pumpAndSettle may timeout during AI thinking.
          try {
            await tester.pumpAndSettle(const Duration(seconds: 3));
          } on FlutterError {
            await tester.pump(const Duration(milliseconds: 200));
          }

          if (i % 20 == 0) {
            print('[HvAI] Action $i/$kActionsPerHvAIGame');
            GameStateReader.printState();
          }
        }

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 3: AI vs AI + UI stress
    // -----------------------------------------------------------------------
    testWidgets(
      'AiVsAi - observe game while performing UI interactions',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

        // Let the AI play while we randomly interact with the UI.
        final SmartActions actions = SmartActions(seed: 77);

        for (int i = 0; i < kActionsPerAiVsAiGame; i++) {
          // Only UI actions in AI vs AI mode (game actions are irrelevant).
          await actions.performAction(
            tester,
            gameActionProbability: 0.0,
          );
          await tester.pump(const Duration(milliseconds: 200));

          if (i % 15 == 0) {
            print('[AiVsAi] Action $i/$kActionsPerAiVsAiGame');
          }
        }

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 4: Setup Position - random piece placement
    // -----------------------------------------------------------------------
    testWidgets(
      'SetupPosition - random piece placement and removal',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await navigateToDrawerItem(tester, 'drawer_item_setup_position');

        final SmartActions actions = SmartActions(seed: 500);

        // Tap random board positions to place and remove pieces freely.
        for (int i = 0; i < 60; i++) {
          await actions.performAction(
            tester,
            gameActionProbability: 0.90,
          );
          await tester.pump(const Duration(milliseconds: 50));

          if (i % 20 == 0) {
            print('[SetupPosition] Action $i/60');
          }
        }

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 5: Multi-mode cycling
    // -----------------------------------------------------------------------
    testWidgets(
      'Multi-mode - cycle through game modes and play',
      (WidgetTester tester) async {
        await _setupFastGame(tester);

        final SmartActions actions = SmartActions(seed: 256);
        final List<String> modes = <String>[
          'drawer_item_human_vs_human',
          'drawer_item_human_vs_ai',
          'drawer_item_ai_vs_ai',
          'drawer_item_setup_position',
        ];

        int actionCount = 0;
        for (int cycle = 0; cycle < 3; cycle++) {
          for (final String mode in modes) {
            print('[MultiMode] Switching to $mode (cycle $cycle)');
            try {
              await navigateToDrawerItem(tester, mode);
              // Setup position does not have a "new game" toolbar action
              // the same way, so only call startNewGame for play modes.
              if (mode != 'drawer_item_setup_position') {
                await startNewGame(tester);
              }
            } catch (e) {
              print('[MultiMode] Navigation failed: $e');
              continue;
            }

            // Perform some actions in this mode.
            final int actionsThisMode = kActionsPerMultiMode ~/ 12;
            for (int i = 0; i < actionsThisMode; i++) {
              if (mode == 'drawer_item_ai_vs_ai') {
                await actions.performAction(
                  tester,
                  gameActionProbability: 0.0,
                );
              } else {
                await actions.performAction(
                  tester,
                  gameActionProbability: 0.90,
                );
              }
              await tester.pump(const Duration(milliseconds: 100));
              actionCount++;
            }
          }
        }

        print('[MultiMode] Completed $actionCount actions across modes');
        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 6: Rule variant testing
    // -----------------------------------------------------------------------
    testWidgets(
      'Rule variants - play with different rule sets',
      (WidgetTester tester) async {
        await _setupFastGame(tester);

        final SmartActions actions = SmartActions(seed: 999);

        // Test with Nine Men's Morris (default).
        print('[RuleVariant] Testing Nine Men\'s Morris');
        DB().ruleSettings = const RuleSettings().copyWith(piecesCount: 9);
        await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
        await startNewGame(tester);
        await _runActions(tester, actions, kActionsPerRuleVariant ~/ 3);

        // Test with Twelve Men's Morris.
        print('[RuleVariant] Testing Twelve Men\'s Morris');
        DB().ruleSettings = const RuleSettings().copyWith(
          piecesCount: 12,
          hasDiagonalLines: true,
        );
        GameController().reset(force: true);
        await startNewGame(tester);
        await _runActions(tester, actions, kActionsPerRuleVariant ~/ 3);

        // Test with Nine Men's Morris with flying disabled.
        print('[RuleVariant] Testing Nine Men\'s Morris (no fly)');
        DB().ruleSettings = const RuleSettings().copyWith(
          piecesCount: 9,
          mayFly: false,
        );
        GameController().reset(force: true);
        await startNewGame(tester);
        await _runActions(tester, actions, kActionsPerRuleVariant ~/ 3);

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 7: Settings chaos
    // -----------------------------------------------------------------------
    testWidgets(
      'Settings chaos - change settings while game is active',
      (WidgetTester tester) async {
        await _setupFastGame(tester);
        await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
        await startNewGame(tester);

        final SmartActions actions = SmartActions(seed: 314);

        for (int i = 0; i < kActionsPerSettingsChaos; i++) {
          // Alternate between game actions and settings changes.
          if (i % 5 == 0) {
            // Change a setting programmatically.
            _randomSettingsChange(i);
          }

          await actions.performAction(tester, gameActionProbability: 0.70);

          if (i % 20 == 0) {
            print('[SettingsChaos] Action $i/$kActionsPerSettingsChaos');
          }
        }

        actions.printSummary();
        verifyPageDisplayed(tester, 'game_page_scaffold');
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Configure the game for fast testing: low AI skill, zero think time,
/// shuffling disabled for reproducibility.
Future<void> _setupFastGame(WidgetTester tester) async {
  await initApp(tester);

  DB().generalSettings = DB().generalSettings.copyWith(
    skillLevel: 1,
    moveTime: 0,
    shufflingEnabled: false,
    showTutorial: false,
    firstRun: false,
  );
}

/// Run [count] smart actions and pump between them.
Future<void> _runActions(
  WidgetTester tester,
  SmartActions actions,
  int count,
) async {
  for (int i = 0; i < count; i++) {
    await actions.performAction(tester, gameActionProbability: 0.95);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Apply a pseudo-random settings change.
void _randomSettingsChange(int seed) {
  switch (seed % 5) {
    case 0:
      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: (seed % 10) + 1,
      );
      print('[SettingsChaos] Set skillLevel=${(seed % 10) + 1}');
    case 1:
      DB().generalSettings = DB().generalSettings.copyWith(
        moveTime: seed % 3,
      );
      print('[SettingsChaos] Set moveTime=${seed % 3}');
    case 2:
      DB().generalSettings = DB().generalSettings.copyWith(
        shufflingEnabled: seed % 2 == 0,
      );
      print('[SettingsChaos] Set shuffling=${seed % 2 == 0}');
    case 3:
      DB().generalSettings = DB().generalSettings.copyWith(
        isAutoRestart: seed % 2 == 0,
      );
      print('[SettingsChaos] Set autoRestart=${seed % 2 == 0}');
    case 4:
    default:
      DB().generalSettings = DB().generalSettings.copyWith(
        aiIsLazy: seed % 2 == 0,
      );
      print('[SettingsChaos] Set aiIsLazy=${seed % 2 == 0}');
  }
}

/// Print statistics about game phases exercised.
void _printPhaseStats(SmartActions actions, int gamesCompleted) {
  print('');
  print('[SmartMonkey] ============= PHASE COVERAGE ==============');
  print('[SmartMonkey] Games completed: $gamesCompleted');
  print('[SmartMonkey] Placing actions: ${actions.placingActions}');
  print('[SmartMonkey] Moving actions:  ${actions.movingActions}');
  print('[SmartMonkey] Removing actions: ${actions.removingActions}');
  print('[SmartMonkey] ==========================================');
  print('');
}
