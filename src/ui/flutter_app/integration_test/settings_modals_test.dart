// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// settings_modals_test.dart
//
// Integration tests for various modal dialogs in settings pages.
// Tests the algorithm selection modal, rule set selection modal,
// pieces count modal, and other pickers/modals across the settings UI.

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

  late Map<String, dynamic> dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('General Settings Modals', () {
    testWidgets('Algorithm modal opens and displays options', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to and tap the algorithm setting
      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_ais_play_style_algorithm',
      );

      // The algorithm modal should be displayed with radio options
      expect(
        find.byKey(const Key('algorithm_modal_column')),
        findsOneWidget,
        reason: 'Algorithm modal column should be visible',
      );

      // Verify at least one algorithm radio option exists
      expect(
        find.byKey(const Key('algorithm_modal_radio_list_tile_alpha_beta')),
        findsOneWidget,
        reason: 'Alpha-Beta radio option should be present',
      );

      // Select Alpha-Beta and dismiss
      await tester.tap(
        find.byKey(const Key('algorithm_modal_radio_list_tile_alpha_beta')),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Move time slider modal opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to and tap move time
      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_difficulty_move_time',
      );

      // The move time slider should be displayed
      expect(
        find.byKey(const Key('move_time_slider_slider')),
        findsOneWidget,
        reason: 'Move time slider should be visible',
      );

      // Dismiss the bottom sheet by tapping outside or pressing back
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Sound theme modal opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Scroll to and tap sound theme
      await scrollToAndTap(
        tester,
        targetKey:
            'general_settings_page_settings_card_play_sounds_sound_theme',
      );

      // A modal bottom sheet should appear with sound theme options
      await tester.pumpAndSettle();

      // Dismiss the modal
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });
  });

  group('Rule Settings Modals', () {
    testWidgets('Rule set modal opens with all rule variants', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Tap the rule set tile
      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();

      // Verify multiple rule set options are present
      expect(
        find.byKey(const Key('radio_nine_mens_morris')),
        findsOneWidget,
        reason: "Nine Men's Morris option should be present",
      );
      expect(
        find.byKey(const Key('radio_twelve_mens_morris')),
        findsOneWidget,
        reason: "Twelve Men's Morris option should be present",
      );
      expect(
        find.byKey(const Key('radio_morabaraba')),
        findsOneWidget,
        reason: 'Morabaraba option should be present',
      );

      // Select Nine Men's Morris to dismiss
      await tester.tap(find.byKey(const Key('radio_nine_mens_morris')));
      await tester.pumpAndSettle();
    });

    testWidgets('Select Twelve Mens Morris rule set', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Tap rule set tile
      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();

      // Select Twelve Men's Morris
      await tester.tap(find.byKey(const Key('radio_twelve_mens_morris')));
      await tester.pumpAndSettle();

      // Verify pieces count changed to 12
      expect(
        DB().ruleSettings.piecesCount,
        equals(12),
        reason: "Twelve Men's Morris should set pieces count to 12",
      );
    });

    testWidgets('Select Morabaraba rule set', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();

      // Select Morabaraba
      await tester.tap(find.byKey(const Key('radio_morabaraba')));
      await tester.pumpAndSettle();

      // Morabaraba has 12 pieces and diagonal lines
      expect(
        DB().ruleSettings.piecesCount,
        equals(12),
        reason: 'Morabaraba should set pieces count to 12',
      );
      expect(
        DB().ruleSettings.hasDiagonalLines,
        isTrue,
        reason: 'Morabaraba should enable diagonal lines',
      );
    });

    testWidgets('Pieces count modal opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Scroll to and tap pieces count
      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_tile_pieces_count',
        scrollableKey: 'rule_settings_list',
      );

      // The pieces count modal should open with radio options
      // Radio buttons are named 'radio_5' through 'radio_12'
      expect(
        find.byKey(const Key('radio_9')),
        findsOneWidget,
        reason: 'Radio option for 9 pieces should be present',
      );

      // Select 9 pieces to dismiss
      await tester.tap(find.byKey(const Key('radio_9')));
      await tester.pumpAndSettle();
    });

    testWidgets('N-move rule modal opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Scroll to and tap N-move rule
      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_tile_n_move_rule',
        scrollableKey: 'rule_settings_list',
      );

      // The N-move rule modal should open
      await tester.pumpAndSettle();

      // Dismiss the modal
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Fly piece count modal opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Scroll to and tap fly piece count
      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_tile_fly_piece_count',
        scrollableKey: 'rule_settings_list',
      );

      // The fly piece count modal should open
      await tester.pumpAndSettle();

      // Dismiss the modal
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Select Lasker Morris rule set', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();

      // Select Lasker Morris
      await tester.tap(find.byKey(const Key('radio_lasker_morris')));
      await tester.pumpAndSettle();

      // Verify Lasker Morris allows moving in placing phase
      expect(
        DB().ruleSettings.mayMoveInPlacingPhase,
        isTrue,
        reason: 'Lasker Morris should enable moving in placing phase',
      );
    });

    testWidgets('Revert to Nine Mens Morris after changing rule set', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // First set to Twelve Men's Morris
      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('radio_twelve_mens_morris')));
      await tester.pumpAndSettle();
      expect(DB().ruleSettings.piecesCount, equals(12));

      // Now switch back to Nine Men's Morris
      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('radio_nine_mens_morris')));
      await tester.pumpAndSettle();

      expect(
        DB().ruleSettings.piecesCount,
        equals(9),
        reason: "Reverting to Nine Men's Morris should set pieces count to 9",
      );
    });
  });

  group('Appearance Settings Modals', () {
    testWidgets('Point painting style modal opens', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      // Scroll to and tap point style
      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_point_style_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      // The point painting style modal should open
      // Verify the radio options are present
      expect(
        find.byKey(const Key('radio_none')),
        findsOneWidget,
        reason: 'None option should be present in point style modal',
      );
      expect(
        find.byKey(const Key('radio_solid')),
        findsOneWidget,
        reason: 'Solid option should be present in point style modal',
      );

      // Select None to dismiss
      await tester.tap(find.byKey(const Key('radio_none')));
      await tester.pumpAndSettle();
    });

    testWidgets('Board corner radius slider opens', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_board_corner_radius_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      // A bottom sheet with a slider should appear
      await tester.pumpAndSettle();

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Piece width slider opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'display_settings_card_piece_width_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      // A bottom sheet with a slider should appear
      await tester.pumpAndSettle();

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Animation duration slider opens', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndTap(
        tester,
        targetKey:
            'display_settings_card_animation_duration_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      await tester.pumpAndSettle();

      // Dismiss
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('Export color settings dialog opens', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'color_settings_card_export_color_settings_list_tile',
        scrollableKey: 'appearance_settings_page_settings_list',
      );

      // The export dialog should open
      expect(
        find.byKey(const Key('export_color_settings_alert_dialog')),
        findsOneWidget,
        reason: 'Export color settings dialog should be visible',
      );

      // Dismiss by tapping Close
      final Finder closeButton = find.byKey(
        const Key('export_color_settings_close_button'),
      );
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();
    });
  });
}
