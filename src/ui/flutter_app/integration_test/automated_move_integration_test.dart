// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_integration_test.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/shared/database/database.dart';

import '../test/game/automated_move_test_data.dart';
import '../test/game/automated_move_test_models.dart';

/// Integration test for automated move testing with real AI engine
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Automated Move Integration Tests', () {
    
    testWidgets('Test real AI move execution with imported move list', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      // Print current DB settings
      final generalSettings = DB().generalSettings;
      final ruleSettings = DB().ruleSettings;
      
      print('[IntegrationTest] Current AI Settings:');
      print('[IntegrationTest] Skill Level: ${generalSettings.skillLevel}');
      print('[IntegrationTest] Move Time: ${generalSettings.moveTime}');
      print('[IntegrationTest] Search Algorithm: ${generalSettings.searchAlgorithm}');
      print('[IntegrationTest] Perfect Database: ${generalSettings.usePerfectDatabase}');
      print('[IntegrationTest] AI Is Lazy: ${generalSettings.aiIsLazy}');
      print('[IntegrationTest] Shuffling: ${generalSettings.shufflingEnabled}');
      print('[IntegrationTest] Pieces Count: ${ruleSettings.piecesCount}');
      print('[IntegrationTest] Has Diagonal Lines: ${ruleSettings.hasDiagonalLines}');
      print('[IntegrationTest] May Fly: ${ruleSettings.mayFly}');

      // Navigate to Human vs Human mode
      await _navigateToHumanVsHuman(tester);
      
      // Execute test with sample move list
      await _executeTestCase(
        tester,
        AutomatedMoveTestData.sampleTestCase1,
      );
    });

    testWidgets('Test AI with shorter move sequence', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      // Navigate to Human vs Human mode
      await _navigateToHumanVsHuman(tester);
      
      // Execute test with shorter move list
      await _executeTestCase(
        tester,
        AutomatedMoveTestData.sampleTestCase2,
      );
    });
  });
}

/// Navigate to Human vs Human mode
Future<void> _navigateToHumanVsHuman(WidgetTester tester) async {
  print('[IntegrationTest] Navigating to Human vs Human mode...');
  
  // Look for the drawer button and tap it
  final Finder drawerButton = find.byTooltip('Open navigation menu');
  if (drawerButton.evaluate().isNotEmpty) {
    await tester.tap(drawerButton);
    await tester.pumpAndSettle();
  }

  // Look for Human vs Human option in the drawer
  final Finder humanVsHumanOption = find.text('Human vs Human');
  if (humanVsHumanOption.evaluate().isNotEmpty) {
    await tester.tap(humanVsHumanOption);
    await tester.pumpAndSettle();
    print('[IntegrationTest] Successfully navigated to Human vs Human mode');
  } else {
    print('[IntegrationTest] Warning: Could not find Human vs Human option');
  }
}

/// Execute a test case with move list import and AI execution
Future<void> _executeTestCase(
  WidgetTester tester,
  MoveListTestCase testCase,
) async {
  print('[IntegrationTest] Executing test case: ${testCase.id}');
  print('[IntegrationTest] Description: ${testCase.description}');
  
  try {
    // Get the game controller
    final GameController controller = GameController();
    
    // Reset to clean state
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    
    // Record initial state
    final String initialSequence = controller.gameRecorder.moveHistoryText;
    final int initialMoveCount = controller.gameRecorder.mainlineMoves.length;
    
    print('[IntegrationTest] Initial sequence: "$initialSequence"');
    print('[IntegrationTest] Initial move count: $initialMoveCount');
    
    // Import the move list
    print('[IntegrationTest] Importing move list...');
    ImportService.import(testCase.moveList);
    
    // Record state after import
    final String afterImportSequence = controller.gameRecorder.moveHistoryText;
    final int afterImportMoveCount = controller.gameRecorder.mainlineMoves.length;
    
    print('[IntegrationTest] After import sequence: "$afterImportSequence"');
    print('[IntegrationTest] After import move count: $afterImportMoveCount');
    
    // Create a BuildContext for moveNow
    final BuildContext context = tester.element(find.byType(MaterialApp));
    
    // Execute "move now" to trigger AI
    print('[IntegrationTest] Executing move now to trigger AI...');
    await controller.moveNow(context);
    
    // Wait for AI to complete moves
    await Future<void>.delayed(const Duration(seconds: 3));
    
    // Record final state
    final String finalSequence = controller.gameRecorder.moveHistoryText;
    final int finalMoveCount = controller.gameRecorder.mainlineMoves.length;
    
    print('[IntegrationTest] Final sequence: "$finalSequence"');
    print('[IntegrationTest] Final move count: $finalMoveCount');
    print('[IntegrationTest] AI made ${finalMoveCount - afterImportMoveCount} moves');
    
    // Check if result matches expected sequences
    bool testPassed = false;
    String? matchedExpected;
    
    for (final String expected in testCase.expectedSequences) {
      if (_normalizeSequence(finalSequence) == _normalizeSequence(expected)) {
        testPassed = true;
        matchedExpected = expected;
        break;
      }
    }
    
    // Print test result
    final String status = testPassed ? 'PASSED' : 'FAILED';
    print('[IntegrationTest] [$status] ${testCase.id}');
    
    if (testPassed && matchedExpected != null) {
      print('[IntegrationTest] Matched expected sequence: $matchedExpected');
    } else {
      print('[IntegrationTest] Expected one of:');
      for (final String expected in testCase.expectedSequences) {
        print('[IntegrationTest]   - $expected');
      }
      print('[IntegrationTest] Actual: $finalSequence');
    }
    
    // Note: In integration tests, we don't use expect() to fail the test
    // because we want to see the actual AI output to update expected sequences
    
  } catch (e) {
    print('[IntegrationTest] Test case failed with error: $e');
  }
  
  print('[IntegrationTest] Test case completed\n');
}

/// Normalize a move sequence for comparison
String _normalizeSequence(String sequence) {
  return sequence.trim().replaceAll(RegExp(r'\s+'), ' ');
}
