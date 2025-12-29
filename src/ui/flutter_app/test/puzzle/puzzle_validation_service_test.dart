// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_validation_service.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

    // Initialize bitboards
    initBitboards();

    // Provide a stable documents directory for Hive/path_provider callers
    appDocDir = Directory.systemTemp.createTempSync('sanmill_test_');
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
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  group('PuzzleValidationService.validatePuzzle', () {
    test('valid puzzle passes validation', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'valid_puzzle',
        title: 'Valid Puzzle',
        description: 'This is a valid puzzle with proper format',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
            ],
            isOptimal: true,
          ),
        ],
        author: 'Test Author',
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
    });

    test('detects empty puzzle ID', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: '',
        title: 'Test',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('ID is empty')));
    });

    test('detects empty title', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: '',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('title is empty')));
    });

    test('warns about very short title', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'AB',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.warnings, contains(contains('title is very short')));
    });

    test('detects empty description', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: '',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('description is empty')));
    });

    test('detects invalid FEN format', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition: 'invalid_fen_format',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('Invalid FEN format')));
    });

    test('detects puzzle with no solutions', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('no solutions')));
    });

    test('detects solution with empty moves', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[PuzzleSolution(moves: <PuzzleMove>[])],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('no moves')));
    });

    test('detects move with empty notation', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: '', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('empty notation')));
    });

    test('warns when no solution is marked optimal', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
            isOptimal: false,
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(
        report.warnings,
        contains(contains('No solution is marked as optimal')),
      );
    });

    test('detects incorrect side alternation', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(
                notation: 'd1',
                side: PieceColor.white,
              ), // Wrong: should be black
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validatePuzzle(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('incorrect side')));
    });
  });

  group('PuzzleValidationService.quickValidate', () {
    test('returns null for valid puzzle', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Test Puzzle',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final String? error = PuzzleValidationService.quickValidate(puzzle);
      expect(error, isNull);
    });

    test('returns error for empty title', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: '',
        description: 'Test description',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final String? error = PuzzleValidationService.quickValidate(puzzle);
      expect(error, isNotNull);
      expect(error, contains('title'));
    });
  });

  group('PuzzleValidationService.validateForContribution', () {
    test('enforces stricter requirements', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'AB', // Too short for contribution
        description: 'Short', // Too short for contribution
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validateForContribution(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors.length, greaterThan(1));
    });

    test('requires author for contribution', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test',
        title: 'Contribution Puzzle',
        description: 'A puzzle for contribution',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
        // No author specified
      );

      final PuzzleValidationReport report =
          PuzzleValidationService.validateForContribution(puzzle);

      expect(report.isValid, isFalse);
      expect(report.errors, contains(contains('author')));
    });
  });
}
