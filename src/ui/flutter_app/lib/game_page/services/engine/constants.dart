// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// constants.dart

part of '../mill.dart';

/// Game constants for different Morris variants
class GameConstants {
  const GameConstants._();

  /// Valid squares for Six Men's Morris (only middle and outer rings)
  /// - Inner ring: squares 8..15 (not used in Six Men's Morris)
  /// - Middle ring: squares 16..23
  /// - Outer ring: squares 24..31
  static const List<int> sixMensMorrisValidSquares = <int>[
    // Middle ring
    16, 17, 18, 19, 20, 21, 22, 23,
    // Outer ring
    24, 25, 26, 27, 28, 29, 30, 31
  ];

  /// Valid point indices for Six Men's Morris in the points array
  /// - Points for outer square are at indices: 0, 1, 2, 9, 14, 21, 22, 23
  /// - Points for middle square are at indices: 3, 4, 5, 10, 13, 18, 19, 20
  static const List<int> sixMensMorrisValidPointIndices = <int>[
    0,
    1,
    2,
    3,
    4,
    5,
    9,
    10,
    13,
    14,
    18,
    19,
    20,
    21,
    22,
    23
  ];
}
