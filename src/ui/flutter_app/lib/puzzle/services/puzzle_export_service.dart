// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_export_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../game_page/services/mill.dart';
import '../../shared/database/database.dart';
import '../models/puzzle_models.dart';
import '../models/rule_variant.dart';

/// Service for exporting and importing puzzles
class PuzzleExportService {
  const PuzzleExportService._();

  /// Export format version
  static const String exportVersion = '1.0';

  /// File extension for puzzle exports
  static const String fileExtension = 'sanmill_puzzles';

  /// Export multiple puzzles to a JSON file
  /// Returns the file path if successful, null otherwise
  static Future<String?> exportPuzzles(
    List<PuzzleInfo> puzzles, {
    String? fileName,
    PuzzlePackMetadata? metadata,
  }) async {
    try {
      final Map<String, dynamic> exportData = <String, dynamic>{
        'formatVersion': exportVersion,
        'exportedBy': <String, String>{
          'appName': 'Sanmill',
          'platform': Platform.operatingSystem,
        },
        'exportDate': DateTime.now().toIso8601String(),
        'puzzleCount': puzzles.length,
        if (metadata != null) 'metadata': metadata.toJson(),
        'puzzles': puzzles.map((PuzzleInfo p) => p.toJson()).toList(),
      };

      final String jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(exportData);

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String defaultFileName =
          fileName ??
          'sanmill_puzzles_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final File file = File('${tempDir.path}/$defaultFileName');

      await file.writeAsString(jsonString);

      return file.path;
    } catch (e) {
      // Log error but don't expose details to production
      assert(false, 'Error exporting puzzles: $e');
      return null;
    }
  }

