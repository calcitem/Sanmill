// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// color_helper.dart

import 'dart:ui';

/// A helper function to compare two candidate colors against a reference color
/// and pick the one with the larger RGB squared-distance difference.
Color pickColorWithMaxDifference(
    Color candidate1, Color candidate2, Color reference) {
  double colorDiff(Color c1, Color c2) {
    final double dr = c1.red.toDouble() - c2.red.toDouble();
    final double dg = c1.green.toDouble() - c2.green.toDouble();
    final double db = c1.blue.toDouble() - c2.blue.toDouble();
    return dr * dr + dg * dg + db * db;
  }

  return (colorDiff(candidate1, reference) > colorDiff(candidate2, reference))
      ? candidate1
      : candidate2;
}
