/*
 * localization_screenshot_test.dart
 *
 * This integration test captures screenshots for a SINGLE specified locale,
 * passed via the TEST_LOCALE environment variable (e.g., "en_US").
 *
 * It includes screenshots of:
 * 1. Home screen (with pieces placed)
 * 2. Open Drawer view
 * 3. General Settings screen
 * 4. Rule Settings screen (initial view)
 * 5. Rule Settings screen (scrolled view)
 * 6. Appearance Settings screen (initial view)
 * 7. Appearance Settings screen (scrolled to themes)
 * 8. Setup Position screen
 *
 * All screenshots are saved to /storage/emulated/0/Pictures/Sanmill/
 * with timestamps in the format YYYY-MM-DD_HH-MM-SS.
 */

import 'dart:io' show Platform, Directory, File;
import 'dart:typed_data' show Uint8List, ByteData;
import 'dart:ui' as ui;

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';
import 'package:sanmill/custom_drawer/custom_drawer.dart'; // Import CustomDrawer/ Import Item & Header
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/general_settings/widgets/general_settings_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/services/storage_permission_service.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

Catcher2? mockCatcher;
late Catcher2 catcher;

// List to track created screenshots within a single run
final List<String> createdScreenshots = <String>[];

// Define the target screenshot directory - centralized for consistency
const String targetScreenshotDir = '/storage/emulated/0/Pictures/Sanmill';

// Define the pages to capture screenshots for
enum ScreenshotPage { home, generalSettings, ruleSettings, appearanceSettings }

// Map the enum values to string identifiers for filenames
extension ScreenshotPageExtension on ScreenshotPage {
  String get fileNamePart {
    switch (this) {
      case ScreenshotPage.home:
        return 'home_screen';
      case ScreenshotPage.generalSettings:
        return 'general_settings';
      case ScreenshotPage.ruleSettings:
        return 'rule_settings';
      case ScreenshotPage.appearanceSettings:
        return 'appearance_settings';
    }
  }
}

// Helper function to parse locale string (e.g., "en_US") into Locale object
Locale? parseLocale(String? localeString) {
  if (localeString == null ||
      localeString.isEmpty ||
      !localeString.contains('_')) {
    // Check also for empty string which fromEnvironment might return if not defined
    return null; // Default or invalid
  }
  final List<String> parts = localeString.split('_');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return null; // Invalid format
  }
  return Locale(parts[0], parts[1]);
}

