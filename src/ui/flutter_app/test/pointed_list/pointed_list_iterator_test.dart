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

// ignore_for_file: always_specify_types, strict_raw_type

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/list_helpers/pointed_list.dart';

void main() {
  group("PointedListIterator", () {
    test(
        "Current should be populated with the first element when parent isNotEmpty",
        () {
      // Initialize
      final List<int> list = <int>[1, 2, 3, 4, 5];
      final PointedListIterator<int> iterator = PointedListIterator(list);

      expect(iterator.current, list.first);
    });

    test("Current should be null when parent isEmpty", () {
      // Initialize
      final List list = [];
      final PointedListIterator iterator = PointedListIterator(list);

      expect(iterator.current, isNull);
    });
  });

  group("PointedListIterator.move", () {
    test("moveTo should return when the parent isEmpty", () {
      // Initialize
      final List list = [];
      final PointedListIterator iterator = PointedListIterator(list);
      final PointedListIterator snapshot = PointedListIterator(list);

      iterator.moveTo(2);

      expect(iterator, snapshot);
    });

    test("moveTo should move to the given index", () {
      const int index = 2;

      // Initialize
      final List<int> list = [1, 2, 3, 4, 5, 6];
      final PointedListIterator<int> iterator = PointedListIterator(list);

      iterator.moveTo(index);

      expect(iterator.current, list[index]);
    });

    test("moveToLast should move to the last index", () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);

      iterator.moveToLast();

      expect(iterator.current, list.last);
    });

    test("moveToFirst should move to the first index", () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);
      iterator.moveToLast();

      iterator.moveToFirst();

      expect(iterator.current, list.first);
    });

    test("moveNext should move to the next index", () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);

      expect(iterator.moveNext(), true);

      expect(iterator.current, list[1]);
    });

    test(
        "moveNext should not move to the next index and return false when current is the last element",
        () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);
      iterator.moveToLast();

      expect(iterator.moveNext(), false);

      expect(iterator.current, list.last);
    });

    test("moveNext should not move to the next when the parent is empty", () {
      // Initialize
      final List list = [];
      final PointedListIterator iterator = PointedListIterator(list);

      expect(iterator.moveNext(), false);
    });

    test("movePrevious should move to the previous index", () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);
      iterator.moveToLast();

      expect(iterator.movePrevious(), true);

      expect(iterator.current, list[list.length - 2]);
    });

    test(
        "movePrevious should not move to the previous index and return false when current is the first element",
        () {
      // Initialize
      final List<int> list = [1, 2, 3, 4];
      final PointedListIterator<int> iterator = PointedListIterator(list);
      iterator.moveToFirst();

      expect(iterator.movePrevious(), true);

      expect(iterator.current, isNull);
    });

    test(
        "movePrevious should not move to the previous when the parent is empty",
        () {
      // Initialize
      final List list = [];
      final PointedListIterator iterator = PointedListIterator(list);

      expect(iterator.movePrevious(), false);
    });
  });
}
