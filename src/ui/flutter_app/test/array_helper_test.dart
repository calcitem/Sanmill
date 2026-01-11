// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// array_helper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/array_helpers/array_helper.dart';

void main() {
  test(
    "List.lastF should return the last value of the list only if the list is not empty",
    () {
      // Initialize
      final List<int> list = List<int>.generate(5, (int index) => index);

      expect(list.lastF, 4);

      list.clear();
      expect(list.lastF, isNull);
    },
  );
}
