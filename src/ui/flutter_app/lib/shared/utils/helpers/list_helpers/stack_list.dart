// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
      logger.v(element.toString());
    });
  }
}
