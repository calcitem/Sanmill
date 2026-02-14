// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// appearance_settings_test.dart
//
// Integration tests for the Appearance Settings page.
// Verifies that display settings and color settings sections are present,
// toggle switches function correctly, and the page can be scrolled
// through without issues.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Appearance Settings Page', () {
    testWidgets('Page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      // Verify the page scaffold
      verifyPageDisplayed(tester, 'appearance_settings_page_scaffold');

      // Verify the settings list
      verifyWidgetExists(tester, 'appearance_settings_page_settings_list');
    });

    testWidgets('Display settings card is visible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      // Verify display settings card
      verifyWidgetExists(
        tester,
        'appearance_settings_page_display_settings_card',
      );
    });

    testWidgets('Language setting is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      // Verify language settings tile
      await scrollToAndVerify(
        tester,
        targetKey: 'display_settings_card_language_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Toggle history navigation toolbar shown', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue =
          DB().displaySettings.isHistoryNavigationToolbarShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_history_navigation_toolbar_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isHistoryNavigationToolbarShown,
        isNot(equals(initialValue)),
        reason: 'History navigation toolbar shown should have toggled',
      );
    });

    testWidgets('Toggle notations shown', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isNotationsShown;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_notations_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isNotationsShown,
        isNot(equals(initialValue)),
        reason: 'Notations shown should have toggled',
      );
    });

    testWidgets('Toggle unplaced and removed pieces shown', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue =
          DB().displaySettings.isUnplacedAndRemovedPiecesShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_unplaced_removed_pieces_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isUnplacedAndRemovedPiecesShown,
        isNot(equals(initialValue)),
        reason: 'Unplaced/removed pieces shown should have toggled',
      );
    });

    testWidgets('Toggle positional advantage indicator', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue =
          DB().displaySettings.isPositionalAdvantageIndicatorShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_positional_advantage_indicator_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isPositionalAdvantageIndicatorShown,
        isNot(equals(initialValue)),
        reason: 'Positional advantage indicator should have toggled',
      );
    });

    testWidgets('Toggle advantage graph shown', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isAdvantageGraphShown;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_advantage_graph_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isAdvantageGraphShown,
        isNot(equals(initialValue)),
        reason: 'Advantage graph shown should have toggled',
      );
    });

    testWidgets('Toggle piece count in hand shown', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isPieceCountInHandShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_piece_count_in_hand_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isPieceCountInHandShown,
        isNot(equals(initialValue)),
        reason: 'Piece count in hand shown should have toggled',
      );
    });

    testWidgets('Board corner radius setting is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey:
            'display_settings_card_board_corner_radius_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Piece width setting is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'display_settings_card_piece_width_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Color settings card is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'appearance_settings_page_color_settings_card',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Theme setting tile is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'color_settings_card_theme_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Toggle board shadow enabled', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.boardShadowEnabled;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_board_shadow_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.boardShadowEnabled,
        isNot(equals(initialValue)),
        reason: 'Board shadow enabled should have toggled',
      );
    });

    testWidgets('Toggle vignette effect', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.vignetteEffectEnabled;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_vignette_effect_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.vignetteEffectEnabled,
        isNot(equals(initialValue)),
        reason: 'Vignette effect should have toggled',
      );
    });

    testWidgets('Toggle numbers on pieces shown', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isNumbersOnPiecesShown;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_numbers_on_pieces_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isNumbersOnPiecesShown,
        isNot(equals(initialValue)),
        reason: 'Numbers on pieces shown should have toggled',
      );
    });

    testWidgets('Export color settings tile is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'color_settings_card_export_color_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Toggle toolbar at bottom', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isToolbarAtBottom;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_toolbar_at_bottom_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isToolbarAtBottom,
        isNot(equals(initialValue)),
        reason: 'Toolbar at bottom should have toggled',
      );
    });

    testWidgets('Toggle annotation toolbar shown', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isAnnotationToolbarShown;

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_annotation_toolbar_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isAnnotationToolbarShown,
        isNot(equals(initialValue)),
        reason: 'Annotation toolbar shown should have toggled',
      );
    });

    testWidgets('Toggle capturable pieces highlight shown', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue =
          DB().displaySettings.isCapturablePiecesHighlightShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_capturable_pieces_highlight_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isCapturablePiecesHighlightShown,
        isNot(equals(initialValue)),
        reason: 'Capturable pieces highlight shown should have toggled',
      );
    });

    testWidgets('Toggle screenshot game info shown', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue = DB().displaySettings.isScreenshotGameInfoShown;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_screenshot_game_info_shown_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isScreenshotGameInfoShown,
        isNot(equals(initialValue)),
        reason: 'Screenshot game info shown should have toggled',
      );
    });

    testWidgets('Toggle piece pick up animation enabled', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      final bool initialValue =
          DB().displaySettings.isPiecePickUpAnimationEnabled;

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_piece_pick_up_animation_enabled_switch_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      expect(
        DB().displaySettings.isPiecePickUpAnimationEnabled,
        isNot(equals(initialValue)),
        reason: 'Piece pick up animation enabled should have toggled',
      );
    });

    testWidgets('Import color settings tile is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'color_settings_card_import_color_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Board color tile is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'color_settings_card_board_color_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Drawer color tile is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'color_settings_card_drawer_color_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Font size setting is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'display_settings_card_font_size_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });

    testWidgets('Board top setting is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'display_settings_card_board_top_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );
    });
  });
}
