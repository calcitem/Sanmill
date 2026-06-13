// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// detailed_error_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/services/puzzle_export_service.dart';

void main() {
  group('DetailedError', () {
    test('should store key and fallbackMessage', () {
      final DetailedError error = DetailedError(
        key: 'error_invalid_fen',
        fallbackMessage: 'The FEN string is invalid.',
      );

      expect(error.key, 'error_invalid_fen');
      expect(error.fallbackMessage, 'The FEN string is invalid.');
      expect(error.params, isNull);
    });

    test('should store optional params', () {
      final DetailedError error = DetailedError(
        key: 'error_line',
        fallbackMessage: 'Error at line 5',
        params: <String, dynamic>{'line': 5, 'file': 'test.json'},
      );

      expect(error.params, isNotNull);
      expect(error.params!['line'], 5);
      expect(error.params!['file'], 'test.json');
    });

    test('should work with empty params map', () {
      final DetailedError error = DetailedError(
        key: 'error_generic',
        fallbackMessage: 'An error occurred.',
        params: <String, dynamic>{},
      );

      expect(error.params, isEmpty);
    });
  });
}
