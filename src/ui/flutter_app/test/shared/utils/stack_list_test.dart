// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// stack_list_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/list_helpers/stack_list.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Basic operations
  // ---------------------------------------------------------------------------
  group('StackList basic operations', () {
    test('newly created stack should be empty', () {
      final StackList<int> stack = StackList<int>();

      expect(stack.isEmpty, isTrue);
      expect(stack.isNotEmpty, isFalse);
      expect(stack.size(), 0);
      expect(stack.length, 0);
    });

    test('push should add elements to the top', () {
      final StackList<int> stack = StackList<int>();

      stack.push(1);
      expect(stack.isEmpty, isFalse);
      expect(stack.isNotEmpty, isTrue);
      expect(stack.size(), 1);
      expect(stack.top(), 1);

      stack.push(2);
      expect(stack.size(), 2);
      expect(stack.top(), 2);
    });

    test('pop should remove and return the top element', () {
      final StackList<int> stack = StackList<int>();
      stack.push(10);
      stack.push(20);
      stack.push(30);

      expect(stack.pop(), 30);
      expect(stack.size(), 2);
      expect(stack.pop(), 20);
      expect(stack.size(), 1);
      expect(stack.pop(), 10);
      expect(stack.isEmpty, isTrue);
    });

    test('top should return the top element without removing it', () {
      final StackList<int> stack = StackList<int>();
      stack.push(42);

      expect(stack.top(), 42);
      expect(stack.size(), 1); // Size unchanged
    });

    test('pop on empty stack should throw', () {
      final StackList<int> stack = StackList<int>();

      expect(() => stack.pop(), throwsException);
    });

    test('top on empty stack should throw', () {
      final StackList<int> stack = StackList<int>();

      expect(() => stack.top(), throwsException);
    });
  });

  // ---------------------------------------------------------------------------
  // contains, clear, toList
  // ---------------------------------------------------------------------------
  group('StackList contains / clear / toList', () {
    test('contains should return true for existing elements', () {
      final StackList<String> stack = StackList<String>();
      stack.push('a');
      stack.push('b');
      stack.push('c');

      expect(stack.contains('a'), isTrue);
      expect(stack.contains('b'), isTrue);
      expect(stack.contains('c'), isTrue);
      expect(stack.contains('d'), isFalse);
    });

    test('clear should remove all elements', () {
      final StackList<int> stack = StackList<int>();
      stack.push(1);
      stack.push(2);
      stack.push(3);

      stack.clear();

      expect(stack.isEmpty, isTrue);
      expect(stack.size(), 0);
    });

    test('clear on empty stack should be a no-op', () {
      final StackList<int> stack = StackList<int>();

      stack.clear();

      expect(stack.isEmpty, isTrue);
    });

    test('toList should return elements in insertion order', () {
      final StackList<int> stack = StackList<int>();
      stack.push(1);
      stack.push(2);
      stack.push(3);

      expect(stack.toList(), <int>[1, 2, 3]);
    });

    test('toList on empty stack should return empty list', () {
      final StackList<int> stack = StackList<int>();

      expect(stack.toList(), <int>[]);
    });
  });

  // ---------------------------------------------------------------------------
  // Sized stack
  // ---------------------------------------------------------------------------
  group('StackList.sized', () {
    test('should allow pushes within the size limit', () {
      final StackList<int> stack = StackList<int>.sized(3);

      stack.push(1);
      stack.push(2);
      stack.push(3);

      expect(stack.size(), 3);
      expect(stack.top(), 3);
    });

    test('should throw when pushing beyond the size limit', () {
      final StackList<int> stack = StackList<int>.sized(2);

      stack.push(1);
      stack.push(2);

      expect(() => stack.push(3), throwsException);
    });

    test('should throw for size < 2', () {
      expect(() => StackList<int>.sized(1), throwsException);
      expect(() => StackList<int>.sized(0), throwsException);
      expect(() => StackList<int>.sized(-1), throwsException);
    });

    test('minimum allowed size is 2', () {
      final StackList<int> stack = StackList<int>.sized(2);

      stack.push(1);
      stack.push(2);

      expect(stack.size(), 2);
    });

    test('should allow push after pop even at capacity', () {
      final StackList<int> stack = StackList<int>.sized(2);

      stack.push(1);
      stack.push(2);
      stack.pop();
      stack.push(3);

      expect(stack.size(), 2);
      expect(stack.top(), 3);
    });
  });

  // ---------------------------------------------------------------------------
  // LIFO ordering
  // ---------------------------------------------------------------------------
  group('StackList LIFO ordering', () {
    test('should maintain LIFO order across push and pop', () {
      final StackList<int> stack = StackList<int>();
      final List<int> poppedOrder = <int>[];

      for (int i = 1; i <= 5; i++) {
        stack.push(i);
      }

      while (stack.isNotEmpty) {
        poppedOrder.add(stack.pop());
      }

      expect(poppedOrder, <int>[5, 4, 3, 2, 1]);
    });
  });

  // ---------------------------------------------------------------------------
  // Type safety
  // ---------------------------------------------------------------------------
  group('StackList type safety', () {
    test('should work with String type', () {
      final StackList<String> stack = StackList<String>();
      stack.push('hello');
      stack.push('world');

      expect(stack.pop(), 'world');
      expect(stack.pop(), 'hello');
    });

    test('should work with custom objects', () {
      final StackList<List<int>> stack = StackList<List<int>>();
      stack.push(<int>[1, 2]);
      stack.push(<int>[3, 4]);

      expect(stack.pop(), <int>[3, 4]);
      expect(stack.pop(), <int>[1, 2]);
    });
  });
}