void main() {
  // Get the binding instance required for integration tests
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Read the target locale using String.fromEnvironment
  // Provide a default value (empty string) in case it's not defined,
  // which will then be caught by the null check later.
  const String targetLocaleString = String.fromEnvironment(
    'TEST_LOCALE',
  );
  final Locale? targetLocale = parseLocale(targetLocaleString);

  // Add extra debug logging here to see the raw value from fromEnvironment
  debugPrint(
      "Raw value from String.fromEnvironment('TEST_LOCALE'): '$targetLocaleString'");

  setUpAll(() async {
    debugPrint('=== GLOBAL SETUP STARTING ===');
    // Check if the parsed locale is valid
    if (targetLocale == null) {
      // Improve error message slightly
      throw Exception(
          "ERROR: TEST_LOCALE from --dart-define was not set, empty, or invalid. Raw value: '$targetLocaleString'. Expected format e.g., 'en_US'.");
    }
    debugPrint(
        'Target Locale for this run: $targetLocaleString ($targetLocale)');

    // Initialize necessary systems
    WidgetsFlutterBinding.ensureInitialized();

    EnvironmentConfig.catcher = false;

    // Initialize mock catcher if needed for other tests, but not essential for screenshots
    mockCatcher = Catcher2(rootWidget: Container());
    catcher = mockCatcher!;

    // Initialize bitboards (game logic)
    debugPrint('Initializing bitboards...');
    initBitboards();

    // Initialize database
    debugPrint('Initializing database...');
    await DB.init();
    debugPrint('Database initialized.');

    // Request storage permissions first
    if (Platform.isAndroid && !kIsWeb) {
      debugPrint('Requesting storage permissions...');
      final bool hasPermission =
          await StoragePermissionService.requestPermission();
      debugPrint('Storage permission granted: $hasPermission');

      if (!hasPermission) {
        debugPrint(
            'WARNING: Storage permissions not granted. Screenshots may fail.');
      }
    }

    // Print device storage paths for debugging
    if (!kIsWeb && Platform.isAndroid) {
      try {
        // Get external storage directory for debugging
        final Directory? externalDir = await getExternalStorageDirectory();
        debugPrint('External storage directory: ${externalDir?.path}');

        // Get application documents directory
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        debugPrint('App documents directory: ${appDocDir.path}');

        // Check standard picture directories
        const String sdcardPictures = '/sdcard/Pictures';
        const String storagePictures = '/storage/emulated/0/Pictures';

        debugPrint('Checking if standard picture directories exist:');
        debugPrint(
            '$sdcardPictures exists: ${Directory(sdcardPictures).existsSync()}');
        debugPrint(
            '$storagePictures exists: ${Directory(storagePictures).existsSync()}');
      } catch (e) {
        debugPrint('Error checking storage directories: $e');
      }
    }

    debugPrint('=== GLOBAL SETUP COMPLETE ===');
  });

  tearDownAll(() async {
    // Reduced teardown, only print created screenshots for this run
    debugPrint('=== GLOBAL TEARDOWN STARTING ===');
    await Hive.close();

    // Print the paths of all created screenshots for this specific locale run
    if (createdScreenshots.isNotEmpty) {
      debugPrint('Created screenshots for $targetLocaleString:');
      for (final String path in createdScreenshots) {
        debugPrint('- $path');
      }
    } else {
      debugPrint('No screenshots were created for $targetLocaleString.');
    }

    // Removed failedLocales check and final expect
    debugPrint('=== GLOBAL TEARDOWN COMPLETE FOR $targetLocaleString ===');
  });

  // Reset state before the single testWidgets block runs
  setUp(() async {
    debugPrint('=== TEST CASE SETUP - Resetting State ===');
    // Reset GameController
    GameController().reset();
    // Explicitly reset the ready flag
    GameController().isControllerReady = false;
    // Reset locale in DisplaySettings (will be set again in _processLocale)
    final DisplaySettings settings = DB().displaySettings;
    DB().displaySettings = settings.copyWith();
    debugPrint('Locale reset in settings.');
    // Clear screenshot list for this specific test run
    createdScreenshots.clear();
  });

  // Single testWidgets block that processes the targetLocale
  // Use targetLocaleString in the group title as targetLocale might be null initially
  group('Sanmill App Localization Screenshot Test for $targetLocaleString', () {
    testWidgets('Take screenshots for locale: $targetLocaleString',
        (WidgetTester tester) async {
      // Use the locale parsed earlier, re-checking it here
      if (targetLocale == null) {
        fail(
            "Target locale is null, cannot proceed. Check --dart-define value. Raw: '$targetLocaleString'");
      }

      debugPrint('--- Starting processing for locale: $targetLocale ---');

      // Run the processing logic for the single specified locale.
      await _processLocale(tester, binding, targetLocale);

      debugPrint(
          '--- Finished processing for locale: $targetLocale successfully ---');
    }); // End single testWidgets block
  }); // End group
}

