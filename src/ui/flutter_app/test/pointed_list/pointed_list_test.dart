// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// pointed_list_test.dart

// ignore_for_file: always_specify_types

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/list_helpers/pointed_list.dart';

void main() {
  group("PointedList", () {
    test("should construct an empty list by default", () {
      // Initialize
      final PointedList<int> list = PointedList<int>();

      expect(list.toList(), <int>[]);
    });

    test(
      "PointedList.from should have all elements of the sublist and the global iterator should be at the end of it",
      () {
        // Initialize
        final List<int> subList = List.generate(10, (int index) => index);
        final PointedList<int> list = PointedList.from(subList);

        expect(list.toList(), subList);
        expect(list.index, list.length - 1);
      },
    );
  });

  group("PointedList.prune", () {
    test(
      "prune should remove all elements next to the current pointer position",
      () {
        const int index = 2;

        // Initialize
        final List<int> subList = List.generate(10, (int index) => index);
        final PointedList<int> list = PointedList.from(subList);

        // Move forward to
        list.globalIterator.moveTo(index);

        // Prune list
        list.prune();

        final List<int> result = List.generate(index + 1, (int index) => index);
        expect(list.toList(), result);
      },
    );

    test(
      "prune should not alter the list if the current pointer position is at the end",
      () {
        // Initialize
        final List<int> subList = List.generate(10, (int index) => index);
        final PointedList<int> list = PointedList.from(subList);

        // Prune list
        list.prune();

        expect(list.toList(), subList);
      },
    );

    test("prune should not alter the list if the list is empty", () {
      // Initialize
      final PointedList<int> list = PointedList<int>();

      // Prune list
      list.prune();

      expect(list.toList(), []);
    });

    test(
      "Prune should reset the current pointer position to the new last index.",
      () {
        const int index = 2;

        // Initialize
        final List<int> subList = List.generate(10, (int index) => index);
        final PointedList<int> list = PointedList.from(subList);

        // Move forward to
        list.globalIterator.moveTo(index);

        // Prune list
        list.prune();

        expect(list.globalIterator.index, index);
      },
    );
  });
  group("PointedList.add", () {
    test("add should add the value next to the current position", () {
      const int index = 2;
      const int value = 3;

      // Initialize
      final List<int> subList = List.generate(10, (int index) => index);
      final PointedList<int> list = PointedList.from(subList);

      // Move to index
      list.globalIterator.moveTo(index - 1);

      // Add list
      list.add(value);

      final List<int> result = List.generate(index, (int index) => index);
      result.add(value);
      expect(list.toList(), result);
    });

    test("add should iterate the global iterator", () {
      // Initialize
      final List<int> subList = List.generate(10, (int index) => index);
      final PointedList<int> list = PointedList.from(subList);

      final int oldIndex = list.index!;

      // Add list
      list.add(5);

      expect(list.index, oldIndex + 1);
    });
  });
  test(
    "PointedList.forEachVisible should iterate over every entry up to (including) the pointer",
    () {
      const int index = 3;

      // Initialize
      final List<int> subList = List.generate(10, (int index) => index);
      final PointedList<int> list = PointedList.from(subList);

      final List<int> result = <int>[];

      // Move to index
      list.globalIterator.moveTo(index);

      // Iterate
      list.forEachVisible((int value) => result.add(value));

      final List<int> resultExpect = List.generate(
        index + 1,
        (int index) => index,
      );

      expect(result, resultExpect);
    },
  );
}
