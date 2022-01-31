// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
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
import 'package:sanmill/shared/iterable/array_helper.dart';

void main() {
  test(
      "List.lastF should return the last value of the list only if the list is not empty",
      () {
    // initialize
    final list = List.generate(5, (index) => index);

    expect(list.lastF, 4);

    list.clear();
    expect(list.lastF, isNull);
  });
}
