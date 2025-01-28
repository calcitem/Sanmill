import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/logger.dart';

void main() async {
  // Initialize the integration test environment
  final IntegrationTestWidgetsFlutterBinding _ =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Initialize testing environment variables
  EnvironmentConfig.test = false;
  EnvironmentConfig.devMode = true;
  EnvironmentConfig.catcher = false;

  // Logging
  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize the database
  await DB.init();

  // Initialize UI settings
  _initUI();

  // Initialize bitboards
  initBitboards();

  group('App Integration Tests', () {
    testWidgets('Navigate to General Settings', (WidgetTester tester) async {
      // Launch the app
      await tester.pumpWidget(
        const app.SanmillApp(),
      );
      await tester.pumpAndSettle();

      // Find the drawer button by Key
      final Finder drawerButton =
          find.byKey(const Key('custom_drawer_drawer_overlay_button'));
      expect(drawerButton, findsOneWidget,
          reason: 'Drawer button should be present');

      // Tap the drawer button
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      // Find CustomDrawer by Key
      final Finder customDrawer = find.byKey(const Key('custom_drawer_main'));
      expect(customDrawer, findsOneWidget,
          reason: 'CustomDrawer should be present');

      // Find the General Settings item by Key
      final Finder generalSettingsItem =
          find.byKey(const Key('drawer_item_general_settings'));
      expect(generalSettingsItem, findsOneWidget,
          reason: 'General Settings item should be present');

      // Tap the General Settings item
      await tester.tap(generalSettingsItem);
      await tester.pumpAndSettle();

      // Verify if the General Settings page is displayed by Key
      final Finder generalSettingsList =
          find.byKey(const Key('general_settings_page_settings_list'));
      expect(generalSettingsList, findsOneWidget,
          reason: 'General Settings page should be displayed');
    });
  });
}

// Copied from the _initUI() function in lib/main.dart
void _initUI() {
  // Add your UI initialization logic here
  // For example, you can set the preferred orientations
  // SystemChrome.setPreferredOrientations([
  //   DeviceOrientation.portraitUp,
  //   DeviceOrientation.portraitDown,
  // ]);
}