// Helper function to process all steps for a single locale
Future<void> _processLocale(WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding, Locale locale) async {
  int screenshotCounter = 0;

  debugPrint('Processing locale: $locale...');

  // --- START: Reset and Setup Locale ---
  // Reset again just to be absolutely sure state is clean for this process
  GameController().reset(force: true);
  // Explicitly reset the ready flag
  GameController().isControllerReady = false;
  await tester.pumpAndSettle(const Duration(milliseconds: 500));

  // Set the locale from the argument
  final DisplaySettings currentSettings = DB().displaySettings;
  DB().displaySettings = currentSettings.copyWith(locale: locale);
  debugPrint('Locale set to $locale in settings.');

  // --- Step 1: Home Screen with pieces placed ---
  debugPrint('Pumping main app for Home Screen...');
  await tester.pumpWidget(const app.SanmillApp());
  await tester.pumpAndSettle(const Duration(seconds: 8)); // This can be long
  debugPrint('App settled with $locale locale on Home Screen.');

  await _placePiecesOnBoard(
      tester); // Using the original complex placement again

  screenshotCounter++;
  final String homeBaseName =
      '${locale.languageCode}_${locale.countryCode}_${ScreenshotPage.home.fileNamePart}';
  debugPrint('Taking screenshot #$screenshotCounter for $homeBaseName');
  await _takeAndSaveScreenshot(
      binding, tester, homeBaseName, screenshotCounter);
  await Future<void>.delayed(const Duration(seconds: 1));

  // --- Step 2: Drawer Open (via Tap) ---
  debugPrint('Capturing Drawer Open state via tap...');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  screenshotCounter =
      await _captureDrawerViaTap(tester, binding, locale, screenshotCounter);
  debugPrint('Finished capturing Drawer Open page via tap.');
  await Future<void>.delayed(const Duration(seconds: 1));

  // --- Step 3: Settings Pages (Standalone) ---
  debugPrint('Capturing Settings Pages (Standalone)...');
  screenshotCounter =
      await _captureSettingsPages(tester, binding, locale, screenshotCounter);
  debugPrint('Finished capturing Settings Pages for $locale.');
  await Future<void>.delayed(const Duration(seconds: 1));

  // --- Step 4: Setup Position Page (via Navigation) ---
  debugPrint('Capturing Setup Position Page via navigation...');
  GameController().reset(force: true); // Reset before navigation attempt
  // Explicitly reset the ready flag
  GameController().isControllerReady = false;
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
  await tester.pumpWidget(const app.SanmillApp());
  await tester.pumpAndSettle(const Duration(seconds: 5));
  screenshotCounter = await _captureSetupPositionViaNavigation(
      tester, binding, locale, screenshotCounter);
  debugPrint('Finished capturing Setup Position Page.');
}

// Helper function to check if a file exists and get its size
String _fileInfoSync(String path) {
  try {
    final File file = File(path);
    if (file.existsSync()) {
      final int size = file.lengthSync();
      return 'Exists: Yes, Size: $size bytes';
    }
    return 'Exists: No';
  } catch (e) {
    return 'Error checking file: $e';
  }
}

// Helper function to take a screenshot and ensure it's saved
Future<void> _takeAndSaveScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String baseName, // e.g., "en_US_home_screen"
  int counter, // The sequential number for this screenshot
) async {
  // Format counter with leading zero if needed (e.g., 01, 02, ..., 10)
  final String counterStr = counter.toString().padLeft(2, '0');
  final String nameWithCounter =
      '${baseName}_$counterStr'; // e.g., "en_US_home_screen_01"

  debugPrint('====== TAKING SCREENSHOT: $nameWithCounter.png ======');

  // Create timestamp in format: YYYY-MM-DD_HH-MM-SS
  final DateTime now = DateTime.now();
  final String timestamp =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';

  // Include counter and timestamp in filename
  // Revised format: locale_(number)_pageIdentifier_timestamp.png
  // We need to reconstruct baseName slightly to fit this.
  // Assuming baseName is locale_pageIdentifier
  final List<String> parts = baseName.split('_');
  final String localePart = '${parts[0]}_${parts[1]}'; // e.g., "en_US"
  final String pageIdentifier =
      parts.sublist(2).join('_'); // e.g., "home_screen"

  final String filename =
      '${localePart}_${counterStr}_${pageIdentifier}_$timestamp.png';
  // Example: en_US_01_home_screen_2023-10-27_10-30-00.png

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      // Ensure target directory exists - Use synchronous method
      final Directory directory = Directory(targetScreenshotDir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
        debugPrint('Created directory: $targetScreenshotDir');
      }

      final String targetPath = '$targetScreenshotDir/$filename';
      debugPrint('Target path: $targetPath'); // Log the final path

      debugPrint('Using manual screenshot approach (RenderRepaintBoundary)...');

      final RenderObject? renderObject = tester.binding.renderViews.first.child;
      if (renderObject is RenderRepaintBoundary) {
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        final ui.Image image = await renderObject.toImage(pixelRatio: 3.0);
        final ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          final Uint8List buffer = byteData.buffer.asUint8List();
          final File file = File(targetPath);
          file.writeAsBytesSync(buffer);
          createdScreenshots.add(targetPath); // Add to list for this run
          debugPrint('Screenshot saved to: $targetPath');
        } else {
          debugPrint('Failed to get byte data from image for $nameWithCounter');
        }
      } else {
        debugPrint(
            'Failed to find RenderRepaintBoundary for $nameWithCounter. Type: ${renderObject?.runtimeType}');
      }

      // Verify file exists - Use synchronous method
      final String fileStatus = _fileInfoSync(targetPath);
      debugPrint('File status for $targetPath: $fileStatus');
    } catch (e, stackTrace) {
      debugPrint('Screenshot error for $nameWithCounter: $e\n$stackTrace');
    }
  } else {
    debugPrint('Skipping screenshot on unsupported platform');
  }
  debugPrint(
      '====== SCREENSHOT PROCESS COMPLETED FOR: $nameWithCounter.png ======');
}

