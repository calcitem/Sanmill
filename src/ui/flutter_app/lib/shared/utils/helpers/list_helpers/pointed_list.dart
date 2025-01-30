// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// pointed_list.dart

import 'package:collection/collection.dart';

/// Pointed List.
///
/// A list with a final [globalIterator] that can be used to navigate through the list.
class PointedList<E> extends DelegatingList<E> {
  /// Creates an empty [PointedList].
  PointedList() : this._(<E>[]);

  /// Creates a [PointedList] popularized with the given [elements].
  ///
  /// The [globalIterator] will be set to the last element by default.
  PointedList.from(List<E> elements) : this._(elements);

  PointedList._(List<E> list)
      : _list = list,
        globalIterator = PointedListIterator<E>(list),
        super(list) {
    if (list.isNotEmpty) {
      globalIterator.moveToLast();
    }
  }
  late final List<E> _list;

  /// The [PointedListIterator] used to navigate through the list.
  late final PointedListIterator<E> globalIterator;

  /// Prunes the list from any element currently out of focus.
  ///
  /// This is equivalent to `removeRange(globalIterator.index + 1, this.length)`.
  void prune() {
    if (_list.isEmpty) {
      return;
    }
    if (!globalIterator.hasNext) {
      return;
    }

    if (globalIterator.index == null) {
      _list.removeRange(0, _list.length);
    } else {
      _list.removeRange(globalIterator.index! + 1, _list.length);
    }
  }

  @override
  void add(E value) {
    prune();
    _list.add(value);
    globalIterator.moveNext();
  }

  void addAndDeduplicate(E value) {
    if (globalIterator.index != -1 && current != value) {
      add(value);
    }
  }

  /// Gets the element currently in focus.
  ///
  /// This is equivalent to [globalIterator.current].
  E? get current => globalIterator.current;

  /// Gets the index of the currently focused element.
  ///
  /// This is equivalent to [globalIterator.index].
  int? get index => globalIterator.index;

  /// Iterates over every visible element.
  ///
  /// This is equivalent to a loop from `0` to `index`.
  void forEachVisible(void Function(E p1) f) {
    if (index == null) {
      return;
    }

    for (int i = 0; i <= index!; i++) {
      f(_list[i]);
    }
  }

  /// Check if there is still part that can be pruned.
  bool get isClean =>
      (globalIterator.index == _list.length - 1) ||
      (globalIterator.index == null && _list.isEmpty);

  /// Whether the list has another element previous to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasPrevious => globalIterator.hasPrevious;

  /// Returns a new BidirectionalIterator that allows iterating the elements of this Iterable.
  ///
  /// Each time bidirectionalIterator is read, it returns a new iterator, which can be used to iterate through all the elements again. The iterators of the same iterable can be stepped through independently, but should return the same elements in the same order, as long as the underlying collection isn't changed.
  ///
  /// Modifying the collection may cause new iterators to produce different elements, and may change the order of existing elements. A [List] specifies its iteration order precisely, so modifying the list changes the iteration order predictably. A hash-based [Set] may change its iteration order completely when adding a new element to the set.
  ///
  /// Modifying the underlying collection after creating the new iterator may cause an error the next time [Iterator.moveNext] is called on that iterator. Any modifiable iterable class should specify which operations will break iteration.
  ///
  /// Copied from Iterable.
  PointedListIterator<E> get bidirectionalIterator =>
      PointedListIterator<E>(_list);
}

/// Pointed List Iterator.
class PointedListIterator<E> {
  PointedListIterator(this._sourceList) {
    if (_sourceList.isNotEmpty) {
      _currentIndex = 0;
    }
  }
  final List<E> _sourceList;
  int? _currentIndex;

  bool moveNext() {
    if (!hasNext) {
      return false;
    }

    if (_currentIndex == null) {
      _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex! + 1;
    }

    //assert(current != prev);

    return true;
  }

  bool movePrevious() {
    if (!hasPrevious) {
      return false;
    }

    if (_currentIndex == 0) {
      _currentIndex = null;
    } else {
      _currentIndex = _currentIndex! - 1;
    }

    return true;
  }

  /// Move to the given element.
  void moveTo(int index) {
    if (_sourceList.isNotEmpty) {
      _currentIndex = index;
    }
  }

  /// Move to the last element.
  ///
  /// This is equivalent to `moveTo(lastIndex)`.
  void moveToLast() => moveTo(lastIndex);

  /// Move to the first element.
  ///
  /// This is equivalent to `moveTo(0)`.
  void moveToFirst() => moveTo(0);

  /// Move to the head.
  ///
  /// Head is a list node that contains no actual data.
  void moveToHead() => _currentIndex = null;

  /// The currently selected index.
  int? get index => _currentIndex;

  /// The last valid index.
  int get lastIndex => _sourceList.length - 1;

  /// Whether the list has another element next to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasNext => _sourceList.isNotEmpty && _currentIndex != lastIndex;

  /// Whether the list has another element previous to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasPrevious => _sourceList.isNotEmpty && _currentIndex != null;

  E? get current {
    if (_currentIndex == null) {
      return null;
    }

    return _sourceList[_currentIndex!];
  }

  E? get prev {
    if (_currentIndex == null ||
        index == 0 ||
        _sourceList[_currentIndex! - 1] == null) {
      return null;
    }

    return _sourceList[_currentIndex! - 1];
  }

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      other is PointedListIterator &&
      _sourceList == other._sourceList &&
      _currentIndex == other._currentIndex;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(_sourceList, _currentIndex);
}
