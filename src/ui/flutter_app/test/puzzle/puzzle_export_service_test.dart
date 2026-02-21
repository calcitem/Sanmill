// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

    // Provide a stable documents directory for Hive/path_provider callers
    appDocDir = Directory.systemTemp.createTempSync('sanmill_export_test_');
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
    initBitboards();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (appDocDir.existsSync()) {
      appDocDir.deleteSync(recursive: true);
    }
  });

  group('PuzzleExportService', () {
    late PuzzleInfo testPuzzle;

    setUp(() {
      EnvironmentConfig.catcher = false;

      testPuzzle = PuzzleInfo(
        id: 'test_export_001',
        title: 'Test Export',
        description: 'Testing export functionality',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
        author: 'Test Author',
        tags: const <String>['test', 'export'],
        rating: 1500,
        hint: 'A hint',
      );
    });

    group('QR Code Export/Import', () {
      test('exportPuzzlesToQrString returns non-null for a small puzzle', () {
        final String? qrString = PuzzleExportService.exportPuzzlesToQrString(
          <PuzzleInfo>[testPuzzle],
        );
        expect(qrString, isNotNull);
        expect(qrString!.isNotEmpty, isTrue);
      });

      test('exportPuzzlesToQrString round-trips via raw JSON', () {
        final String? qrString = PuzzleExportService.exportPuzzlesToQrString(
          <PuzzleInfo>[testPuzzle],
        );
        expect(qrString, isNotNull);

        // Ensure at least one representation is raw JSON (no prefix).
        final bool isCompressed = qrString!.startsWith('sm_pz_gz:');
        if (!isCompressed) {
          // Verify it is valid JSON.
          expect(() => jsonDecode(qrString), returnsNormally);
        }

        final ImportResult result =
            PuzzleExportService.importPuzzlesFromJsonString(qrString);
        expect(result.success, isTrue);
        expect(result.puzzles.length, equals(1));
        expect(result.puzzles.first.id, equals(testPuzzle.id));
      });

      test('importPuzzlesFromJsonString handles compressed payload', () {
        // Build a valid compressed payload manually using the same encoding
        // that exportPuzzlesToQrString uses internally.
        final Map<String, dynamic> envelope = <String, dynamic>{
          'formatVersion': '1.0',
          'puzzleCount': 1,
          'puzzles': <dynamic>[testPuzzle.toJson()],
        };
        final Uint8List rawBytes = utf8.encode(jsonEncode(envelope));
        final String compressed =
            'sm_pz_gz:${base64.encode(gzip.encode(rawBytes))}';

        final ImportResult result =
            PuzzleExportService.importPuzzlesFromJsonString(compressed);
        expect(result.success, isTrue);
        expect(result.puzzles.length, equals(1));
        expect(result.puzzles.first.id, equals(testPuzzle.id));
      });

      test('importPuzzlesFromJsonString handles invalid compressed data', () {
        const String badPayload = 'sm_pz_gz:!!not_valid_base64!!';
        final ImportResult result =
            PuzzleExportService.importPuzzlesFromJsonString(badPayload);
        expect(result.success, isFalse);
      });

      test(
        'importPuzzlesFromJsonString auto-wraps bare single-puzzle object',
        () {
          final String singleJson = jsonEncode(testPuzzle.toJson());
          final ImportResult result =
              PuzzleExportService.importPuzzlesFromJsonString(singleJson);
          expect(result.success, isTrue);
          expect(result.puzzles.length, equals(1));
          expect(result.puzzles.first.id, equals(testPuzzle.id));
        },
      );

      test('exportPuzzlesToQrString returns null when data is too large', () {
        // Build a list of puzzles large enough to exceed 2331 bytes even when
        // compressed by generating many distinct puzzles.
        final List<PuzzleInfo> largeBatch = List<PuzzleInfo>.generate(
          30,
          (int i) => testPuzzle.copyWith(
            id: 'test_qr_overflow_$i',
            title: 'Overflow Test Puzzle $i with a long descriptive title',
            description:
                'This is a detailed description for overflow test puzzle $i. '
                'It contains enough text to push the total payload over the '
                'QR code limit even after gzip compression is applied.',
          ),
        );

        final String? qrString = PuzzleExportService.exportPuzzlesToQrString(
          largeBatch,
        );
        expect(qrString, isNull);
      });
    });

    group('String Export/Import', () {
      test('exportPuzzleToString generates valid JSON', () {
        final String jsonString = PuzzleExportService.exportPuzzleToString(
          testPuzzle,
        );
        final Map<String, dynamic> json =
            jsonDecode(jsonString) as Map<String, dynamic>;

        expect(json['id'], equals(testPuzzle.id));
        expect(json['title'], equals(testPuzzle.title));
        expect(json['description'], equals(testPuzzle.description));
        expect(json['author'], equals(testPuzzle.author));
      });

      test('importPuzzleFromString reconstructs puzzle correctly', () {
        final String jsonString = PuzzleExportService.exportPuzzleToString(
          testPuzzle,
        );
        final PuzzleInfo? imported = PuzzleExportService.importPuzzleFromString(
          jsonString,
        );

        expect(imported, isNotNull);
        expect(imported!.id, equals(testPuzzle.id));
        expect(imported.title, equals(testPuzzle.title));
        expect(imported.category, equals(testPuzzle.category));
        expect(imported.difficulty, equals(testPuzzle.difficulty));
        expect(imported.solutions.length, equals(testPuzzle.solutions.length));
      });

      test('importPuzzleFromString handles invalid JSON', () {
        final PuzzleInfo? imported = PuzzleExportService.importPuzzleFromString(
          'invalid json',
        );
        expect(imported, isNull);
      });

      test('importPuzzleFromString validates FEN', () {
        final Map<String, dynamic> json = testPuzzle.toJson();
        json['initialPosition'] = 'invalid_fen';
        final String jsonString = jsonEncode(json);

        final PuzzleInfo? imported = PuzzleExportService.importPuzzleFromString(
          jsonString,
        );

        // Should return null due to FEN validation failure (assert in debug mode)
        // Note: assertions might be enabled in tests
        expect(imported, isNull);
      });
    });

    group('Contribution Validation', () {
      test('valid puzzle passes validation', () {
        final String? error = PuzzleExportService.validateForContribution(
          testPuzzle,
        );
        expect(error, isNull);
      });

      test('validates title length', () {
        final PuzzleInfo shortTitle = testPuzzle.copyWith(title: 'Abc');
        expect(
          PuzzleExportService.validateForContribution(shortTitle),
          equals('puzzleValidationTitleTooShort'),
        );

        final PuzzleInfo longTitle = testPuzzle.copyWith(title: 'A' * 101);
        expect(
          PuzzleExportService.validateForContribution(longTitle),
          equals('puzzleValidationTitleTooLong'),
        );
      });

      test('validates description length', () {
        final PuzzleInfo shortDesc = testPuzzle.copyWith(description: 'Short');
        expect(
          PuzzleExportService.validateForContribution(shortDesc),
          equals('puzzleValidationDescriptionTooShort'),
        );

        final PuzzleInfo longDesc = testPuzzle.copyWith(description: 'A' * 501);
        expect(
          PuzzleExportService.validateForContribution(longDesc),
          equals('puzzleValidationDescriptionTooLong'),
        );
      });

      test('validates author presence', () {
        final PuzzleInfo noAuthor = testPuzzle.copyWith(author: '');
        expect(
          PuzzleExportService.validateForContribution(noAuthor),
          equals('puzzleValidationAuthorRequired'),
        );
      });

      test('validates solutions presence', () {
        final PuzzleInfo noSolutions = testPuzzle.copyWith(
          solutions: <PuzzleSolution>[],
        );
        expect(
          PuzzleExportService.validateForContribution(noSolutions),
          equals('puzzleValidationSolutionRequired'),
        );
      });
    });

    group('Contribution Export', () {
      test('exportForContribution generates correct structure', () {
        final String jsonString = PuzzleExportService.exportForContribution(
          testPuzzle,
        );
        final Map<String, dynamic> json =
            jsonDecode(jsonString) as Map<String, dynamic>;

        expect(json['version'], equals('1.0'));
        expect(json['puzzle'], isA<Map<String, dynamic>>());

        final Map<String, dynamic> puzzleData =
            json['puzzle'] as Map<String, dynamic>;
        expect(puzzleData['id'], equals(testPuzzle.id));
        expect(puzzleData['author'], equals(testPuzzle.author));
        expect(puzzleData['tags'], equals(testPuzzle.tags));
        expect(puzzleData['hint'], equals(testPuzzle.hint));
        expect(puzzleData['rating'], equals(testPuzzle.rating));
      });

      test('exportMultipleForContribution generates correct structure', () {
        final List<PuzzleInfo> puzzles = <PuzzleInfo>[
          testPuzzle,
          testPuzzle.copyWith(id: 'test_export_002', title: 'Test Export 2'),
        ];

        final String jsonString =
            PuzzleExportService.exportMultipleForContribution(puzzles);
        final Map<String, dynamic> json =
            jsonDecode(jsonString) as Map<String, dynamic>;

        expect(json['version'], equals('1.0'));
        expect(json['puzzles'], isA<List<dynamic>>());

        final List<dynamic> puzzlesList = json['puzzles'] as List<dynamic>;
        expect(puzzlesList.length, equals(2));
        expect(
          (puzzlesList[0] as Map<String, dynamic>)['id'],
          equals('test_export_001'),
        );
        expect(
          (puzzlesList[1] as Map<String, dynamic>)['id'],
          equals('test_export_002'),
        );
      });
    });
  });
}
