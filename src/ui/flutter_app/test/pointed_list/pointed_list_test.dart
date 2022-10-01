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

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/iterable/pointed_list.dart';

void main() {
  group("PointedList", () {
    test("should construct an empty list by default", () {
      // Initialize
      final list = PointedList<int>();

      expect(list.toList(), []);
    });

    test(
        "PointedList.from should have all elements of the sublist and the global iterator should be at the end of it",
        () {
      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      expect(list.toList(), subList);
      expect(list.index, list.length - 1);
    });
  });

  group("PointedList.prune", () {
    test(
        "prune should remove all elements next to the current pointer position",
        () {
      const index = 2;

      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      // Move forward to
      list.globalIterator.moveTo(index);

      // Prune list
      list.prune();

      final result = List.generate(index + 1, (index) => index);
      expect(list.toList(), result);
    });

    test(
        "prune should not alter the list if the current pointer position is at the end",
        () {
      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      // Prune list
      list.prune();

      expect(list.toList(), subList);
    });

    test("prune should not alter the list if the list is empty", () {
      // Initialize
      final list = PointedList<int>();

      // Prune list
      list.prune();

      expect(list.toList(), []);
    });

    test(
        "Prune should reset the current pointer position to the new last index.",
        () {
      const index = 2;

      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      // Move forward to
      list.globalIterator.moveTo(index);

      // Prune list
      list.prune();

      expect(list.globalIterator.index, index);
    });
  });
  group("PointedList.add", () {
    test("add should add the value next to the current position", () {
      const index = 2;
      const value = 3;

      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      // Move to index
      list.globalIterator.moveTo(index - 1);

      // Add list
      list.add(value);

      final result = List.generate(index, (index) => index);
      result.add(value);
      expect(list.toList(), result);
    });

    test("add should iterate the global iterator", () {
      // Initialize
      final subList = List.generate(10, (index) => index);
      final list = PointedList.from(subList);

      final oldIndex = list.index!;

      // Add list
      list.add(5);

      expect(list.index, oldIndex + 1);
    });
  });
  test(
      "PointedList.forEachVisible should iterate over every entry up to (including) the pointer",
      () {
    const index = 3;

    // Initialize
    final subList = List.generate(10, (index) => index);
    final list = PointedList.from(subList);

    final result = <int>[];

    // Move to index
    list.globalIterator.moveTo(index);

    // Iterate
    list.forEachVisible((value) => result.add(value));

    final resultExpect = List.generate(index + 1, (index) => index);

    expect(result, resultExpect);
  });
}
