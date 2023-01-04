// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

  PointedList._(List<E> l)
      : _l = l,
        globalIterator = PointedListIterator<E>(l),
        super(l) {
    if (l.isNotEmpty) {
      globalIterator.moveToLast();
    }
  }
  late final List<E> _l;

  /// The [PointedListIterator] used to navigate through the list.
  late final PointedListIterator<E> globalIterator;

  /// Prunes the list from any element currently out of focus.
  ///
  /// This is equivalent to `removeRange(globalIterator.index + 1, this.length)`.
  void prune() {
    if (_l.isEmpty) {
      return;
    }
    if (!globalIterator.hasNext) {
      return;
    }

    if (globalIterator.index == null) {
      _l.removeRange(0, _l.length);
    } else {
      _l.removeRange(globalIterator.index! + 1, _l.length);
    }
  }

  @override
  void add(E value) {
    prune();
    _l.add(value);
    globalIterator.moveNext();
  }

  void addAndDeduplicate(E value) {
    if (current != value) {
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
      f(_l[i]);
    }
  }

  /// Check if there is still part that can be pruned.
  bool get isClean =>
      (globalIterator.index == _l.length - 1) ||
      (globalIterator.index == null && _l.isEmpty);

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
      PointedListIterator<E>(_l);
}

/// Pointed List Iterator.
class PointedListIterator<E> {
  PointedListIterator(this._base) {
    if (_base.isNotEmpty) {
      _index = 0;
    }
  }
  final List<E> _base;
  int? _index;

  bool moveNext() {
    if (!hasNext) {
      return false;
    }

    if (_index == null) {
      _index = 0;
    } else {
      _index = _index! + 1;
    }

    //assert(current != prev);

    return true;
  }

  bool movePrevious() {
    if (!hasPrevious) {
      return false;
    }

    if (_index == 0) {
      _index = null;
    } else {
      _index = _index! - 1;
    }

    return true;
  }

  /// Move to the given element.
  void moveTo(int index) {
    if (_base.isNotEmpty) {
      _index = index;
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
  void moveToHead() => _index = null;

  /// The currently selected index.
  int? get index => _index;

  /// The last valid index.
  int get lastIndex => _base.length - 1;

  /// Whether the list has another element next to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasNext => _base.isNotEmpty && _index != lastIndex;

  /// Whether the list has another element previous to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasPrevious => _base.isNotEmpty && _index != null;

  E? get current {
    if (_index == null) {
      return null;
    }

    return _base[_index!];
  }

  E? get prev {
    if (_index == null || index == 0 || _base[_index! - 1] == null) {
      return null;
    }

    return _base[_index! - 1];
  }

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      other is PointedListIterator &&
      _base == other._base &&
      _index == other._index;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(_base, _index);
}
