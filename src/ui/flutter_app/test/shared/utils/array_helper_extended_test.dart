// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// array_helper_extended_test.dart
//
// Extended tests for the ListExtension.lastF getter.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/array_helpers/array_helper.dart';

void main() {
  group('ListExtension.lastF', () {
    test('should return last element of non-empty int list', () {
      expect(<int>[1, 2, 3, 4, 5].lastF, 5);
    });

    test('should return null for empty list', () {
      expect(<int>[].lastF, isNull);
    });

    test('should return single element for single-element list', () {
      expect(<int>[42].lastF, 42);
    });

    test('should work with String lists', () {
      expect(<String>['a', 'b', 'c'].lastF, 'c');
    });

    test('should work with nullable types', () {
      expect(<int?>[1, null, 3].lastF, 3);
    });

    test('should return null element if last is null', () {
      expect(<int?>[1, 2, null].lastF, isNull);
    });

    test('should work with large lists', () {
      final List<int> large = List<int>.generate(10000, (int i) => i);
      expect(large.lastF, 9999);
    });

    test('should work with empty list of custom objects', () {
      expect(<Map<String, int>>[].lastF, isNull);
    });

    test('should work with list of lists', () {
      expect(
        <List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ].lastF,
        <int>[3, 4],
      );
    });

    test('should not mutate the list', () {
      final List<int> list = <int>[1, 2, 3];
      final int? result = list.lastF;

      expect(result, 3);
      expect(list.length, 3);
    });
  });
}
