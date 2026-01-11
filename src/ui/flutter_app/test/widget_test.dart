// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// widget_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import flutter services
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/home/home.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

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

    // Initialize the database and other services
    await DB.init();
    await initializeUI(true);
    initBitboards();
  });

  testWidgets('SanmillApp smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const SanmillApp());

    // Verify that MaterialApp and Scaffold are present
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('Verify app navigation and localization', (
    WidgetTester tester,
  ) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const SanmillApp());

    // Check that the supported locales include English
    expect(S.supportedLocales.contains(const Locale('en')), isTrue);

    // Verify that the Home widget is present
    expect(find.byType(Home), findsOneWidget);
  });
}
