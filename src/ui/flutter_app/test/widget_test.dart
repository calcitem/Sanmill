// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// widget_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import flutter services
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/app_shell/sanmill_app_shell.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/game_shell/shell_route_ids.dart';
import 'package:sanmill/games/built_in_game_modules.dart';
import 'package:sanmill/general_settings/widgets/developer_options_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/system_ui_service.dart';
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
        findsNothing,
      );
      expect(find.byKey(const Key('sanmill_navigation_rail')), findsOneWidget);
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
      expect((watchDestination.icon as Icon).icon, Icons.live_tv_rounded);
      expect(watchDestination.selectedIcon, isA<Icon>());
      expect(
        (watchDestination.selectedIcon! as Icon).icon,
        Icons.live_tv_rounded,
      );

      expect(
        find.byKey(const Key('sanmill_navigation_drawer_button')),
        findsNothing,
      );
      expect(find.byKey(const Key('sanmill_navigation_drawer')), findsNothing);

      final SanmillAppShellState shellState = tester
          .state<SanmillAppShellState>(find.byType(SanmillAppShell));
      expect(shellState.debugCurrentTab, SanmillShellTab.home);
      expect(
        shellState.debugCurrentRouteId,
        SanmillShellRouteIds.homeRoot.value,
      );
      expect(find.byKey(const Key('sanmill_home_list')), findsOneWidget);
      final Text homeAppBarTitle = tester.widget<Text>(
        find.byKey(const Key('sanmill_home_appbar_title')),
      );
      expect(homeAppBarTitle.data, 'Mill');
      expect(find.byKey(const Key('drawer_item_human_vs_ai')), findsOneWidget);
      expect(
        find.byKey(const Key('play_area_lichess_bottom_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('drawer_item_human_vs_ai')));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byKey(const Key('sanmill_tab_more')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sanmill_more_list'), skipOffstage: false),
        findsOneWidget,
      );
      final Text moreAppBarTitle = tester.widget<Text>(
        find.byKey(const Key('sanmill_more_appbar_title')),
      );
      expect(moreAppBarTitle.data, 'Mill');

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
}
