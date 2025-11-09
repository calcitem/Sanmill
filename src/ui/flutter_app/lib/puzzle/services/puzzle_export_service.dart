// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_export_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/puzzle_models.dart';

/// Service for exporting and importing puzzles
class PuzzleExportService {
  /// Export format version
  static const int exportVersion = 1;

  /// File extension for puzzle exports
  static const String fileExtension = 'sanmill_puzzles';

  /// Export multiple puzzles to a JSON file
  /// Returns the file path if successful, null otherwise
  static Future<String?> exportPuzzles(
    List<PuzzleInfo> puzzles, {
    String? fileName,
  }) async {
    try {
      final Map<String, dynamic> exportData = <String, dynamic>{
        'version': exportVersion,
        'exportDate': DateTime.now().toIso8601String(),
        'puzzleCount': puzzles.length,
        'puzzles': puzzles.map((PuzzleInfo p) => p.toJson()).toList(),
      };

      final String jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String defaultFileName = fileName ??
          'sanmill_puzzles_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final File file = File('${tempDir.path}/$defaultFileName');

      await file.writeAsString(jsonString);

      return file.path;
    } catch (e) {
      print('Error exporting puzzles: $e');
      return null;
    }
  }

  /// Share exported puzzles using the platform share sheet
  static Future<bool> sharePuzzles(
    List<PuzzleInfo> puzzles, {
    String? fileName,
  }) async {
    try {
      final String? filePath = await exportPuzzles(puzzles, fileName: fileName);

      if (filePath == null) {
        return false;
      }

      final XFile xFile = XFile(filePath);
      final ShareResult result = await Share.shareXFiles(
        <XFile>[xFile],
        subject: 'Sanmill Puzzles (${puzzles.length})',
        text: 'Check out these ${puzzles.length} Sanmill puzzles!',
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      print('Error sharing puzzles: $e');
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
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          errorMessage: 'No file selected',
        );
      }

      final PlatformFile pickedFile = result.files.first;
      final String? filePath = pickedFile.path;

      if (filePath == null) {
        return ImportResult(
          success: false,
          errorMessage: 'Invalid file path',
        );
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

      if (!await file.exists()) {
        return ImportResult(
          success: false,
          errorMessage: 'File does not exist',
        );
      }

      final String jsonString = await file.readAsString();
      final Map<String, dynamic> data =
          jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate format
      if (!data.containsKey('version') || !data.containsKey('puzzles')) {
        return ImportResult(
          success: false,
          errorMessage: 'Invalid file format',
        );
      }

      final int fileVersion = data['version'] as int;
      if (fileVersion > exportVersion) {
        return ImportResult(
          success: false,
          errorMessage: 'File version ($fileVersion) is newer than supported version ($exportVersion)',
        );
      }

      // Parse puzzles
      final List<dynamic> puzzlesJson = data['puzzles'] as List<dynamic>;
      final List<PuzzleInfo> importedPuzzles = <PuzzleInfo>[];
      final List<String> errors = <String>[];

      for (int i = 0; i < puzzlesJson.length; i++) {
        try {
          final Map<String, dynamic> puzzleJson =
              puzzlesJson[i] as Map<String, dynamic>;
          final PuzzleInfo puzzle = PuzzleInfo.fromJson(puzzleJson);
          importedPuzzles.add(puzzle);
        } catch (e) {
          errors.add('Failed to parse puzzle ${i + 1}: $e');
        }
      }

      return ImportResult(
        success: true,
        puzzles: importedPuzzles,
        errorMessage: errors.isEmpty ? null : errors.join('\n'),
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
      return PuzzleInfo.fromJson(json);
    } catch (e) {
      print('Error importing puzzle from string: $e');
      return null;
    }
  }
}

/// Result of an import operation
class ImportResult {
  ImportResult({
    required this.success,
    this.puzzles = const <PuzzleInfo>[],
    this.errorMessage,
  });

  /// Whether the import was successful
  final bool success;

  /// Successfully imported puzzles
  final List<PuzzleInfo> puzzles;

  /// Error message if import failed
  final String? errorMessage;
}