  /// Share exported puzzles using the platform share sheet
  static Future<bool> sharePuzzles(
    List<PuzzleInfo> puzzles, {
    String? fileName,
    PuzzlePackMetadata? metadata,
  }) async {
    try {
      final String? filePath = await exportPuzzles(
        puzzles,
        fileName: fileName,
        metadata: metadata,
      );

      if (filePath == null) {
        return false;
      }

      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          text: 'Check out these ${puzzles.length} Sanmill puzzles!',
          subject: 'Sanmill Puzzles (${puzzles.length})',
          files: <XFile>[XFile(filePath)],
        ),
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      // Log error but don't expose details to production
      assert(false, 'Error sharing puzzles: $e');
      return false;
    }
  }

  /// Import puzzles from a JSON file
  /// Returns a list of successfully imported puzzles
  static Future<ImportResult> importPuzzles() async {
    try {
      // Pick file using file picker
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[fileExtension, 'json'],
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(success: false, errorMessage: 'No file selected');
      }

      final PlatformFile pickedFile = result.files.first;
      final String? filePath = pickedFile.path;

      if (filePath == null) {
        return ImportResult(success: false, errorMessage: 'Invalid file path');
      }

      return await importPuzzlesFromFile(filePath);
    } catch (e) {
      return ImportResult(
        success: false,
        errorMessage: 'Error picking file: $e',
      );
    }
  }

  /// Import puzzles from a specific file path
  static Future<ImportResult> importPuzzlesFromFile(String filePath) async {
    try {
      final File file = File(filePath);

      if (!file.existsSync()) {
        return ImportResult(
          success: false,
          errorMessage: 'File does not exist',
        );
      }

      final String jsonString = file.readAsStringSync();
      final Map<String, dynamic> data =
          jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate format
      if (!data.containsKey('puzzles')) {
        return ImportResult(
          success: false,
          errorMessage: 'Invalid file format: missing puzzles field',
        );
      }

      // Check format version
      final String? formatVersion = data['formatVersion'] as String?;
      if (formatVersion != null && formatVersion != exportVersion) {
        return ImportResult(
          success: false,
          errorMessage:
              'Incompatible file format version: $formatVersion (expected $exportVersion)',
        );
      }

      // Parse metadata if present
      PuzzlePackMetadata? metadata;
      if (data.containsKey('metadata')) {
        try {
          metadata = PuzzlePackMetadata.fromJson(
            data['metadata'] as Map<String, dynamic>,
          );
        } catch (e) {
          // Metadata parsing failed, but continue with puzzles
          assert(false, 'Failed to parse metadata: $e');
        }
      }

      // Parse puzzles
      final List<dynamic> puzzlesJson = data['puzzles'] as List<dynamic>;
      final List<PuzzleInfo> importedPuzzles = <PuzzleInfo>[];
      final List<String> errors = <String>[];
      final List<String> warnings = <String>[];

      // Get current rule variant ID from settings
      final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
        DB().ruleSettings,
      );
      final String currentVariantId = currentVariant.id;

      for (int i = 0; i < puzzlesJson.length; i++) {
        try {
          final Map<String, dynamic> puzzleJson =
              puzzlesJson[i] as Map<String, dynamic>;
          final PuzzleInfo puzzle = PuzzleInfo.fromJson(puzzleJson);

          // Validate FEN format
          final Position tempPosition = Position();
          if (!tempPosition.validateFen(puzzle.initialPosition)) {
            errors.add(
              'Puzzle ${i + 1} ("${puzzle.title}") has invalid FEN format',
            );
            continue;
          }

          // Check if rule variant matches current settings
          if (puzzle.ruleVariantId != currentVariantId) {
            warnings.add(
              'Puzzle ${i + 1} ("${puzzle.title}") uses different rules: '
              '${puzzle.ruleVariantId} (current: $currentVariantId). '
              'This puzzle may not work correctly with your current settings.',
            );
          }

          importedPuzzles.add(puzzle);
        } catch (e) {
          errors.add('Failed to parse puzzle ${i + 1}: $e');
        }
      }

      // Build result message
      String? resultMessage;
      if (errors.isNotEmpty || warnings.isNotEmpty) {
        final StringBuffer buffer = StringBuffer();
        if (errors.isNotEmpty) {
          buffer.writeln('Errors:');
          for (final String error in errors) {
            buffer.writeln('  - $error');
          }
        }
        if (warnings.isNotEmpty) {
          if (errors.isNotEmpty) buffer.writeln();
          buffer.writeln('Warnings:');
          for (final String warning in warnings) {
            buffer.writeln('  - $warning');
          }
        }
        resultMessage = buffer.toString().trim();
      }

      return ImportResult(
        success: true,
        puzzles: importedPuzzles,
        metadata: metadata,
        errorMessage: resultMessage,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        errorMessage: 'Error reading file: $e',
      );
    }
  }

  /// Export a single puzzle to JSON string
  static String exportPuzzleToString(PuzzleInfo puzzle) {
    return const JsonEncoder.withIndent('  ').convert(puzzle.toJson());
  }

  /// Import a single puzzle from JSON string
  static PuzzleInfo? importPuzzleFromString(String jsonString) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(jsonString) as Map<String, dynamic>;
      final PuzzleInfo puzzle = PuzzleInfo.fromJson(json);

      // Validate FEN format
      final Position tempPosition = Position();
      if (!tempPosition.validateFen(puzzle.initialPosition)) {
        assert(false, 'Invalid FEN format in puzzle: ${puzzle.title}');
        return null;
      }

      return puzzle;
    } catch (e) {
      // Log error but don't expose details to production
      assert(false, 'Error importing puzzle from string: $e');
      return null;
    }
  }

  // ==================== CONTRIBUTION FEATURES ====================

  /// Export puzzle in standardized contribution format
  ///
  /// This format is designed for submitting puzzles to the Sanmill project
  /// for inclusion in the built-in puzzle collection.
  /// See PUZZLE_CONTRIBUTION_GUIDE.md for details.
  static String exportForContribution(PuzzleInfo puzzle) {
    final Map<String, dynamic> exportData = <String, dynamic>{
      'version': '1.0',
      'puzzle': _puzzleToContributionMap(puzzle),
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Export multiple puzzles in contribution format
  static String exportMultipleForContribution(List<PuzzleInfo> puzzles) {
    final Map<String, dynamic> exportData = <String, dynamic>{
      'version': '1.0',
      'puzzles': puzzles.map(_puzzleToContributionMap).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Convert puzzle to contribution map
  static Map<String, dynamic> _puzzleToContributionMap(PuzzleInfo puzzle) {
    final Map<String, dynamic> map = <String, dynamic>{
      'id': puzzle.id,
      'title': puzzle.title,
      'description': puzzle.description,
      'initialPosition': puzzle.initialPosition,
      'solutions': puzzle.solutions
          .map((PuzzleSolution s) => s.toJson())
          .toList(),
      'category': puzzle.category.name,
      'difficulty': puzzle.difficulty.name,
      'ruleVariantId': puzzle.ruleVariantId,
      'createdDate': puzzle.createdDate.toIso8601String(),
      'version': puzzle.version,
    };

    // Add optional fields if present
    if (puzzle.tags.isNotEmpty) {
      map['tags'] = puzzle.tags;
    }

    if (puzzle.author != null && puzzle.author!.isNotEmpty) {
      map['author'] = puzzle.author;
    }

    if (puzzle.hint != null && puzzle.hint!.isNotEmpty) {
      map['hint'] = puzzle.hint;
    }

    if (puzzle.rating != null) {
      map['rating'] = puzzle.rating;
    }

    return map;
  }

  /// Share puzzle for contribution
  ///
  /// Exports puzzle in contribution format and opens share dialog
  static Future<bool> shareForContribution(PuzzleInfo puzzle) async {
    try {
      // Validate before export
      final String? validationError = validateForContribution(puzzle);
      if (validationError != null) {
        return false;
      }

      // Generate filename
      final String filename = _generateContributionFilename(
        puzzle.author ?? 'contributor',
        puzzle.title,
      );

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/$filename';

      // Write JSON to file
      final File file = File(filePath);
      final String jsonContent = exportForContribution(puzzle);
      await file.writeAsString(jsonContent);

      // Share the file
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          text:
              'Puzzle contribution for Sanmill.\n\n'
              'See PUZZLE_CONTRIBUTION_GUIDE.md for submission instructions.',
          subject: 'Sanmill Puzzle Contribution: ${puzzle.title}',
          files: <XFile>[XFile(filePath)],
        ),
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      // Log error but don't expose details to production
      assert(false, 'Error sharing puzzle for contribution: $e');
      return false;
    }
  }

  /// Share multiple puzzles for contribution
  static Future<bool> shareMultipleForContribution(
    List<PuzzleInfo> puzzles,
  ) async {
    try {
      // Validate all puzzles
      for (final PuzzleInfo puzzle in puzzles) {
        final String? validationError = validateForContribution(puzzle);
        if (validationError != null) {
          return false;
        }
      }

      // Generate filename
      final String filename = 'sanmill_puzzles_${puzzles.length}.json';

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/$filename';

      // Write JSON to file
      final File file = File(filePath);
      final String jsonContent = exportMultipleForContribution(puzzles);
      await file.writeAsString(jsonContent);

      // Share the file
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          text:
              'Puzzle contributions for Sanmill.\n\n'
              'See PUZZLE_CONTRIBUTION_GUIDE.md for submission instructions.',
          subject: 'Sanmill Puzzle Contributions (${puzzles.length} puzzles)',
          files: <XFile>[XFile(filePath)],
        ),
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      // Log error but don't expose details to production
      assert(false, 'Error sharing puzzles for contribution: $e');
      return false;
    }
  }

  /// Validate puzzle for contribution
  ///
  /// Returns null if valid, error message if invalid
  static String? validateForContribution(PuzzleInfo puzzle) {
    // Check required fields
    if (puzzle.title.trim().isEmpty) {
      return 'Puzzle must have a title';
    }

    if (puzzle.description.trim().isEmpty) {
      return 'Puzzle must have a description';
    }

    if (puzzle.initialPosition.trim().isEmpty) {
      return 'Puzzle must have a valid position';
    }

    // Validate FEN format
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(puzzle.initialPosition)) {
      return 'Puzzle has invalid FEN format. Please check the position.';
    }

    if (puzzle.solutions.isEmpty) {
      return 'Puzzle must have a solution';
    }

    // Check title length
    if (puzzle.title.length < 5) {
      return 'Title too short (minimum 5 characters)';
    }

    if (puzzle.title.length > 100) {
      return 'Title too long (maximum 100 characters)';
    }

    // Check description length
    if (puzzle.description.length < 10) {
      return 'Description too short (minimum 10 characters)';
    }

    if (puzzle.description.length > 500) {
      return 'Description too long (maximum 500 characters)';
    }

    // Check for attribution
    if (puzzle.author == null || puzzle.author!.trim().isEmpty) {
      return 'Please add your name as author before contributing';
    }

    // All checks passed
    return null;
  }

  /// Generate standardized contribution filename
  ///
  /// Format: author_puzzlename.json
  /// Example: john_windmill_trap.json
  static String _generateContributionFilename(String author, String title) {
    // Clean author name
    final String cleanAuthor = author
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Clean puzzle title
    final String cleanTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Limit length
    final String shortAuthor = cleanAuthor.length > 15
        ? cleanAuthor.substring(0, 15)
        : cleanAuthor;
    final String shortTitle = cleanTitle.length > 30
        ? cleanTitle.substring(0, 30)
        : cleanTitle;

    return '${shortAuthor}_$shortTitle.json';
  }
}

/// Result of an import operation
class ImportResult {
  ImportResult({
    required this.success,
    this.puzzles = const <PuzzleInfo>[],
    this.metadata,
    this.errorMessage,
  });

  /// Whether the import was successful
  final bool success;

  /// Successfully imported puzzles
  final List<PuzzleInfo> puzzles;

  /// Imported puzzle pack metadata (if present)
  final PuzzlePackMetadata? metadata;

  /// Error message if import failed
  final String? errorMessage;
}
