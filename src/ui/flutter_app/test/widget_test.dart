// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// widget_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import flutter services
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sanmill/app_shell/sanmill_app_shell.dart';
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/game_shell/shell_route_ids.dart';
import 'package:sanmill/games/built_in_game_modules.dart';
import 'package:sanmill/general_settings/widgets/developer_options_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/puzzle_creation_page.dart';
import 'package:sanmill/puzzle/widgets/puzzle_card.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/system_ui_service.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import 'helpers/test_native_library.dart';

void main() {
  // Ensure the binding is initialized before tests run
  TestWidgetsFlutterBinding.ensureInitialized();

  // Define the MethodChannel to be mocked
  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  // Set up a mock method channel handler for 'path_provider'
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUpAll(() async {
    // Disable catcher in test environment to avoid initialization issues
    // The catcher is only used in specific platforms (not iOS/Web) and
    // when EnvironmentConfig.catcher is true
    EnvironmentConfig.catcher = false;

    // Use the new API to set up mock handlers for MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
              return null; // Return a success response
            case 'shutdown':
              return null; // Return a success response
            case 'startup':
              return null; // Return a success response
            case 'read':
              return 'bestmove d2'; // Simulate a response for the 'read' method
            case 'isThinking':
              return false; // Simulate the 'isThinking' method response
            default:
              return null; // For unhandled methods, return null
          }
        });

    // Mock the 'getApplicationDocumentsDirectory' method
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            // Return a temporary directory path
            final Directory directory = Directory.systemTemp.createTempSync();
            return directory.path;
          }
          return null;
        });

    // Initialize the Rust/FRB bridge: Home starts a NativeMillGameSession
    // (backed by the Rust kernel) as soon as it builds.
    await initRustLibForTests();

    // Initialize the database and other services
    await DB.init();

    // Register the built-in game modules, mirroring main(): the Home
    // shell asserts that a module is registered for the active GameId.
    registerBuiltInGameModules(GameRegistry.instance);

    await initializeUI(true);
  });

  tearDownAll(disposeRustLibForTests);

  testWidgets('SanmillApp smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const SanmillApp());

    // Verify that MaterialApp and Scaffold are present
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);

    // Let the SettingsSideEffectCoordinator debounce timer (300 ms),
    // armed by Home.firstRun saving the settings, expire before the
    // pending-timer invariant check at test teardown.
    await tester.pump(const Duration(milliseconds: 350));
  }, skip: nativeLibrarySkipReason() != null);

  testWidgets(
    'Verify app navigation and localization',
    (WidgetTester tester) async {
      // Build the app and trigger a frame
      await tester.pumpWidget(const SanmillApp());

      // Check that the supported locales include English
      expect(S.supportedLocales.contains(const Locale('en')), isTrue);

      // Verify that the Lichess-style shell is present.
      expect(find.byType(SanmillAppShell), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_navigation_rail')), findsNothing);
      expect(find.byKey(const Key('sanmill_tab_home')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_tab_watch')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_tab_records')), findsNothing);

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Verify mobile shell bottom navigation and more menu',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());

      expect(find.byType(SanmillAppShell), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_navigation_rail')), findsNothing);
      expect(find.byKey(const Key('sanmill_tab_home')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_tab_watch')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_tab_records')), findsNothing);
      expect(
        find.byKey(const Key('sanmill_more_list'), skipOffstage: false),
        findsNothing,
      );

      final NavigationDestination learnDestination = tester
          .widget<NavigationDestination>(
            find.byKey(const Key('sanmill_tab_learn')),
          );
      expect(learnDestination.label, 'Learn');

      final NavigationDestination watchDestination = tester
          .widget<NavigationDestination>(
            find.byKey(const Key('sanmill_tab_watch')),
          );
      expect((watchDestination.icon as Icon).icon, Symbols.live_tv_rounded);
      expect((watchDestination.icon as Icon).fill, 0);
      expect(watchDestination.selectedIcon, isA<Icon>());
      expect(
        (watchDestination.selectedIcon! as Icon).icon,
        Symbols.live_tv_rounded,
      );
      expect((watchDestination.selectedIcon! as Icon).fill, 1);

      expect(
        find.byKey(const Key('sanmill_navigation_drawer_button')),
        findsNothing,
      );
      expect(find.byKey(const Key('sanmill_navigation_drawer')), findsNothing);

      final SanmillAppShellState shellState = tester
          .state<SanmillAppShellState>(find.byType(SanmillAppShell));
      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(find.byKey(const Key('sanmill_tab_focus_home')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.homeRoot.value,
      );
      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      final Text homeAppBarTitle = tester.widget<Text>(
        find.byKey(const Key('sanmill_home_appbar_title')),
      );
      expect(homeAppBarTitle.data, 'Mill');
      expect(find.byKey(const Key('sanmill_home_play_fab')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_human_vs_ai')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_setup_position')), findsNothing);
      expect(
        find.byKey(const Key('play_area_lichess_bottom_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sanmill_home_play_fab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sanmill_home_play_sheet')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.humanVsAi')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.humanVsAi')),
      );
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(shellState.debugCurrentRouteId, shellState.debugPlayRouteId);
      expect(find.byKey(const Key('human_ai')), findsOneWidget);
      expect(find.byKey(const Key('human_ai_new_game_sheet')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('human_ai_new_game_sheet')), findsNothing);
      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(shellState.debugCurrentRouteId, shellState.debugPlayRouteId);
      expect(find.byKey(const Key('human_ai')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.homeRoot.value,
      );
      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      expect(
        find.byKey(const Key('play_area_lichess_bottom_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sanmill_tab_learn')));
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.learn);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.learnRoot.value,
      );
      expect(find.byKey(const Key('sanmill_learn_list')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_learn_guides_group')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_learn_tools_group')), findsNothing);
      expect(
        find.byKey(const Key('sanmill_learn_how_to_play')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_learn_mill.tools.analysis')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sanmill_learn_mill.tools.openingExplorer')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('how_to_play_screen_scaffold')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sanmill_learn_how_to_play')));
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentRouteId, ShellRouteIds.appHowToPlay.value);
      expect(
        find.byKey(const Key('how_to_play_screen_scaffold')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.learn);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.learnRoot.value,
      );
      expect(find.byKey(const Key('sanmill_learn_list')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sanmill_tab_puzzles')));
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.puzzles);
      expect(find.byKey(const Key('puzzles_home_list')), findsOneWidget);
      expect(
        find.byKey(const Key('puzzles_home_progress_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('puzzles_home_modes_section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('puzzles_home_daily')), findsOneWidget);
      expect(find.byKey(const Key('puzzles_home_all')), findsOneWidget);
      expect(find.byKey(const Key('puzzles_home_rush')), findsOneWidget);
      expect(find.byKey(const Key('puzzles_home_streak')), findsOneWidget);

      await tester.tap(find.byKey(const Key('puzzles_home_daily')));
      await tester.pumpAndSettle();

      final BuildContext dailyPuzzleContext = tester.element(
        find.byKey(const Key('daily_puzzle_page_scaffold')),
      );
      final Scaffold dailyPuzzleScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('daily_puzzle_page_scaffold')),
      );
      expect(
        dailyPuzzleScaffold.backgroundColor,
        Theme.of(dailyPuzzleContext).colorScheme.surface,
      );
      expect(
        find.byKey(const Key('daily_puzzle_card')).evaluate().isNotEmpty ||
            find
                .byKey(const Key('daily_puzzle_empty_state'))
                .evaluate()
                .isNotEmpty,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_all')));
      await tester.pumpAndSettle();

      final BuildContext puzzleListContext = tester.element(
        find.byKey(const Key('puzzle_list_page_scaffold')),
      );
      final Scaffold puzzleListScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('puzzle_list_page_scaffold')),
      );
      expect(
        puzzleListScaffold.backgroundColor,
        Theme.of(puzzleListContext).colorScheme.surface,
      );
      expect(
        find.byKey(const Key('puzzle_list_page_list')).evaluate().isNotEmpty ||
            find
                .byKey(const Key('puzzle_list_empty_state'))
                .evaluate()
                .isNotEmpty,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_rush')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_rush')));
      await tester.pumpAndSettle();

      final BuildContext puzzleRushContext = tester.element(
        find.byKey(const Key('puzzle_rush_setup_scaffold')),
      );
      final Scaffold puzzleRushScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('puzzle_rush_setup_scaffold')),
      );
      expect(
        puzzleRushScaffold.backgroundColor,
        Theme.of(puzzleRushContext).colorScheme.surface,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_streak')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_streak')));
      await tester.pumpAndSettle();

      final BuildContext puzzleStreakContext = tester.element(
        find.byKey(const Key('puzzle_streak_setup_scaffold')),
      );
      final Scaffold puzzleStreakScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('puzzle_streak_setup_scaffold')),
      );
      expect(
        puzzleStreakScaffold.backgroundColor,
        Theme.of(puzzleStreakContext).colorScheme.surface,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_custom')));
      await tester.pumpAndSettle();

      final BuildContext customPuzzlesContext = tester.element(
        find.byKey(const Key('custom_puzzles_page_scaffold')),
      );
      final Scaffold customPuzzlesScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('custom_puzzles_page_scaffold')),
      );
      expect(
        customPuzzlesScaffold.backgroundColor,
        Theme.of(customPuzzlesContext).colorScheme.surface,
      );
      expect(
        find
                .byKey(const Key('custom_puzzles_page_list'))
                .evaluate()
                .isNotEmpty ||
            find
                .byKey(const Key('custom_puzzles_empty_state'))
                .evaluate()
                .isNotEmpty,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_history')));
      await tester.pumpAndSettle();

      final BuildContext puzzleHistoryContext = tester.element(
        find.byKey(const Key('puzzle_history_page_scaffold')),
      );
      final Scaffold puzzleHistoryScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('puzzle_history_page_scaffold')),
      );
      expect(
        puzzleHistoryScaffold.backgroundColor,
        Theme.of(puzzleHistoryContext).colorScheme.surface,
      );
      expect(
        find.byKey(const Key('puzzle_history_filter_button')),
        findsOneWidget,
      );
      expect(
        find
                .byKey(const Key('puzzle_history_page_list'))
                .evaluate()
                .isNotEmpty ||
            find
                .byKey(const Key('puzzle_history_empty_state'))
                .evaluate()
                .isNotEmpty,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('puzzles_home_stats')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('puzzles_home_stats')));
      await tester.pumpAndSettle();

      final BuildContext puzzleStatsContext = tester.element(
        find.byKey(const Key('puzzle_stats_page_scaffold')),
      );
      final Scaffold puzzleStatsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('puzzle_stats_page_scaffold')),
      );
      expect(
        puzzleStatsScaffold.backgroundColor,
        Theme.of(puzzleStatsContext).colorScheme.surface,
      );
      expect(find.byKey(const Key('puzzle_stats_page_list')), findsOneWidget);
      expect(
        find.byKey(const Key('puzzle_stats_rating_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('puzzle_stats_performance_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('puzzle_stats_activity_section')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sanmill_tab_watch')));
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.watch);
      expect(find.byKey(const Key('sanmill_watch_list')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_watch_replay_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_watch_statistics_group')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_watch_load_game')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_statistics')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sanmill_watch_load_game')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final BuildContext savedGamesContext = tester.element(
        find.byKey(const Key('saved_games_page_scaffold')),
      );
      final Scaffold savedGamesScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('saved_games_page_scaffold')),
      );
      expect(
        savedGamesScaffold.backgroundColor,
        Theme.of(savedGamesContext).colorScheme.surface,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('drawer_item_statistics')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('statistics_page_scaffold')), findsOneWidget);
      expect(
        find.byKey(const Key('statistics_page_human_rating_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('statistics_page_games_played_row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('statistics_page_ai_statistics_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('statistics_page_ai_level_1')),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sanmill_tab_more')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sanmill_more_list'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_tab_focus_more')), findsOneWidget);
      final Text moreAppBarTitle = tester.widget<Text>(
        find.byKey(const Key('sanmill_more_appbar_title')),
      );
      expect(moreAppBarTitle.data, 'Mill');
      expect(find.byKey(const Key('more_human_vs_ai')), findsNothing);
      expect(find.byKey(const Key('drawer_item_tools_group')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_import_game')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_analysis')), findsOneWidget);
      expect(
        find.byKey(const Key('drawer_item_opening_explorer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('drawer_item_setup_position')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('drawer_item_import_game')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('import_game_page_scaffold')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('import_game_from_file_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('import_game_from_clipboard_button')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('drawer_item_analysis')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('analysis_panel_page_scaffold')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final BuildContext settingsTileContext = tester.element(
        find.byKey(const Key('drawer_item_general_settings')),
      );
      expect(
        ListTileTheme.of(settingsTileContext).iconColor,
        Theme.of(settingsTileContext).colorScheme.primary,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('drawer_item_settings_group')),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('drawer_item_general_settings')),
          matching: find.byType(Card),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('drawer_item_general_settings')),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('drawer_item_general_settings')));
      await tester.pumpAndSettle();

      final BuildContext generalSettingsContext = tester.element(
        find.byKey(const Key('general_settings_page_scaffold')),
      );
      final Scaffold generalSettingsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('general_settings_page_scaffold')),
      );
      expect(
        generalSettingsScaffold.backgroundColor,
        Theme.of(generalSettingsContext).colorScheme.surface,
      );
      expect(
        shellState.debugCurrentRouteId,
        ShellRouteIds.appGeneralSettings.value,
      );

      await tester.ensureVisible(
        find.byKey(
          const Key(
            'general_settings_page_settings_card_ais_play_style_advanced_search',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key(
            'general_settings_page_settings_card_ais_play_style_advanced_search',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder advancedAiScaffoldFinder = find.descendant(
        of: find.byKey(const Key('advanced_ai_search_page')),
        matching: find.byType(Scaffold),
      );
      final BuildContext advancedAiContext = tester.element(
        advancedAiScaffoldFinder,
      );
      final Scaffold advancedAiScaffold = tester.widget<Scaffold>(
        advancedAiScaffoldFinder,
      );
      expect(
        advancedAiScaffold.backgroundColor,
        Theme.of(advancedAiContext).colorScheme.surface,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('drawer_item_rule_settings')));
      await tester.pumpAndSettle();

      final BuildContext ruleSettingsContext = tester.element(
        find.byKey(const Key('rule_settings_scaffold')),
      );
      final Scaffold ruleSettingsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('rule_settings_scaffold')),
      );
      expect(
        ruleSettingsScaffold.backgroundColor,
        Theme.of(ruleSettingsContext).colorScheme.surface,
      );
      expect(
        shellState.debugCurrentRouteId,
        ShellRouteIds.appRuleSettings.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('drawer_item_appearance')));
      await tester.pumpAndSettle();

      final BuildContext appearanceSettingsContext = tester.element(
        find.byKey(const Key('appearance_settings_page_scaffold')),
      );
      final Scaffold appearanceSettingsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('appearance_settings_page_scaffold')),
      );
      expect(
        appearanceSettingsScaffold.backgroundColor,
        Theme.of(appearanceSettingsContext).colorScheme.surface,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('appearance_settings_page_appbar')),
          matching: find.byType(BackButton),
        ),
        findsOneWidget,
      );
      expect(shellState.debugCurrentRouteId, ShellRouteIds.appAppearance.value);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.homeRoot.value,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Opening explorer uses split panes in landscape',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(960, 540)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());

      await tester.tap(find.byKey(const Key('sanmill_tab_more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('drawer_item_opening_explorer')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drawer_item_opening_explorer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('opening_explorer_list')), findsOneWidget);
      expect(
        find.byKey(const Key('opening_explorer_board_pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_data_pane')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('opening_explorer_board')), findsOneWidget);
      expect(
        find.byKey(const Key('opening_explorer_position_card')),
        findsOneWidget,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home tab uses split content on wide screens',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(960, 540)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_home_wide_content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_play_modes_group')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('drawer_item_human_vs_ai')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_home_play_fab')), findsNothing);

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Developer options use the themed settings surface',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: DeveloperOptionsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final BuildContext developerOptionsContext = tester.element(
        find.byKey(const Key('developer_options_page_scaffold')),
      );
      final Scaffold developerOptionsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('developer_options_page_scaffold')),
      );
      expect(
        developerOptionsScaffold.backgroundColor,
        Theme.of(developerOptionsContext).colorScheme.surface,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'PuzzleCard uses a flat themed list-card surface',
    (WidgetTester tester) async {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test-puzzle',
        title: 'Opening tactic',
        description: 'Find the forcing mill.',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.medium,
        initialPosition: '********/********/******** w p p 0 9 0 9 0 0',
        solutions: const <PuzzleSolution>[],
      );
      final PuzzleProgress progress = PuzzleProgress(
        puzzleId: puzzle.id,
        completed: true,
        stars: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Center(
              child: PuzzleCard(
                puzzle: puzzle,
                progress: progress,
                showCustomBadge: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder cardFinder = find.byKey(
        const Key('puzzle_card_test-puzzle'),
      );
      final BuildContext cardContext = tester.element(cardFinder);
      final Card card = tester.widget<Card>(cardFinder);
      expect(card.elevation, 0);
      expect(card.color, Theme.of(cardContext).colorScheme.surfaceContainer);
      expect(find.text('Opening tactic'), findsOneWidget);
      expect(find.byType(MiniBoard), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'PuzzleCreationPage uses themed flat section surfaces',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const PuzzleCreationPage(),
        ),
      );
      await tester.pump();

      final Finder scaffoldFinder = find.byKey(
        const Key('puzzle_creation_page_scaffold'),
      );
      final BuildContext pageContext = tester.element(scaffoldFinder);
      final Scaffold scaffold = tester.widget<Scaffold>(scaffoldFinder);
      expect(
        scaffold.backgroundColor,
        Theme.of(pageContext).colorScheme.surface,
      );

      final Card firstSection = tester.widget<Card>(find.byType(Card).first);
      expect(firstSection.elevation, 0);
      expect(
        firstSection.color,
        Theme.of(pageContext).colorScheme.surfaceContainer,
      );
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Repeated puzzle tab tap scrolls the root list to top',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 480)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());

      await tester.tap(find.byKey(const Key('sanmill_tab_puzzles')));
      await tester.pumpAndSettle();

      final Finder puzzlesScrollable = find.descendant(
        of: find.byKey(const Key('puzzles_home_list')),
        matching: find.byType(Scrollable),
      );
      final ScrollableState scrollable = tester.state<ScrollableState>(
        puzzlesScrollable,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      await tester.drag(
        find.byKey(const Key('puzzles_home_list')),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));

      await tester.tap(find.byKey(const Key('sanmill_tab_puzzles')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, moreOrLessEquals(0, epsilon: 0.5));

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );
}
