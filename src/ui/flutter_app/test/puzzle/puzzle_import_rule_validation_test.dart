// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_export_service.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

/// Integration tests for puzzle import/export with rule variant validation
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;
    initBitboards();

    // Mock engine channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'uciok';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    // Mock path provider
    appDocDir = Directory.systemTemp.createTempSync('sanmill_import_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return appDocDir.path;
            default:
              return null;
          }
        });

    await DB.init();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  group('Puzzle Import - Rule Variant Validation', () {
    test('warns when importing puzzle with different rule variant', () async {
      // Current settings should be standard 9mm (default)
      // Create a puzzle with 12mm rule variant
      final Map<String, dynamic> importData = <String, dynamic>{
        'formatVersion': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'puzzleCount': 1,
        'puzzles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'twelve_mm_puzzle',
            'title': 'Twelve Men Morris Puzzle',
            'description': 'A puzzle designed for 12-piece variant',
            'category': 'formMill',
            'difficulty': 'medium',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'twelve_mens_morris', // Different from current
          },
        ],
      };

      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/test_rule_mismatch.json');
      await tempFile.writeAsString(jsonEncode(importData));

      try {
        final ImportResult result =
            await PuzzleExportService.importPuzzlesFromFile(tempFile.path);

        expect(result.success, isTrue);
        expect(result.puzzles, isNotEmpty);

        // Should have a warning about rule mismatch
        expect(result.errorMessage, isNotNull);
        expect(result.errorMessage, contains('twelve_mens_morris'));
        expect(result.errorMessage, contains('current'));
        expect(result.errorMessage, contains('Warnings:'));
      } finally {
        await tempFile.delete();
      }
    });

    test('imports puzzle with matching rule variant without warning', () async {
      // Create a puzzle with standard 9mm (matches current settings)
      final Map<String, dynamic> importData = <String, dynamic>{
        'formatVersion': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'puzzleCount': 1,
        'puzzles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'standard_puzzle',
            'title': 'Standard Nine Mens Morris Puzzle',
            'description': 'A puzzle for standard 9mm',
            'category': 'formMill',
            'difficulty': 'easy',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'standard_9mm', // Matches current
          },
        ],
      };

      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/test_rule_match.json');
      await tempFile.writeAsString(jsonEncode(importData));

      try {
        final ImportResult result =
            await PuzzleExportService.importPuzzlesFromFile(tempFile.path);

        expect(result.success, isTrue);
        expect(result.puzzles, isNotEmpty);

        // Should NOT have warnings about rule mismatch
        if (result.errorMessage != null) {
          expect(result.errorMessage, isNot(contains('Warnings:')));
        }
      } finally {
        await tempFile.delete();
      }
    });

    test('imports multiple puzzles with mixed rule variants', () async {
      final Map<String, dynamic> importData = <String, dynamic>{
        'formatVersion': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'puzzleCount': 3,
        'puzzles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'puzzle_1',
            'title': 'Standard Puzzle',
            'description': 'Standard 9mm puzzle',
            'category': 'formMill',
            'difficulty': 'easy',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'standard_9mm', // Matches
          },
          <String, dynamic>{
            'id': 'puzzle_2',
            'title': 'Twelve Puzzle',
            'description': 'Twelve mens morris puzzle',
            'category': 'formMill',
            'difficulty': 'medium',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'twelve_mens_morris', // Different
          },
          <String, dynamic>{
            'id': 'puzzle_3',
            'title': 'Russian Mill Puzzle',
            'description': 'Russian mill variant puzzle',
            'category': 'formMill',
            'difficulty': 'hard',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'russian_mill', // Different
          },
        ],
      };

      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/test_mixed_rules.json');
      await tempFile.writeAsString(jsonEncode(importData));

      try {
        final ImportResult result =
            await PuzzleExportService.importPuzzlesFromFile(tempFile.path);

        expect(result.success, isTrue);
        expect(result.puzzles!.length, equals(3));

        // Should have warnings for the 2 mismatched puzzles
        expect(result.errorMessage, isNotNull);
        expect(result.errorMessage, contains('Warnings:'));
        expect(result.errorMessage, contains('twelve_mens_morris'));
        expect(result.errorMessage, contains('russian_mill'));
        // Should not warn about the standard puzzle
        expect(result.errorMessage, isNot(contains('Puzzle 1')));
      } finally {
        await tempFile.delete();
      }
    });

    test('provides helpful message about rule variant mismatch', () async {
      final Map<String, dynamic> importData = <String, dynamic>{
        'formatVersion': '1.0',
        'puzzleCount': 1,
        'puzzles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'custom_variant',
            'title': 'Custom Variant Puzzle',
            'description': 'A puzzle with custom rules',
            'category': 'formMill',
            'difficulty': 'expert',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                ],
                'isOptimal': true,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': DateTime.now().toIso8601String(),
            'version': 1,
            'ruleVariantId': 'custom_15p_diag',
          },
        ],
      };

      final Directory tempDir = Directory.systemTemp;
      final File tempFile = File('${tempDir.path}/test_custom_rule.json');
      await tempFile.writeAsString(jsonEncode(importData));

      try {
        final ImportResult result =
            await PuzzleExportService.importPuzzlesFromFile(tempFile.path);

        expect(result.success, isTrue);
        expect(result.errorMessage, isNotNull);

        // Message should be helpful
        expect(result.errorMessage, contains('custom_15p_diag'));
        expect(result.errorMessage, contains('may not work correctly'));
      } finally {
        await tempFile.delete();
      }
    });
  });
}
