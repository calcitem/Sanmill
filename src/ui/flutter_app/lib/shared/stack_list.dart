import 'dart:collection';
import 'dart:core';

import 'package:flutter/foundation.dart';

class StackList<T> {
  /// Default constructor sets the maximum stack size to 'no limit.'
  StackList() {
    _sizeMax = noLimit;
  }

  /// Constructor in which you can specify maximum number of entries.
  /// This maximum is a limit that is enforced as entries are pushed on to the stack
  /// to prevent stack growth beyond a maximum size. There is no pre-allocation of
  /// slots for entries at any time in this library.
  StackList.sized(int sizeMax) {
    if (sizeMax < 2) {
      throw Exception('Error: stack size must be 2 entries or more ');
    } else {
      _sizeMax = sizeMax;
    }
  }

  final ListQueue<T> _list = ListQueue<T>();

  final int noLimit = -1;

  /// the maximum number of entries allowed on the stack. -1 = no limit.
  int _sizeMax = 0;

  /// Returns a list of T elements contained in the Stack
  List<T> toList() => _list.toList();

  /// check if the stack is empty.
  bool get isEmpty => _list.isEmpty;

  /// check if the stack is not empty.
  bool get isNotEmpty => _list.isNotEmpty;

  /// push element in top of the stack.
  void push(T e) {
    if (_sizeMax == noLimit || _list.length < _sizeMax) {
      _list.addLast(e);
    } else {
      throw Exception(
          'Error: cannot add element. Stack already at maximum size of: $_sizeMax elements');
    }
  }

  /// get the top of the stack and delete it.
  T pop() {
    if (isEmpty) {
      throw Exception(
        "Can't use pop with empty stack\n consider "
        'checking for size or isEmpty before calling pop',
      );
    }
    final T res = _list.last;
    _list.removeLast();
    return res;
  }

  /// get the top of the stack without deleting it.
  T top() {
    if (isEmpty) {
      throw Exception(
        "Can't use top with empty stack\n consider "
        'checking for size or isEmpty before calling top',
      );
    }
    return _list.last;
  }

  /// get the size of the stack.
  int size() {
    return _list.length;
  }

  /// get the length of the stack.
  int get length => size();

  /// returns true if element is found in the stack
  bool contains(T x) {
    return _list.contains(x);
  }

  /// removes all elements from the stack
  void clear() {
    while (isNotEmpty) {
      _list.removeLast();
    }
  }

  /// print stack
  void print() {
    List<T>.from(_list).reversed.toList().forEach((T element) {
      debugPrint(element.toString());
    });
  }
}
