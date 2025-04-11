// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// stack_list.dart

import 'dart:collection';
import 'dart:core';

import '../../../services/logger.dart';

class StackList<T> {
  /// Default constructor sets the maximum stack size to 'no limit.'
  StackList() {
    _maxStackSize = _noLimit;
  }

  /// Constructor in which you can specify maximum number of entries.
  /// This maximum is a limit that is enforced as entries are pushed on to the stack
  /// to prevent stack growth beyond a maximum size. There is no pre-allocation of
  /// slots for entries at any time in this library.
  StackList.sized(int maxStackSize) {
    if (maxStackSize < 2) {
      throw Exception('Error: stack size must be 2 entries or more ');
    } else {
      _maxStackSize = maxStackSize;
    }
  }

  final ListQueue<T> _list = ListQueue<T>();

  final int _noLimit = -1;

  /// The maximum number of entries allowed on the stack. -1 = no limit.
  int _maxStackSize = 0;

  /// Returns a list of T elements contained in the Stack
  List<T> toList() => _list.toList();

  /// Check if the stack is empty.
  bool get isEmpty => _list.isEmpty;

  /// Check if the stack is not empty.
  bool get isNotEmpty => _list.isNotEmpty;

  /// Push element in top of the stack.
  void push(T element) {
    if (_maxStackSize == _noLimit || _list.length < _maxStackSize) {
      _list.addLast(element);
    } else {
      throw Exception(
          'Error: Cannot add element. Stack already at maximum size of: $_maxStackSize elements');
    }
  }

  /// Get the top of the stack and delete it.
  T pop() {
    if (isEmpty) {
      throw Exception(
        "Can't use pop with empty stack\n consider "
        'checking for size or isEmpty before calling pop',
      );
    }
    final T poppedElement = _list.last;
    _list.removeLast();
    return poppedElement;
  }

  /// Get the top of the stack without deleting it.
  T top() {
    if (isEmpty) {
      throw Exception(
        "Can't use top with empty stack\n consider "
        'checking for size or isEmpty before calling top',
      );
    }
    return _list.last;
  }

  /// Get the size of the stack.
  int size() {
    return _list.length;
  }

  /// Get the length of the stack.
  int get length => size();

  /// Returns true if element is found in the stack
  bool contains(T searchElement) {
    return _list.contains(searchElement);
  }

  /// Removes all elements from the stack
  void clear() {
    while (isNotEmpty) {
      _list.removeLast();
    }
  }

  /// Print stack
  void print() {
    List<T>.from(_list).reversed.toList().forEach((T element) {
      logger.t(element.toString());
    });
  }
}
