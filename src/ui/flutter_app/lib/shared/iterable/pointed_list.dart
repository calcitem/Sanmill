// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
  late final List<E> _l;

  /// The [PointedListIterator] used to navigate through the list.
  late final PointedListIterator<E> globalIterator;

  /// Creates an empty [PointedList].
  PointedList() : this._(<E>[]);

  /// Creates a [PointedList] popularized with the given [elements].
  ///
  /// The [globalIterator] will be set to the last element by default.
  PointedList.from(List<E> elements) : this._(elements);

  PointedList._(List<E> l)
      : _l = l,
        globalIterator = PointedListIterator(l),
        super(l) {
    if (l.isNotEmpty) {
      globalIterator.moveToLast();
    }
  }

  /// Prunes the list from any element currently out of focus.
  ///
  /// This is equvalent to `removeRange(globalIterator.index + 1, this.length)`.
  void prune() {
    if (_l.isEmpty) return;
    if (!globalIterator.hasNext) return;

    _l.removeRange(globalIterator.index! + 1, _l.length);
  }

  @override
  void add(E value) {
    prune();
    _l.add(value);
    globalIterator.moveNext();
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
    if (index == null) return;

    for (int i = 0; i <= index!; i++) {
      f(_l[i]);
    }
  }

  /// Returns a new BidirectionalIterator that allows iterating the elements of this Iterable.
  ///
  /// Each time bidirectionalIterator is read, it returns a new iterator, which can be used to iterate through all the elements again. The iterators of the same iterable can be stepped through independently, but should return the same elements in the same order, as long as the underlying collection isn't changed.
  ///
  /// Modifying the collection may cause new iterators to produce different elements, and may change the order of existing elements. A [List] specifies its iteration order precisely, so modifying the list changes the iteration order predictably. A hash-based [Set] may change its iteration order completely when adding a new element to the set.
  ///
  /// Modifying the underlying collection after creating the new iterator may cause an error the next time [Iterator.moveNext] is called on that iterator. Any modifiable iterable class should specify which operations will break iteration.
  ///
  /// Copied from Iterable.
  PointedListIterator<E> get bidirectionalIterator => PointedListIterator(_l);
}

/// Pointed List Iterator.
///
/// A [BidirectionalIterator] to be used with but not limited to a [PointedList].
class PointedListIterator<E> extends BidirectionalIterator<E?> {
  final List<E> _parent;
  int? _index;

  PointedListIterator(this._parent) {
    if (_parent.isNotEmpty) {
      _index = 0;
    }
  }

  @override
  bool moveNext() {
    if (!hasNext) {
      return false;
    } else if (_index == null) {
      _index = 0;
    } else {
      _index = _index! + 1;
    }
    return true;
  }

  @override
  bool movePrevious() {
    if (!hasPrevious) {
      return false;
    } else if (_index == null) {
      _index = 0;
    } else {
      _index = _index! - 1;
    }
    return true;
  }

  /// Move to the given element.
  void moveTo(int index) {
    if (_parent.isNotEmpty) {
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

  /// The currently selected index.
  int? get index => _index;

  /// The last valid index.
  int get lastIndex => _parent.length - 1;

  /// Whether the list has another element next to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasNext => _parent.isNotEmpty && _index != lastIndex;

  /// Whether the list has another element previous to the iterator.
  ///
  /// This has the benefit of not altering the iterator while still being able to check it.
  bool get hasPrevious => _parent.isNotEmpty && _index != 0;

  @override
  E? get current {
    if (_index != null) {
      return _parent[_index!];
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PointedListIterator &&
      _parent == other._parent &&
      _index == other._index;

  @override
  int get hashCode => Object.hash(_parent, _index);
}
