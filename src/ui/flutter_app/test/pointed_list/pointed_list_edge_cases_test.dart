// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// pointed_list_edge_cases_test.dart
//
// Additional edge-case tests for PointedList and PointedListIterator.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/list_helpers/pointed_list.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PointedList additional tests
  // ---------------------------------------------------------------------------
  group('PointedList isClean', () {
    test('empty list should be clean', () {
      final PointedList<int> list = PointedList<int>();
      expect(list.isClean, isTrue);
    });

    test('list with pointer at end should be clean', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      expect(list.isClean, isTrue);
    });

    test('list with pointer not at end should not be clean', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveTo(0);
      expect(list.isClean, isFalse);
    });

    test('list after prune should be clean', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveTo(1);
      list.prune();
      expect(list.isClean, isTrue);
    });
  });

  group('PointedList hasPrevious', () {
    test('empty list should not have previous', () {
      final PointedList<int> list = PointedList<int>();
      expect(list.hasPrevious, isFalse);
    });

    test('list at first element should have previous (movePrevious goes to head)', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveToFirst();
      expect(list.hasPrevious, isTrue);
    });

    test('list at head (null index) should not have previous', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveToHead();
      expect(list.hasPrevious, isFalse);
    });
  });

  group('PointedList current', () {
    test('empty list current should be null', () {
      final PointedList<int> list = PointedList<int>();
      expect(list.current, isNull);
    });

    test('list with elements should return current element', () {
      final PointedList<int> list = PointedList<int>.from(<int>[10, 20, 30]);
      expect(list.current, 30); // Initially at last
    });

    test('after moveTo, current should reflect new position', () {
      final PointedList<int> list = PointedList<int>.from(<int>[10, 20, 30]);
      list.globalIterator.moveTo(0);
      expect(list.current, 10);

      list.globalIterator.moveTo(1);
      expect(list.current, 20);
    });
  });

  group('PointedList addAndDeduplicate', () {
    test('should not add duplicate of current', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      // current is 3 (at last position)
      list.addAndDeduplicate(3);
      // Should not add since current == value
      expect(list.length, 3);
    });

    test('should add value different from current', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.addAndDeduplicate(4);
      expect(list.length, 4);
      expect(list.current, 4);
    });
  });

  group('PointedList forEachVisible', () {
    test('should iterate nothing when index is null', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveToHead();
      final List<int> visited = <int>[];

      list.forEachVisible((int e) => visited.add(e));

      expect(visited, isEmpty);
    });

    test('should iterate all elements when at end', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      final List<int> visited = <int>[];

      list.forEachVisible((int e) => visited.add(e));

      expect(visited, <int>[1, 2, 3]);
    });

    test('should iterate only first element when at index 0', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      list.globalIterator.moveToFirst();
      final List<int> visited = <int>[];

      list.forEachVisible((int e) => visited.add(e));

      expect(visited, <int>[1]);
    });
  });

  group('PointedList bidirectionalIterator', () {
    test('should return a new iterator', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      final PointedListIterator<int> iter = list.bidirectionalIterator;

      expect(iter, isNotNull);
      expect(iter.current, 1); // Starts at first element
    });

    test('new iterator should be independent from global iterator', () {
      final PointedList<int> list = PointedList<int>.from(<int>[1, 2, 3]);
      final PointedListIterator<int> iter = list.bidirectionalIterator;

      // Move the new iterator independently
      iter.moveToLast();
      expect(iter.current, 3);

      // Global iterator should still be at its own position
      expect(list.globalIterator.current, 3); // Was at end
    });
  });

  // ---------------------------------------------------------------------------
  // PointedListIterator additional tests
  // ---------------------------------------------------------------------------
  group('PointedListIterator moveToHead', () {
    test('should set current to null', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);

      iter.moveToHead();

      expect(iter.current, isNull);
      expect(iter.index, isNull);
    });

    test('moveNext from head should go to first element', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);

      iter.moveToHead();
      final bool result = iter.moveNext();

      expect(result, isTrue);
      expect(iter.current, 1);
      expect(iter.index, 0);
    });
  });

  group('PointedListIterator prev', () {
    test('should return null at head', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);
      iter.moveToHead();

      expect(iter.prev, isNull);
    });

    test('should return null at first element (index 0)', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);
      iter.moveToFirst();

      expect(iter.prev, isNull);
    });

    test('should return previous element at index > 0', () {
      final List<int> source = <int>[10, 20, 30];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);
      iter.moveToLast();

      expect(iter.prev, 20);
    });
  });

  group('PointedListIterator equality', () {
    test('same list and same index should be equal', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter1 = PointedListIterator<int>(source);
      final PointedListIterator<int> iter2 = PointedListIterator<int>(source);

      expect(iter1, equals(iter2));
    });

    test('same list but different index should not be equal', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter1 = PointedListIterator<int>(source);
      final PointedListIterator<int> iter2 = PointedListIterator<int>(source);
      iter2.moveToLast();

      expect(iter1, isNot(equals(iter2)));
    });
  });

  group('PointedListIterator lastIndex', () {
    test('should return correct last index', () {
      final List<int> source = <int>[1, 2, 3, 4, 5];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);

      expect(iter.lastIndex, 4);
    });
  });

  group('PointedListIterator hasNext', () {
    test('should return true when not at last', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);
      iter.moveToFirst();

      expect(iter.hasNext, isTrue);
    });

    test('should return false when at last', () {
      final List<int> source = <int>[1, 2, 3];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);
      iter.moveToLast();

      expect(iter.hasNext, isFalse);
    });

    test('should return false for empty list', () {
      final List<int> source = <int>[];
      final PointedListIterator<int> iter = PointedListIterator<int>(source);

      expect(iter.hasNext, isFalse);
    });
  });
}
