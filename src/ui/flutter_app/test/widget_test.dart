// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// widget_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import flutter services
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sanmill/app_shell/sanmill_app_shell.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';
import 'package:sanmill/appearance_settings/widgets/theme_selection_page.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/game_platform/game_session.dart' as platform;
import 'package:sanmill/game_shell/shell_route_ids.dart';
import 'package:sanmill/games/built_in_game_modules.dart';
import 'package:sanmill/games/mill/mill_board_geometry.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';
import 'package:sanmill/games/mill/opening_explorer/opening_explorer_page.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/general_settings/widgets/developer_options_page.dart';
import 'package:sanmill/generated/assets/assets.gen.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/learn/mill_coordinate_training_page.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/misc/mill_variants_page.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/puzzle_creation_page.dart';
import 'package:sanmill/puzzle/widgets/puzzle_card.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/system_ui_service.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_bottom_bar.dart';

import 'games/mill/opening_book/opening_book_test_assets.dart';
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

    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
    await OpeningBookRepository.instance.ensureLoaded();

    // Register the built-in game modules, mirroring main(): the Home
    // shell asserts that a module is registered for the active GameId.
    registerBuiltInGameModules(GameRegistry.instance);

    await initializeUI(true);
  });

  tearDownAll(() {
    OpeningBookRepository.instance.resetForTest();
    disposeRustLibForTests();
  });

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
    'Rule onboarding is dismissed after choosing no',
    (WidgetTester tester) async {
      final GeneralSettings originalGeneralSettings = DB().generalSettings;
      final DisplaySettings originalDisplaySettings = DB().displaySettings;
      final bool originalTestEnvironment = EnvironmentConfig.test;

      DB().generalSettings = GeneralSettings.fromJson(
        Map<String, dynamic>.from(originalGeneralSettings.toJson())
          ..['firstRun'] = false
          ..['showTutorial'] = true,
      );
      DB().displaySettings = originalDisplaySettings.copyWith(
        locale: const Locale('zh'),
      );
      EnvironmentConfig.test = false;

      try {
        await tester.pumpWidget(const SanmillApp());
        await tester.pumpAndSettle();

        expect(find.text('配置规则'), findsOneWidget);
        await tester.tap(find.text('否'));
        await tester.pumpAndSettle();
        expect(DB().generalSettings.showTutorial, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SanmillApp());
        await tester.pumpAndSettle();

        expect(find.text('配置规则'), findsNothing);
      } finally {
        EnvironmentConfig.test = originalTestEnvironment;
        DB().generalSettings = originalGeneralSettings;
        DB().displaySettings = originalDisplaySettings;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 350));
      }
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Learn tab starts with coordinate training',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());
      await tester.tap(find.byKey(const Key('sanmill_tab_learn')));
      await tester.pumpAndSettle();

      final Finder coordinateTraining = find.byKey(
        const Key('sanmill_learn_coordinate_training'),
      );
      final Finder guidesHeader = find.byKey(
        const Key('sanmill_learn_guides_group'),
      );

      expect(find.byKey(const Key('sanmill_learn_list')), findsOneWidget);
      expect(coordinateTraining, findsOneWidget);
      expect(guidesHeader, findsOneWidget);
      expect(find.byKey(const Key('sanmill_learn_tools_group')), findsNothing);
      expect(
        tester.getTopLeft(coordinateTraining).dy,
        lessThan(tester.getTopLeft(guidesHeader).dy),
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home play sheet promotes LAN play with friend mode',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());

      await tester.tap(find.byKey(const Key('sanmill_home_play_fab')));
      await tester.pumpAndSettle();

      final Finder quickStartCard = find.byKey(
        const Key('sanmill_home_play_sheet_card'),
      );
      final Finder moreModesCard = find.byKey(
        const Key('sanmill_home_play_sheet_more_modes_card'),
      );
      final Finder lanMode = find.byKey(
        const Key('sanmill_home_play_sheet_mill.play.humanVsLan'),
      );

      expect(find.byKey(const Key('sanmill_home_play_sheet')), findsOneWidget);
      expect(
        find.descendant(of: quickStartCard, matching: lanMode),
        findsOneWidget,
      );
      expect(
        find.descendant(of: moreModesCard, matching: lanMode),
        findsNothing,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home empty state keeps game lists visible',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      expect(find.byKey(const Key('sanmill_home_empty_start')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_home_empty_ongoing_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_empty_ongoing_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_empty_ongoing_games')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_home_welcome_group')), findsNothing);
      expect(
        find.byKey(const Key('sanmill_home_quick_start_group')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sanmill_home_empty_recent_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_empty_recent_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_empty_recent_games')),
        findsOneWidget,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'More tools follow Lichess-style order',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(const Key('sanmill_tab_more')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('drawer_item_opening_explorer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('drawer_item_setup_position')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('drawer_item_clock')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_variants')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_import_game')), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_analysis')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('drawer_item_import_game'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('drawer_item_analysis'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('drawer_item_analysis'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('drawer_item_opening_explorer')))
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('drawer_item_opening_explorer')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('drawer_item_setup_position')))
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('drawer_item_setup_position')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('drawer_item_clock'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('drawer_item_clock'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('drawer_item_variants'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('drawer_item_variants'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('drawer_item_clock'))).dy,
        ),
      );

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
      final GeneralSettings originalGeneralSettings = DB().generalSettings;
      DB().generalSettings = GeneralSettings.fromJson(
        Map<String, dynamic>.from(originalGeneralSettings.toJson())
          ..['aiChatEnabled'] = true,
      );
      addTearDown(() {
        DB().generalSettings = originalGeneralSettings;
        AnalysisMode.setShowEngineLines(true);
        AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
      });
      AnalysisMode.setShowEngineLines(true);
      AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);

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
      expect(find.text('Quick pairing'), findsNothing);
      expect(find.byKey(const Key('drawer_item_human_vs_ai')), findsNothing);
      expect(find.byKey(const Key('drawer_item_setup_position')), findsNothing);
      expect(
        find.byKey(const Key('play_area_lichess_bottom_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sanmill_home_play_fab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sanmill_home_play_sheet')), findsOneWidget);
      expect(find.text('Quick pairing'), findsNothing);
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_quick_start_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_more_modes_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.humanVsAi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.humanVsHuman')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.aiVsAi')),
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
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsNothing,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('human_ai_new_game_sheet')), findsNothing);
      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(shellState.debugCurrentRouteId, shellState.debugPlayRouteId);
      expect(find.byKey(const Key('human_ai')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('game_page_top_right_buttons_align')),
        findsNothing,
      );
      expect(find.byKey(const Key('game_page_ai_chat_button')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.homeRoot.value,
      );
      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsOneWidget,
      );
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
        find.byKey(const Key('sanmill_learn_coordinate_training')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sanmill_learn_tutorial')), findsOneWidget);
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

      await tester.tap(
        find.byKey(const Key('sanmill_learn_coordinate_training')),
      );
      await tester.pumpAndSettle();

      final BuildContext coordinateTrainingContext = tester.element(
        find.byKey(const Key('mill_coordinate_training_page_scaffold')),
      );
      final Scaffold coordinateTrainingScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('mill_coordinate_training_page_scaffold')),
      );
      expect(
        coordinateTrainingScaffold.backgroundColor,
        Theme.of(coordinateTrainingContext).colorScheme.surface,
      );
      expect(
        shellState.debugCurrentRouteId,
        ShellRouteIds.appCoordinateTraining.value,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_board')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_start_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('mill_coordinate_training_menu_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mill_coordinate_training_duration_60')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('mill_coordinate_training_duration_60')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('mill_coordinate_training_start_button')),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('mill_coordinate_training_score')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_current_coordinate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_next_coordinate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_action_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_coordinate_training_bottom_bar')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('mill_coordinate_training_action_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mill_coordinate_training_start_button')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

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
      expect(find.text('Board editor'), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_clock')), findsOneWidget);
      expect(find.text('Clock'), findsOneWidget);
      expect(find.byKey(const Key('drawer_item_variants')), findsOneWidget);
      expect(find.text('Variants'), findsOneWidget);

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
        find.byKey(const Key('import_game_scan_qr_button')),
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

      expect(GameController().gameInstance.gameMode, GameMode.analysis);
      expect(find.byKey(const Key('game_page_scaffold')), findsOneWidget);
      expect(
        find.byKey(const Key('game_page_analysis_appbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('game_page_analysis_appbar_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('game_page_analysis_menu_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('game_page_top_left_button_align')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('game_page_analysis_menu_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('game_page_analysis_menu_settings')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('game_page_analysis_menu_engine_lines')),
        findsOneWidget,
      );
      expect(AnalysisMode.showEngineLines, isTrue);

      await tester.tap(
        find.byKey(const Key('game_page_analysis_menu_engine_lines')),
      );
      await tester.pumpAndSettle();

      expect(AnalysisMode.showEngineLines, isFalse);

      await tester.tap(find.byKey(const Key('game_page_analysis_menu_button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('game_page_analysis_menu_settings')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('play_area_analysis_settings_sheet')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('play_area_analysis_settings_close')),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('drawer_item_clock')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clock_tool_page_scaffold')), findsOneWidget);
      expect(find.byKey(const Key('clock_tool_top_tile')), findsOneWidget);
      expect(find.byKey(const Key('clock_tool_bottom_tile')), findsOneWidget);
      expect(
        find.byKey(const Key('clock_tool_start_pause_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('clock_tool_close_button')), findsOneWidget);
      expect(find.byKey(const Key('clock_tool_reset_button')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('drawer_item_variants')));
      await tester.pumpAndSettle();

      final BuildContext variantsContext = tester.element(
        find.byKey(const Key('mill_variants_page_scaffold')),
      );
      final Scaffold variantsScaffold = tester.widget<Scaffold>(
        find.byKey(const Key('mill_variants_page_scaffold')),
      );
      expect(
        variantsScaffold.backgroundColor,
        Theme.of(variantsContext).colorScheme.surface,
      );
      expect(shellState.debugCurrentRouteId, ShellRouteIds.appVariants.value);
      expect(
        find.byKey(const Key('mill_variant_standard_9mm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mill_variant_twelve_mens_morris')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final BuildContext settingsTileContext = tester.element(
        find.byKey(const Key('drawer_item_settings')),
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
          of: find.byKey(const Key('drawer_item_settings')),
          matching: find.byType(Card),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('drawer_item_settings')),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('drawer_item_settings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_hub_list')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        ShellRouteIds.appSettingsGroup.value,
      );
      expect(
        find.byKey(const Key('settings_hub_general_settings')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_hub_rule_settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings_hub_appearance')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_hub_appearance')),
          matching: find.text('Board'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_hub_appearance')),
          matching: find.text('Appearance'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('settings_hub_general_settings')));
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
        ShellRouteIds.appSettingsGroup.value,
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
      expect(find.byKey(const Key('settings_hub_list')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('settings_hub_rule_settings')));
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
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(find.byKey(const Key('settings_hub_list')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.tap(find.byKey(const Key('settings_hub_appearance')));
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
      final Text appearanceTitle = tester.widget<Text>(
        find.byKey(const Key('appearance_settings_page_appbar_title')),
      );
      expect(appearanceTitle.data, 'Board');
      expect(
        find.descendant(
          of: find.byKey(const Key('appearance_settings_page_appbar')),
          matching: find.byType(BackButton),
        ),
        findsOneWidget,
      );
      final Finder boardThemeTile = find.byKey(
        const Key('color_settings_card_theme_settings_list_tile'),
      );
      expect(boardThemeTile, findsOneWidget);
      await tester.scrollUntilVisible(
        boardThemeTile,
        320,
        scrollable: find.descendant(
          of: find.byKey(const Key('settings_list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final Finder pieceSetTile = find.byKey(
        const Key('display_settings_card_piece_image_settings_list_tile'),
      );
      final Finder boardCoordinatesTile = find.byKey(
        const Key('display_settings_card_notations_shown_switch_tile'),
      );
      final Finder pieceAnimationTile = find.byKey(
        const Key(
          'display_settings_card_piece_pick_up_animation_enabled_switch_tile',
        ),
      );
      final Finder boardImageTile = find.byKey(
        const Key('display_settings_card_board_image_settings_list_tile'),
      );
      final Finder backgroundImageTile = find.byKey(
        const Key('display_settings_card_background_image_settings_list_tile'),
      );
      expect(pieceSetTile, findsOneWidget);
      expect(boardCoordinatesTile, findsOneWidget);
      expect(pieceAnimationTile, findsOneWidget);
      expect(boardImageTile, findsOneWidget);
      expect(backgroundImageTile, findsOneWidget);
      expect(
        tester.getTopLeft(pieceSetTile).dy,
        greaterThan(tester.getTopLeft(boardThemeTile).dy),
      );
      expect(
        tester.getTopLeft(boardCoordinatesTile).dy,
        greaterThan(tester.getTopLeft(pieceSetTile).dy),
      );
      expect(
        tester.getTopLeft(pieceAnimationTile).dy,
        greaterThan(tester.getTopLeft(boardCoordinatesTile).dy),
      );
      expect(
        tester.getTopLeft(boardImageTile).dy,
        greaterThan(tester.getTopLeft(pieceAnimationTile).dy),
      );
      expect(
        tester.getTopLeft(backgroundImageTile).dy,
        greaterThan(tester.getTopLeft(boardImageTile).dy),
      );
      final Finder displaySettings = find.byKey(
        const Key('appearance_settings_page_display_settings_card'),
      );
      final Finder colorTuning = find.byKey(
        const Key('appearance_settings_page_board_color_settings_card'),
      );
      final Finder appearanceScrollable = find.descendant(
        of: find.byKey(const Key('settings_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        displaySettings,
        320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();
      final double displaySettingsOffset = tester
          .state<ScrollableState>(appearanceScrollable)
          .position
          .pixels;
      await tester.scrollUntilVisible(
        colorTuning,
        320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();
      expect(colorTuning, findsOneWidget);
      final double colorTuningOffset = tester
          .state<ScrollableState>(appearanceScrollable)
          .position
          .pixels;
      expect(colorTuningOffset, greaterThan(displaySettingsOffset));
      await tester.scrollUntilVisible(
        pieceSetTile,
        -320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(pieceSetTile);
      await tester.pumpAndSettle();

      final Finder pieceSelectionPage = find.byKey(
        const Key('piece_image_selection_page'),
      );
      expect(pieceSelectionPage, findsOneWidget);
      final Finder pieceSelectionScrollable = find.descendant(
        of: find.byKey(const Key('piece_image_selection_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('piece_image_selection_player1_card')),
        320,
        scrollable: pieceSelectionScrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('piece_image_selection_player1_card')),
        findsOneWidget,
      );
      final ListTile player1SolidTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('piece_image_selection_player1_0')),
          matching: find.byType(ListTile),
        ),
      );
      expect(player1SolidTile.selected, isTrue);
      expect(
        find.byKey(const Key('piece_image_selection_solid_color_preview')),
        findsWidgets,
      );

      await tester.tap(
        find.byKey(const Key('piece_image_selection_player1_1')),
      );
      await tester.pumpAndSettle();
      final ListTile player1ImageTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('piece_image_selection_player1_1')),
          matching: find.byType(ListTile),
        ),
      );
      expect(player1ImageTile.selected, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(find.byKey(const Key('settings_hub_list')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(shellState.debugCurrentTab, SanmillShellTab.more);
      expect(find.byKey(const Key('sanmill_more_list')), findsOneWidget);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.moreRoot.value,
      );

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));

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

  testWidgets('Coordinate training mirrors Lichess default toggles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightThemeData,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const MillCoordinateTrainingPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mill_coordinate_training_board')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('mill_coordinate_training_time_bar')))
          .height,
      15,
    );

    await tester.tap(
      find.byKey(const Key('mill_coordinate_training_settings_button')),
    );
    await tester.pumpAndSettle();

    final SwitchListTile showCoordinatesTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('mill_coordinate_training_show_coordinates')),
    );
    final SwitchListTile showPiecesTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('mill_coordinate_training_show_pieces')),
    );
    expect(showCoordinatesTile.value, isFalse);
    expect(showPiecesTile.value, isTrue);

    expect(
      find.byKey(const Key('mill_coordinate_training_duration_30')),
      findsNothing,
    );

    Navigator.of(
      tester.element(find.byKey(const Key('mill_coordinate_training_board'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('mill_coordinate_training_menu_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mill_coordinate_training_orientation_random')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mill_coordinate_training_orientation_board')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const Key('mill_coordinate_training_orientation_random'),
        ),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('mill_coordinate_training_orientation_board')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('mill_coordinate_training_menu_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('mill_coordinate_training_orientation_board')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mill_coordinate_training_duration_30')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mill_coordinate_training_show_coordinates')),
      findsNothing,
    );
  });

  testWidgets('Variants page opens detail before applying a rule set', (
    WidgetTester tester,
  ) async {
    final RuleSettings previousRuleSettings = DB().ruleSettings;
    addTearDown(() {
      DB().ruleSettings = previousRuleSettings;
    });
    DB().ruleSettings = const RuleSettings();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightThemeData,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const MillVariantsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mill_variants_section_card')), findsOneWidget);
    expect(
      find.byKey(const Key('mill_variants_mainline_header')),
      findsNothing,
    );
    expect(find.byKey(const Key('mill_variants_capture_header')), findsNothing);
    expect(find.byKey(const Key('mill_variants_rules_header')), findsNothing);
    expect(
      find.byKey(const Key('mill_variants_capture_section_card')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('mill_variants_rules_section_card')),
      findsNothing,
    );
    final ListTile standardVariantTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('mill_variant_standard_9mm')),
        matching: find.byType(ListTile),
      ),
    );
    expect(standardVariantTile.leading, isNull);

    await tester.tap(find.byKey(const Key('mill_variant_twelve_mens_morris')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mill_variant_detail_twelve_mens_morris')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mill_variant_detail_rules_twelve_mens_morris')),
      findsOneWidget,
    );
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byIcon(Icons.category_outlined), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(
          const Key('mill_variant_detail_rules_twelve_mens_morris'),
        ),
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
      findsNothing,
    );
    final Iterable<ListTile> detailRuleTiles = tester.widgetList<ListTile>(
      find.descendant(
        of: find.byKey(
          const Key('mill_variant_detail_rules_twelve_mens_morris'),
        ),
        matching: find.byType(ListTile),
      ),
    );
    expect(detailRuleTiles, isNotEmpty);
    expect(
      detailRuleTiles.every((ListTile tile) => tile.leading == null),
      isTrue,
    );
    expect(DB().ruleSettings.piecesCount, 9);

    await tester.tap(find.byKey(const Key('mill_variant_detail_apply_button')));
    await tester.pumpAndSettle();

    expect(DB().ruleSettings.piecesCount, 12);
    expect(find.byKey(const Key('mill_variants_page_list')), findsOneWidget);
  });

  testWidgets('Appearance board settings follow Lichess primary order', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightThemeData,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const AppearanceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder boardThemeTile = find.byKey(
      const Key('color_settings_card_theme_settings_list_tile'),
    );
    final Finder pieceSetTile = find.byKey(
      const Key('display_settings_card_piece_image_settings_list_tile'),
    );
    final Finder boardCoordinatesTile = find.byKey(
      const Key('display_settings_card_notations_shown_switch_tile'),
    );
    final Finder pieceAnimationTile = find.byKey(
      const Key(
        'display_settings_card_piece_pick_up_animation_enabled_switch_tile',
      ),
    );
    final Finder boardImageTile = find.byKey(
      const Key('display_settings_card_board_image_settings_list_tile'),
    );

    expect(boardThemeTile, findsOneWidget);
    expect(pieceSetTile, findsOneWidget);
    expect(boardCoordinatesTile, findsOneWidget);
    expect(pieceAnimationTile, findsOneWidget);
    expect(boardImageTile, findsOneWidget);
    expect(
      tester.getTopLeft(pieceSetTile).dy,
      greaterThan(tester.getTopLeft(boardThemeTile).dy),
    );
    expect(
      tester.getTopLeft(boardCoordinatesTile).dy,
      greaterThan(tester.getTopLeft(pieceSetTile).dy),
    );
    expect(
      tester.getTopLeft(pieceAnimationTile).dy,
      greaterThan(tester.getTopLeft(boardCoordinatesTile).dy),
    );
    expect(
      tester.getTopLeft(boardImageTile).dy,
      greaterThan(tester.getTopLeft(pieceAnimationTile).dy),
    );
  });

  testWidgets(
    'Appearance board theme uses full-screen board selector',
    (WidgetTester tester) async {
      final ColorSettings previousColorSettings = DB().colorSettings;
      final List<ColorSettings> previousCustomThemes = List<ColorSettings>.of(
        DB().customThemes,
      );
      addTearDown(() {
        DB().colorSettings = previousColorSettings;
        DB().customThemes = previousCustomThemes;
      });

      DB().colorSettings = AppTheme.colorThemes[ColorTheme.light]!;
      DB().customThemes = <ColorSettings>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: const AppearanceSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder boardThemeTile = find.byKey(
        const Key('color_settings_card_theme_settings_list_tile'),
      );
      final Finder appearanceScrollable = find.descendant(
        of: find.byKey(const Key('settings_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        boardThemeTile,
        320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();

      final ListTile boardThemeListTile = tester.widget<ListTile>(
        find.descendant(of: boardThemeTile, matching: find.byType(ListTile)),
      );
      expect(
        (boardThemeListTile.leading! as Icon).icon,
        Icons.dashboard_outlined,
      );

      await tester.tap(boardThemeTile);
      await tester.pumpAndSettle();

      expect(find.byType(ThemeSelectionPage), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Board')),
        findsOneWidget,
      );

      final ThemePreviewItem currentTheme = tester.widget<ThemePreviewItem>(
        find.byKey(const Key('theme_preview_current')),
      );
      final ThemePreviewItem lightTheme = tester.widget<ThemePreviewItem>(
        find.byKey(const Key('theme_preview_light')),
      );
      expect(currentTheme.isSelected, isFalse);
      expect(lightTheme.isSelected, isTrue);
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets('Appearance board theme label ignores shell colors', (
    WidgetTester tester,
  ) async {
    final ColorSettings previousColorSettings = DB().colorSettings;
    addTearDown(() => DB().colorSettings = previousColorSettings);

    final ColorSettings lightTheme = AppTheme.colorThemes[ColorTheme.light]!;
    DB().colorSettings = lightTheme.copyWith(
      drawerColor: Colors.pink,
      drawerTextColor: Colors.orange,
      mainToolbarBackgroundColor: Colors.red,
      mainToolbarIconColor: Colors.green,
      navigationToolbarBackgroundColor: Colors.yellow,
      navigationToolbarIconColor: Colors.blue,
      analysisToolbarBackgroundColor: Colors.purple,
      analysisToolbarIconColor: Colors.cyan,
      annotationToolbarBackgroundColor: Colors.brown,
      annotationToolbarIconColor: Colors.teal,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightThemeData,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const AppearanceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder boardThemeTile = find.byKey(
      const Key('color_settings_card_theme_settings_list_tile'),
    );
    expect(
      find.descendant(of: boardThemeTile, matching: find.text('Light')),
      findsOneWidget,
    );
  });

  testWidgets('Appearance board theme selection preserves shell colors', (
    WidgetTester tester,
  ) async {
    final ColorSettings previousColorSettings = DB().colorSettings;
    addTearDown(() => DB().colorSettings = previousColorSettings);

    final ColorSettings lightTheme = AppTheme.colorThemes[ColorTheme.light]!;
    final ColorSettings darkTheme = AppTheme.colorThemes[ColorTheme.dark]!;
    DB().colorSettings = lightTheme.copyWith(
      drawerColor: Colors.pink,
      drawerTextColor: Colors.orange,
      mainToolbarBackgroundColor: Colors.red,
      mainToolbarIconColor: Colors.green,
      navigationToolbarBackgroundColor: Colors.yellow,
      navigationToolbarIconColor: Colors.blue,
      analysisToolbarBackgroundColor: Colors.purple,
      analysisToolbarIconColor: Colors.cyan,
      annotationToolbarBackgroundColor: Colors.brown,
      annotationToolbarIconColor: Colors.teal,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightThemeData,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: const AppearanceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('color_settings_card_theme_settings_list_tile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_preview_dark')));
    await tester.pumpAndSettle();

    final ColorSettings updated = DB().colorSettings;
    expect(updated.boardLineColor, darkTheme.boardLineColor);
    expect(updated.boardBackgroundColor, darkTheme.boardBackgroundColor);
    expect(updated.whitePieceColor, darkTheme.whitePieceColor);
    expect(updated.blackPieceColor, darkTheme.blackPieceColor);
    expect(updated.pieceHighlightColor, darkTheme.pieceHighlightColor);
    expect(
      updated.capturablePieceHighlightColor,
      darkTheme.capturablePieceHighlightColor,
    );
    expect(updated.messageColor, darkTheme.messageColor);
    expect(updated.drawerColor, Colors.pink);
    expect(updated.drawerTextColor, Colors.orange);
    expect(updated.mainToolbarBackgroundColor, Colors.red);
    expect(updated.mainToolbarIconColor, Colors.green);
    expect(updated.navigationToolbarBackgroundColor, Colors.yellow);
    expect(updated.navigationToolbarIconColor, Colors.blue);
    expect(updated.analysisToolbarBackgroundColor, Colors.purple);
    expect(updated.analysisToolbarIconColor, Colors.cyan);
    expect(updated.annotationToolbarBackgroundColor, Colors.brown);
    expect(updated.annotationToolbarIconColor, Colors.teal);
    expect(
      find.descendant(
        of: find.byKey(
          const Key('color_settings_card_theme_settings_list_tile'),
        ),
        matching: find.text('Dark'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Appearance piece set uses full-screen selector',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: Locale('en'),
          home: AppearanceSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder pieceSetTile = find.byKey(
        const Key('display_settings_card_piece_image_settings_list_tile'),
      );
      final Finder appearanceScrollable = find.descendant(
        of: find.byKey(const Key('settings_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        pieceSetTile,
        320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(pieceSetTile);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('piece_image_selection_page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('piece_image_selection_piece_sets_card')),
        findsOneWidget,
      );
      final Finder pieceSelectionScrollable = find.descendant(
        of: find.byKey(const Key('piece_image_selection_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('piece_image_selection_player1_card')),
        320,
        scrollable: pieceSelectionScrollable,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('piece_image_selection_player1_card')),
        findsOneWidget,
      );
      final ListTile player1SolidTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('piece_image_selection_player1_0')),
          matching: find.byType(ListTile),
        ),
      );
      expect(player1SolidTile.selected, isTrue);

      await tester.tap(
        find.byKey(const Key('piece_image_selection_player1_1')),
      );
      await tester.pumpAndSettle();

      final ListTile player1ImageTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('piece_image_selection_player1_1')),
          matching: find.byType(ListTile),
        ),
      );
      expect(player1ImageTile.selected, isTrue);
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Appearance piece set applies paired Lichess-style images',
    (WidgetTester tester) async {
      final DisplaySettings previousDisplaySettings = DB().displaySettings;
      addTearDown(() => DB().displaySettings = previousDisplaySettings);
      DB().displaySettings = const DisplaySettings();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: Locale('en'),
          home: AppearanceSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder pieceSetTile = find.byKey(
        const Key('display_settings_card_piece_image_settings_list_tile'),
      );
      final Finder appearanceScrollable = find.descendant(
        of: find.byKey(const Key('settings_list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        pieceSetTile,
        320,
        scrollable: appearanceScrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(pieceSetTile);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('piece_image_selection_piece_set_1')),
      );
      await tester.pumpAndSettle();

      final DisplaySettings updated = DB().displaySettings;
      expect(updated.whitePieceImagePath, Assets.images.whitePieceImage1.path);
      expect(updated.blackPieceImagePath, Assets.images.blackPieceImage1.path);

      final ListTile selectedSetTile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('piece_image_selection_piece_set_1')),
          matching: find.byType(ListTile),
        ),
      );
      expect(selectedSetTile.selected, isTrue);
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
        find.byKey(const Key('opening_explorer_bottom_bar')),
        findsOneWidget,
      );
      final Finder previousButtonFinder = find.byKey(
        const Key('opening_explorer_previous_button'),
      );
      final Finder nextButtonFinder = find.byKey(
        const Key('opening_explorer_next_button'),
      );
      expect(previousButtonFinder, findsOneWidget);
      expect(nextButtonFinder, findsOneWidget);
      expect(
        tester.widget<LichessBottomBarButton>(previousButtonFinder).onTap,
        isNull,
      );
      expect(
        tester.widget<LichessBottomBarButton>(nextButtonFinder).onTap,
        isNull,
      );
      expect(
        find.byKey(const Key('opening_explorer_move_list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_flip_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('opening_explorer_flip_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('opening_explorer_transform_sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_rotate_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_horizontal_flip_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_vertical_flip_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_inner_outer_flip_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_swap_rotate_180_button')),
        findsNothing,
      );

      Navigator.of(
        tester.element(
          find.byKey(const Key('opening_explorer_transform_sheet')),
        ),
      ).pop();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('opening_explorer_position_card')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('opening_explorer_sources_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('opening_explorer_sources_sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_sources_copy_fen')),
        findsOneWidget,
      );

      Navigator.of(
        tester.element(find.byKey(const Key('opening_explorer_sources_sheet'))),
      ).pop();
      await tester.pumpAndSettle();

      final Finder boardFinder = find.byKey(
        const Key('opening_explorer_board'),
      );
      final Offset boardTopLeft = tester.getTopLeft(boardFinder);
      final Size boardSize = tester.getSize(boardFinder);
      await tester.tapAt(
        boardTopLeft + MillBoardGeometry.nodeOffset(0, boardSize),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<LichessBottomBarButton>(previousButtonFinder).onTap,
        isNotNull,
      );
      expect(
        tester.widget<LichessBottomBarButton>(nextButtonFinder).onTap,
        isNull,
      );
      expect(
        find.byKey(const Key('opening_explorer_history_1')),
        findsOneWidget,
      );

      await tester.tap(previousButtonFinder);
      await tester.pumpAndSettle();

      expect(
        tester.widget<LichessBottomBarButton>(previousButtonFinder).onTap,
        isNull,
      );
      expect(
        tester.widget<LichessBottomBarButton>(nextButtonFinder).onTap,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('opening_explorer_history_1')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<LichessBottomBarButton>(previousButtonFinder).onTap,
        isNotNull,
      );

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Setup position toolbar keeps legacy three-row editor controls',
    (WidgetTester tester) async {
      const Color toolbarMessageColor = Color(0xFFFFE6A3);
      final ColorSettings previousColorSettings = DB().colorSettings;
      addTearDown(() {
        DB().colorSettings = previousColorSettings;
      });
      DB().colorSettings = const ColorSettings(
        messageColor: toolbarMessageColor,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SetupPositionToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('setup_position_three_row_toolbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_buttons_container_row1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_buttons_container_row2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('setup_position_buttons_container_row3')),
        findsOneWidget,
      );
      final Container firstToolbarRow = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(
                const Key('setup_position_buttons_container_row1'),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(firstToolbarRow.color, Colors.transparent);

      expect(find.byKey(const Key('paint_color_button')), findsOneWidget);
      expect(find.byKey(const Key('phase_button')), findsOneWidget);
      expect(find.byKey(const Key('remove_button')), findsOneWidget);
      expect(find.byKey(const Key('placed_button')), findsOneWidget);

      expect(find.byKey(const Key('rotate_button')), findsOneWidget);
      expect(find.byKey(const Key('horizontal_flip_button')), findsOneWidget);
      expect(find.byKey(const Key('vertical_flip_button')), findsOneWidget);
      expect(find.byKey(const Key('inner_outer_flip_button')), findsOneWidget);

      expect(find.byKey(const Key('copy_button')), findsOneWidget);
      expect(find.byKey(const Key('paste_button')), findsOneWidget);
      expect(find.byKey(const Key('clear_button')), findsOneWidget);
      expect(find.byKey(const Key('cancel_button')), findsOneWidget);
      expect(find.byKey(const Key('done_button')), findsOneWidget);

      for (final Key buttonKey in <Key>[
        const Key('paint_color_button'),
        const Key('rotate_button'),
        const Key('copy_button'),
      ]) {
        final ToolbarItemThemeData toolbarTheme = ToolbarItemTheme.of(
          tester.element(find.byKey(buttonKey)),
        );
        final WidgetStateProperty<Color?>? foregroundColor =
            toolbarTheme.style?.foregroundColor;
        assert(
          foregroundColor != null,
          'Setup position toolbar rows must define a foreground color.',
        );
        expect(foregroundColor!.resolve(<WidgetState>{}), toolbarMessageColor);
        expect(
          foregroundColor.resolve(<WidgetState>{WidgetState.disabled}),
          toolbarMessageColor.withValues(alpha: 0.38),
        );
      }

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Opening explorer shows loading rows while opening book loads',
    (WidgetTester tester) async {
      final Completer<String> openingBookCompleter = Completer<String>();
      OpeningBookRepository.instance.resetForTest();
      OpeningBookRepository.instance.assetLoader = (String _) =>
          openingBookCompleter.future;
      addTearDown(() async {
        OpeningBookRepository.instance.resetForTest();
        OpeningBookRepository.instance.assetLoader =
            loadOpeningBookAssetFromDisk;
        await OpeningBookRepository.instance.ensureLoaded();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const OpeningExplorerPage(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('opening_explorer_loading_row_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_loading_row_5')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_no_data_row')),
        findsNothing,
      );

      openingBookCompleter.complete('{}');
      await tester.pumpAndSettle();
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Opening explorer starts from the initial position without a source game',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightThemeData,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const OpeningExplorerPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('opening_explorer_list')), findsOneWidget);
      expect(find.byKey(const Key('opening_explorer_board')), findsOneWidget);
      expect(
        find.byKey(const Key('opening_explorer_in_hand_row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_removed_row')),
        findsOneWidget,
      );
      final Text firstInHandText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('opening_explorer_first_in_hand_count')),
          matching: find.byType(Text),
        ),
      );
      final Text secondInHandText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('opening_explorer_second_in_hand_count')),
          matching: find.byType(Text),
        ),
      );
      final Text firstRemovedText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('opening_explorer_first_removed_count')),
          matching: find.byType(Text),
        ),
      );
      final Text secondRemovedText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('opening_explorer_second_removed_count')),
          matching: find.byType(Text),
        ),
      );
      expect(firstInHandText.data, '●●● 9');
      expect(secondInHandText.data, '●●● 9');
      expect(firstRemovedText.data, isEmpty);
      expect(secondRemovedText.data, isEmpty);
      expect(
        find.byKey(const Key('opening_explorer_bottom_bar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('opening_explorer_position_card')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('opening_explorer_sources_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('opening_explorer_sources_copy_fen')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(find.byKey(const Key('opening_explorer_sources_sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      final S strings = S.of(tester.element(find.byType(OpeningExplorerPage)));
      expect(find.text(strings.openingExplorerUnavailable), findsNothing);
      expect(
        find.byKey(const Key('opening_explorer_opening_card')),
        findsNothing,
      );

      final Finder firstMoveFinder = find.byWidgetPredicate((Widget widget) {
        final Key? key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('opening_explorer_move_');
      }, description: 'rendered opening explorer move row');
      expect(firstMoveFinder, findsWidgets);

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home tab merges the current active game into ongoing games',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final GameController controller = GameController();
      addTearDown(() {
        controller.activeSessionSnapshot = null;
        controller.gameRecorder.reset();
      });

      await tester.pumpWidget(const SanmillApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      controller.activeSessionSnapshot = const platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.second,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'placing',
      );
      controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));
      await tester.pump();

      expect(
        find.byKey(const Key('sanmill_home_ongoing_game_group')),
        findsOneWidget,
      );
      expect(find.text('1 game in play'), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_home_ongoing_game')),
        findsOneWidget,
      );
      final Size carouselFrameSize = tester.getSize(
        find.byKey(const Key('sanmill_home_game_carousel_frame')),
      );
      expect(
        carouselFrameSize.width / carouselFrameSize.height,
        moreOrLessEquals(1.15, epsilon: 0.01),
      );
      expect(
        find.byKey(const Key('sanmill_home_saved_ongoing_games_group')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sanmill_home_recent_games_group')),
        findsNothing,
      );

      final Rect ongoingGameRect = tester.getRect(
        find.byKey(const Key('sanmill_home_ongoing_game')),
      );
      await tester.tapAt(ongoingGameRect.centerLeft + const Offset(46, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('game_page_scaffold')), findsOneWidget);

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home tab keeps bottom navigation after leaving an active game',
    (WidgetTester tester) async {
      final GameController controller = GameController();
      addTearDown(() {
        controller.activeSessionSnapshot = null;
        controller.gameRecorder.reset();
      });

      await tester.pumpWidget(const SanmillApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      controller.activeSessionSnapshot = const platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.first,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'ready',
      );
      await tester.pump();
      expect(
        find.byKey(const Key('sanmill_home_ongoing_game_group')),
        findsNothing,
      );

      controller.activeSessionSnapshot = const platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.first,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'placing',
      );
      await tester.pump();
      expect(
        find.byKey(const Key('sanmill_home_ongoing_game_group')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sanmill_home_play_fab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.byKey(const Key('sanmill_home_play_sheet_mill.play.humanVsAi')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));
      controller.activeSessionSnapshot = const platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.second,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'placing',
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('game_page_leave_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('game_page_leave_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      controller.activeSessionSnapshot = const platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.second,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'placing',
      );
      controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));
      await tester.pump();

      expect(
        find.byKey(const Key('sanmill_home_ongoing_game_group')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_home_ongoing_game')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sanmill_bottom_navigation_bar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sanmill_tab_learn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('sanmill_learn_list')), findsOneWidget);

      // Drain any settings-save debounce timer (see the smoke test above).
      await tester.pump(const Duration(milliseconds: 350));
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'Home tab keeps play modes in the FAB on wide screens',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(960, 540)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SanmillApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      expect(
        find.byKey(const Key('sanmill_home_play_modes_group')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sanmill_home_ongoing_game_group')),
        findsNothing,
      );
      expect(find.byKey(const Key('drawer_item_human_vs_ai')), findsNothing);
      expect(find.byKey(const Key('sanmill_home_play_fab')), findsOneWidget);

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
