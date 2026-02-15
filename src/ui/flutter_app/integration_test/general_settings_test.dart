// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// general_settings_test.dart
//
// Integration tests for the General Settings page.
// Verifies that all settings sections are present, settings items
// are accessible via scrolling, and interactive elements (switches,
// pickers) respond correctly to user input.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';

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

  group('General Settings Page', () {
    testWidgets('Page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Verify the page scaffold
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Verify the settings list exists
      verifyWidgetExists(tester, 'general_settings_page_settings_list');
    });

    testWidgets('Who moves first section is visible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Verify the "Who Moves First" card
      verifyWidgetExists(
        tester,
        'general_settings_page_settings_card_who_moves_first',
      );

      // Verify the switch tile
      verifyWidgetExists(
        tester,
        'general_settings_page_settings_card_who_moves_first_switch_tile',
      );
    });

    testWidgets('Toggle who moves first switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Record initial state
      final bool initialValue = DB().generalSettings.aiMovesFirst;

      // Tap the switch
      await tester.tap(
        find.byKey(
          const Key(
            'general_settings_page_settings_card_who_moves_first_switch_tile',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the state changed
      expect(
        DB().generalSettings.aiMovesFirst,
        isNot(equals(initialValue)),
        reason: 'Who moves first should have toggled',
      );
    });

    testWidgets('Difficulty section is visible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Verify the difficulty card
      verifyWidgetExists(
        tester,
        'general_settings_page_settings_card_difficulty',
      );

      // Verify skill level and move time items
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_difficulty_skill_level',
      );
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_difficulty_move_time',
        resetScroll: false,
      );
    });

    testWidgets('Tap skill level opens picker', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to and tap skill level
      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_difficulty_skill_level',
      );

      // The skill level picker dialog should be displayed
      final Finder confirmButton = find.byKey(
        const Key('skill_level_picker_confirm_button'),
      );
      expect(
        confirmButton,
        findsOneWidget,
        reason: 'Skill level picker confirm button should be visible',
      );

      // Dismiss the picker
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
    });

    testWidgets('AI play style section items are accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Verify AI play style card
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_ais_play_style',
      );

      // Verify algorithm item
      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_algorithm',
        resetScroll: false,
      );
    });

    testWidgets('Toggle shuffling enabled switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.shufflingEnabled;

      // Scroll to and tap shuffling switch
      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
      );

      // Verify the state changed
      expect(
        DB().generalSettings.shufflingEnabled,
        isNot(equals(initialValue)),
        reason: 'Shuffling enabled should have toggled',
      );
    });

    testWidgets('Toggle draw on human experience switch', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.drawOnHumanExperience;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_draw_on_human_experience',
      );

      expect(
        DB().generalSettings.drawOnHumanExperience,
        isNot(equals(initialValue)),
        reason: 'Draw on human experience should have toggled',
      );
    });

    testWidgets('Toggle consider mobility switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.considerMobility;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_consider_mobility',
      );

      expect(
        DB().generalSettings.considerMobility,
        isNot(equals(initialValue)),
        reason: 'Consider mobility should have toggled',
      );
    });

    testWidgets('Play sounds section is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to play sounds card
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_play_sounds',
      );

      // Verify tone enabled switch
      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_tone_enabled',
        resetScroll: false,
      );
    });

    testWidgets('Toggle play sounds switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.toneEnabled;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_tone_enabled',
      );

      expect(
        DB().generalSettings.toneEnabled,
        isNot(equals(initialValue)),
        reason: 'Tone enabled should have toggled',
      );
    });

    testWidgets('Developer options section is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to developer options card
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_developer',
      );

      // Verify developer options tile
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
        resetScroll: false,
      );
    });

    testWidgets('Restore defaults section is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to restore card (at the bottom)
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_restore',
      );

      // Verify restore default settings tile
      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_restore_default_settings',
        resetScroll: false,
      );
    });

    testWidgets('Restore defaults shows confirmation dialog', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to and tap Restore Default Settings
      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_restore_default_settings',
      );

      // Verify the confirmation dialog appeared
      final Finder okButton = find.byKey(
        const Key('reset_settings_alert_dialog_ok_button'),
      );
      expect(
        okButton,
        findsOneWidget,
        reason: 'Reset settings confirmation dialog should appear',
      );

      // Dismiss the dialog without confirming (tap Cancel or OK)
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    });

    testWidgets('Sound theme item is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_sound_theme',
      );
    });

    testWidgets('Toggle focus on blocking paths switch', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.focusOnBlockingPaths;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_focus_on_blocking_paths',
      );

      expect(
        DB().generalSettings.focusOnBlockingPaths,
        isNot(equals(initialValue)),
        reason: 'Focus on blocking paths should have toggled',
      );
    });

    testWidgets('Toggle AI is lazy (passive) switch', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.aiIsLazy;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_ai_is_lazy',
      );

      expect(
        DB().generalSettings.aiIsLazy,
        isNot(equals(initialValue)),
        reason: 'AI is lazy should have toggled',
      );
    });

    testWidgets('Toggle use opening book switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.useOpeningBook;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_use_opening_book',
      );

      expect(
        DB().generalSettings.useOpeningBook,
        isNot(equals(initialValue)),
        reason: 'Use opening book should have toggled',
      );
    });

    testWidgets('Toggle keep mute when taking back switch', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.keepMuteWhenTakingBack;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_keep_mute_when_taking_back',
      );

      expect(
        DB().generalSettings.keepMuteWhenTakingBack,
        isNot(equals(initialValue)),
        reason: 'Keep mute when taking back should have toggled',
      );
    });

    testWidgets('Human move time item is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_difficulty_human_move_time',
      );
    });

    testWidgets('Toggle use perfect database switch', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      final bool initialValue = DB().generalSettings.usePerfectDatabase;

      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_use_perfect_database',
      );

      expect(
        DB().generalSettings.usePerfectDatabase,
        isNot(equals(initialValue)),
        reason: 'Use perfect database should have toggled',
      );
    });

    testWidgets('LLM prompts card is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // LLM card is only shown when rule settings look like Nine Men's Morris
      // Ensure Nine Men's Morris rules are active
      await scrollToAndVerify(
        tester,
        targetKey: 'general_settings_page_settings_card_llm_prompts',
      );
    });

    testWidgets('Background music enabled switch is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_background_music_enabled',
      );
    });
  });
}
