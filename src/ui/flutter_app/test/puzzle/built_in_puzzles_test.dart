// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// built_in_puzzles_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/built_in_puzzles.dart';

/// Reads a puzzle asset directly from the project tree.
///
/// Flutter unit tests run with the working directory at the package root,
/// so the bundle asset key doubles as a file path -- the same trick used by
/// `opening_book_test_assets.dart` for the opening book.
Future<String> _loadBuiltInPuzzlesAssetFromDisk(String assetKey) {
  return File(assetKey).readAsString();
}

void main() {
  setUp(() {
    builtInPuzzlesAssetLoader = _loadBuiltInPuzzlesAssetFromDisk;
  });

  tearDown(() {
    builtInPuzzlesAssetLoader = _loadBuiltInPuzzlesAssetFromDisk;
  });

  group('getBuiltInPuzzles', () {
    test('loads the bundled Malom Perfect DB puzzle pack from disk', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isNotEmpty);
      for (final PuzzleInfo puzzle in puzzles) {
        expect(puzzle.id, isNotEmpty);
        expect(puzzle.solutions, isNotEmpty);
        expect(puzzle.isCustom, isFalse);
        for (final PuzzleSolution solution in puzzle.solutions) {
          expect(solution.moves, isNotEmpty);
        }
      }
    });

    test('every puzzle id in the bundled pack is unique', () async {
      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();
      final Set<String> ids = puzzles.map((PuzzleInfo p) => p.id).toSet();
      expect(ids.length, puzzles.length);
    });

    test('a missing asset degrades to an empty list, not a throw', () async {
      builtInPuzzlesAssetLoader = (String key) async =>
          throw const FileSystemException('missing');

      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isEmpty);
    });

    test('malformed JSON degrades to an empty list, not a throw', () async {
      builtInPuzzlesAssetLoader = (String key) async => 'not json';

      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isEmpty);
    });

    test('a JSON object without a puzzles array yields an empty list', () async {
      builtInPuzzlesAssetLoader = (String key) async => '{"formatVersion": "1.0"}';

      final List<PuzzleInfo> puzzles = await getBuiltInPuzzles();

      expect(puzzles, isEmpty);
    });
  });
}
