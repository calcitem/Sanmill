// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// built_in_puzzles_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/services/built_in_puzzles.dart';

void main() {
  group('getBuiltInPuzzles', () {
    test('should return an empty list', () {
      // All built-in puzzles have been removed; users create their own
      expect(getBuiltInPuzzles(), isEmpty);
    });

    test('should return a List<PuzzleInfo>', () {
      final dynamic result = getBuiltInPuzzles();
      expect(result, isList);
    });
  });
}
