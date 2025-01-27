// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

import 'dart:ui';

/// A helper function to compare two candidate colors against a reference color
/// and pick the one with the larger RGB squared-distance difference.
Color pickColorWithMaxDifference(
    Color candidate1, Color candidate2, Color reference) {
  double colorDiff(Color c1, Color c2) {
    final double dr = c1.r - c2.r;
    final double dg = c1.g - c2.g;
    final double db = c1.b - c2.b;
    return dr * dr + dg * dg + db * db;
  }

  return (colorDiff(candidate1, reference) > colorDiff(candidate2, reference))
      ? candidate1
      : candidate2;
}
