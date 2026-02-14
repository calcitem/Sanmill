// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// custom_functions.dart
//
// Registry of custom functions available for data-driven test scenarios.
// Each function receives a WidgetTester and the step data map so it can
// perform programmatic state changes that are difficult to express as
// simple tap/verify actions.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

/// A map of custom function names to their corresponding implementations.
final Map<String, Future<void> Function(WidgetTester, Map<String, String>)>
customFunctionMap =
    <String, Future<void> Function(WidgetTester p1, Map<String, String> p2)>{
      // Sets the AI skill level and move time to low values for fast testing.
      'setSkillLevelAndMovingTime':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().generalSettings = DB().generalSettings.copyWith(skillLevel: 5);
            DB().generalSettings = DB().generalSettings.copyWith(moveTime: 0);
            await tester.pumpAndSettle();
          },

      // Resets rule settings to the default configuration.
      'resetRuleSettings':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().ruleSettings = const RuleSettings();
            await tester.pumpAndSettle();
          },

      // Resets general settings to the default configuration,
      // but preserves firstRun=false and showTutorial=false for tests.
      'resetGeneralSettings':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().generalSettings = const GeneralSettings().copyWith(
              firstRun: false,
              showTutorial: false,
            );
            await tester.pumpAndSettle();
          },

      // Enables the history navigation toolbar in display settings.
      'enableHistoryNavigationToolbar':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isHistoryNavigationToolbarShown: true,
            );
            await tester.pumpAndSettle();
          },

      // Disables the history navigation toolbar in display settings.
      'disableHistoryNavigationToolbar':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isHistoryNavigationToolbarShown: false,
            );
            await tester.pumpAndSettle();
          },

      // Configures fast AI settings for quick test execution.
      'configureFastAi':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().generalSettings = DB().generalSettings.copyWith(
              skillLevel: 1,
              moveTime: 0,
              shufflingEnabled: false,
            );
            await tester.pumpAndSettle();
          },

      // Enables notations on the board.
      'enableNotations':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isNotationsShown: true,
            );
            await tester.pumpAndSettle();
          },

      // Disables notations on the board.
      'disableNotations':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isNotationsShown: false,
            );
            await tester.pumpAndSettle();
          },

      // Enables the advantage graph display.
      'enableAdvantageGraph':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isAdvantageGraphShown: true,
            );
            await tester.pumpAndSettle();
          },

      // Disables the advantage graph display.
      'disableAdvantageGraph':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().displaySettings = DB().displaySettings.copyWith(
              isAdvantageGraphShown: false,
            );
            await tester.pumpAndSettle();
          },

      // Sets Nine Men's Morris as the active rule set.
      'setNineMensMorrisRules':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().ruleSettings = const RuleSettings().copyWith(piecesCount: 9);
            await tester.pumpAndSettle();
          },

      // Sets Twelve Men's Morris as the active rule set.
      'setTwelveMensMorrisRules':
          (WidgetTester tester, Map<String, String> stepData) async {
            DB().ruleSettings = const RuleSettings().copyWith(
              piecesCount: 12,
              hasDiagonalLines: true,
            );
            await tester.pumpAndSettle();
          },
    };