// Function to build and take screenshots of settings pages without game navigation
Future<int> _captureSettingsPages(
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
    Locale locale,
    int currentCounter) async {
  int counter = currentCounter; // Use local copy

  // Define page information including widgets and specific finders/scroll targets
  final List<Map<String, dynamic>> pagesInfo = <Map<String, dynamic>>[
    <String, dynamic>{
      'page': ScreenshotPage.generalSettings,
      'base_name':
          '${locale.languageCode}_${locale.countryCode}_${ScreenshotPage.generalSettings.fileNamePart}',
      'widget': MaterialApp(
        locale: locale,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.lightThemeData,
        darkTheme: AppTheme.darkThemeData,
        debugShowCheckedModeBanner: false,
        home: const GeneralSettingsPage(),
      ),
    },
    <String, dynamic>{
      'page': ScreenshotPage.ruleSettings,
      'base_name':
          '${locale.languageCode}_${locale.countryCode}_${ScreenshotPage.ruleSettings.fileNamePart}',
      'widget': MaterialApp(
        locale: locale,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.lightThemeData,
        darkTheme: AppTheme.darkThemeData,
        debugShowCheckedModeBanner: false,
        home: const RuleSettingsPage(),
      ),
      // --- START: Rule Settings Page 2 Info ---
      'scroll_target_page2': find.byType(Scrollable).first,
      'base_name_page2':
          '${locale.languageCode}_${locale.countryCode}_rule_settings_page2',
      // --- END: Rule Settings Page 2 Info ---
    },
    <String, dynamic>{
      'page': ScreenshotPage.appearanceSettings,
      'base_name':
          '${locale.languageCode}_${locale.countryCode}_${ScreenshotPage.appearanceSettings.fileNamePart}',
      'widget': MaterialApp(
        locale: locale,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.lightThemeData,
        darkTheme: AppTheme.darkThemeData,
        debugShowCheckedModeBanner: false,
        home: const AppearanceSettingsPage(),
      ),
      // --- START: Appearance Settings Theme Info ---
      'scroll_target_theme':
          find.byKey(const Key('color_settings_card_theme_settings_list_tile')),
      'base_name_theme':
          '${locale.languageCode}_${locale.countryCode}_appearance_settings_theme',
      // --- END: Appearance Settings Theme Info ---
    },
  ];

  // Iterate through each settings page and take screenshots
  for (final Map<String, dynamic> pageInfo in pagesInfo) {
    final ScreenshotPage page = pageInfo['page'] as ScreenshotPage;
    final Widget widget = pageInfo['widget'] as Widget;
    final String initialBaseName = pageInfo['base_name'] as String;

    debugPrint('Processing ${page.fileNamePart} page...');

    try {
      debugPrint('Building ${page.fileNamePart} page for initial screenshot');
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Take initial screenshot (Page 1 / Top View)
      counter++; // Increment before screenshot
      debugPrint('Taking screenshot #$counter for $initialBaseName');
      await _takeAndSaveScreenshot(binding, tester, initialBaseName, counter);
      await Future<void>.delayed(const Duration(seconds: 1));

      // --- Handle Rule Settings Page 2 (Scroll) ---
      if (pageInfo.containsKey('scroll_target_page2')) {
        debugPrint(
            'Scrolling down Rule Settings page for page 2 screenshot...');
        final Finder scrollableFinder =
            pageInfo['scroll_target_page2'] as Finder;
        expect(scrollableFinder, findsOneWidget,
            reason: 'Scrollable not found for Rule Settings');
        final Size size = tester.getSize(scrollableFinder);
        final Offset scrollVector = Offset(0, -size.height * 0.7);
        await tester.drag(scrollableFinder, scrollVector);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final String baseNamePage2 = pageInfo['base_name_page2'] as String;
        counter++; // Increment before screenshot
        debugPrint('Taking screenshot #$counter for $baseNamePage2');
        await _takeAndSaveScreenshot(binding, tester, baseNamePage2, counter);
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // --- Handle Appearance Settings Theme (Scroll) ---
      if (pageInfo.containsKey('scroll_target_theme')) {
        debugPrint(
            'Scrolling down Appearance Settings page to Theme section...');
        final Finder themeFinder = pageInfo['scroll_target_theme'] as Finder;
        final Finder scrollableFinder = find.byType(Scrollable).first;
        expect(scrollableFinder, findsOneWidget,
            reason: 'Scrollable not found for Appearance Settings');
        await tester.scrollUntilVisible(themeFinder, 100.0,
            scrollable: scrollableFinder, maxScrolls: 20);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final String baseNameTheme = pageInfo['base_name_theme'] as String;
        counter++; // Increment before screenshot
        debugPrint(
            'Taking screenshot #$counter for $baseNameTheme (Theme Section)');
        await _takeAndSaveScreenshot(binding, tester, baseNameTheme, counter);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (e, stackTrace) {
      debugPrint(
          'Error processing settings page ${page.fileNamePart} for $locale: $e');
      debugPrint('$stackTrace');
    }
  }
  debugPrint('Finished capturing all settings pages for $locale.');
  // Return the final counter value after processing all settings pages
  return counter;
}

// Function to place pieces on specific board positions for the home screen screenshot
// Reverted to original complex placement
Future<void> _placePiecesOnBoard(WidgetTester tester) async {
  // Wait for the board to be fully rendered
  await tester.pumpAndSettle(const Duration(seconds: 2));

  debugPrint(
      'Placing pieces on the board at specific positions (f4, d2, b4, d6, f2)');

  // Find the game board widget
  final Finder boardFinder = find.byType(GameBoard);
  if (boardFinder.evaluate().isEmpty) {
    debugPrint(
        'WARNING: GameBoard widget not found on home screen. Skipping piece placement.');
    return;
  }

  // Get the center and size of the board
  final Offset center = tester.getCenter(boardFinder);
  final Size size = tester.getSize(boardFinder);

  // Map logical positions to tap offsets (approximate based on visual layout)
  final List<MapEntry<String, Offset>> positionsInOrder =
      <MapEntry<String, ui.Offset>>[
    MapEntry<String, ui.Offset>(
        'd6', // Top Middle
        Offset(center.dx, center.dy - size.height * 0.35)),
    MapEntry<String, ui.Offset>(
        'f4', // Middle Right (Logical position, not exact coordinate name)
        Offset(center.dx + size.width * 0.35,
            center.dy)), // Adjust multiplier as needed
    MapEntry<String, ui.Offset>(
        'b4', // Middle Left
        Offset(center.dx - size.width * 0.35, center.dy)),
    MapEntry<String, ui.Offset>(
        'd2', // Bottom Middle
        Offset(center.dx, center.dy + size.height * 0.35)),
    MapEntry<String, ui.Offset>(
        'f2', // Inner Top Right (or adjust position for visual appeal)
        Offset(center.dx + size.width * 0.35, center.dy + size.height * 0.35)),
  ];

  // Tap each position with a delay between taps
  for (final MapEntry<String, Offset> entry in positionsInOrder) {
    final String positionName = entry.key;
    final Offset tapPoint = entry.value;

    debugPrint('Tapping position $positionName at $tapPoint');
    await tester.tapAt(tapPoint);
    // Wait significantly for piece animation and potential turn switch logic
    await tester.pumpAndSettle(const Duration(milliseconds: 1000));
  }

  // Allow time for any final animations or UI updates to complete
  await tester.pumpAndSettle(const Duration(seconds: 2));
  debugPrint(
      'Finished placing pieces on the board for home screen screenshot.');
}

// --- REVISED: Function to capture the drawer open state by tapping the icon ---
Future<int> _captureDrawerViaTap(
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
    Locale locale,
    int currentCounter) async {
  int counter = currentCounter; // Use local copy
  final String baseName =
      '${locale.languageCode}_${locale.countryCode}_drawer_open';
  debugPrint('Opening drawer via tap for screenshot: $baseName');

  try {
    // Find the drawer icon button
    final Finder drawerIconFinder = find.descendant(
      of: find.byType(CustomDrawerIcon),
      matching: find.byType(IconButton),
    );
    expect(drawerIconFinder, findsOneWidget,
        reason: 'Drawer icon button not found');
    debugPrint('Drawer icon button found.');

    // Tap the drawer icon
    await tester.tap(drawerIconFinder);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugPrint('Drawer opened.');

    // Increment counter *before* taking screenshot
    counter++;
    debugPrint('Taking screenshot #$counter for $baseName');
    await _takeAndSaveScreenshot(
        binding, tester, baseName, counter); // Pass updated counter

    await Future<void>.delayed(const Duration(seconds: 1));

    // Close the drawer
    debugPrint('Closing drawer...');
    final Size screenSize = tester.getSize(find.byType(MaterialApp));
    await tester
        .tapAt(Offset(screenSize.width * 0.85, screenSize.height * 0.5));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    debugPrint('Drawer closed.');
  } catch (e, stackTrace) {
    debugPrint('Error capturing drawer open page via tap for $locale: $e');
    debugPrint('$stackTrace');
  }
  // Return the final counter value for this function
  return counter;
}

// --- REVISED: Function to capture the Setup Position Page via navigation ---
Future<int> _captureSetupPositionViaNavigation(
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
    Locale locale,
    int currentCounter) async {
  int counter = currentCounter; // Use local copy
  final String baseName =
      '${locale.languageCode}_${locale.countryCode}_setup_position';
  debugPrint('Navigating to Setup Position page for screenshot: $baseName');

  try {
    // 1. Open the Drawer
    debugPrint('Opening drawer to navigate...');
    final Finder drawerIconFinder = find.descendant(
      of: find.byType(CustomDrawerIcon),
      matching: find.byType(IconButton),
    );
    expect(drawerIconFinder, findsOneWidget,
        reason: 'Drawer icon button not found for navigation');
    await tester.tap(drawerIconFinder);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugPrint('Drawer opened for navigation.');

    // 2. Find and Tap the "Setup Position" Drawer Item's InkWell
    final BuildContext context = tester.element(find.byType(MaterialApp));
    final String setupPositionText = S.of(context).setupPosition;
    debugPrint('Looking for drawer item text: "$setupPositionText"');
    final Finder textFinder = find.text(setupPositionText);
    expect(textFinder, findsOneWidget,
        reason: 'Text "$setupPositionText" not found in drawer');
    debugPrint('Text "$setupPositionText" found.');
    final Finder inkWellFinder = find.ancestor(
      of: textFinder,
      matching: find.byType(InkWell),
    );
    expect(inkWellFinder, findsOneWidget,
        reason: 'Tappable InkWell for Setup Position drawer item not found');
    debugPrint('Setup Position drawer item (InkWell) found.');
    await tester.tap(inkWellFinder);
    await tester.pumpAndSettle(const Duration(seconds: 8));
    debugPrint('Navigated to Setup Position page.');

    // 3. Verify the SetupPositionToolbar is present
    final Finder toolbarFinder = find.byType(SetupPositionToolbar);
    expect(toolbarFinder, findsOneWidget,
        reason: 'SetupPositionToolbar should be visible');
    debugPrint('SetupPositionToolbar found.');

    // 4. Take the screenshot
    counter++; // Increment before screenshot
    debugPrint('Taking screenshot #$counter for $baseName');
    await _takeAndSaveScreenshot(
        binding, tester, baseName, counter); // Pass updated counter

    await Future<void>.delayed(const Duration(seconds: 1));
  } catch (e, stackTrace) {
    debugPrint(
        'Error capturing Setup Position page via navigation for $locale: $e');
    debugPrint('$stackTrace');
  } finally {
    GameController().reset(force: true);
    // Explicitly reset the ready flag
    GameController().isControllerReady = false;
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    debugPrint('Game state reset after Setup Position navigation screenshot.');
  }
  // Return the final counter value for this function
  return counter;
}
