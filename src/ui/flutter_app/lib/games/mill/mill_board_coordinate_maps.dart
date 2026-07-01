// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Stable coordinate maps for the 24-point Mill board.
///
/// These values preserve the legacy Flutter 7x7 grid indices and C++ square
/// ids while exposing them from the game module instead of `position.dart` /
/// `types.dart`.  Native snapshot views and future board-rendering code use
/// this as the compatibility layer until the legacy grid disappears.
abstract final class MillBoardCoordinateMaps {
  static const int legacySquareBegin = 8;
  static const int legacySquareEnd = 32;
  static const int legacySquareStorageSize = 40;
  static const int fileNumber = 3;
  static const int fileExNumber = fileNumber + 2;
  static const int rankNumber = 8;

  static const Map<int, int> squareToGridIndex = <int, int>{
    8: 17,
    9: 18,
    10: 25,
    11: 32,
    12: 31,
    13: 30,
    14: 23,
    15: 16,
    16: 10,
    17: 12,
    18: 26,
    19: 40,
    20: 38,
    21: 36,
    22: 22,
    23: 8,
    24: 3,
    25: 6,
    26: 27,
    27: 48,
    28: 45,
    29: 42,
    30: 21,
    31: 0,
  };

  static const Map<int, int> gridIndexToSquare = <int, int>{
    17: 8,
    18: 9,
    25: 10,
    32: 11,
    31: 12,
    30: 13,
    23: 14,
    16: 15,
    10: 16,
    12: 17,
    26: 18,
    40: 19,
    38: 20,
    36: 21,
    22: 22,
    8: 23,
    3: 24,
    6: 25,
    27: 26,
    48: 27,
    45: 28,
    42: 29,
    21: 30,
    0: 31,
  };

  static const Map<int, int> nodeToLegacySquare = <int, int>{
    0: 8,
    1: 9,
    2: 10,
    3: 11,
    4: 12,
    5: 13,
    6: 14,
    7: 15,
    8: 16,
    9: 17,
    10: 18,
    11: 19,
    12: 20,
    13: 21,
    14: 22,
    15: 23,
    16: 24,
    17: 25,
    18: 26,
    19: 27,
    20: 28,
    21: 29,
    22: 30,
    23: 31,
  };

  static const Map<int, int> legacySquareToNode = <int, int>{
    8: 0,
    9: 1,
    10: 2,
    11: 3,
    12: 4,
    13: 5,
    14: 6,
    15: 7,
    16: 8,
    17: 9,
    18: 10,
    19: 11,
    20: 12,
    21: 13,
    22: 14,
    23: 15,
    24: 16,
    25: 17,
    26: 18,
    27: 19,
    28: 20,
    29: 21,
    30: 22,
    31: 23,
  };

  static const Map<int, String> squareToNotation = <int, String>{
    8: 'd5',
    9: 'e5',
    10: 'e4',
    11: 'e3',
    12: 'd3',
    13: 'c3',
    14: 'c4',
    15: 'c5',
    16: 'd6',
    17: 'f6',
    18: 'f4',
    19: 'f2',
    20: 'd2',
    21: 'b2',
    22: 'b4',
    23: 'b6',
    24: 'd7',
    25: 'g7',
    26: 'g4',
    27: 'g1',
    28: 'd1',
    29: 'a1',
    30: 'a4',
    31: 'a7',
  };

  static const Map<String, int> notationToSquare = <String, int>{
    'd5': 8,
    'e5': 9,
    'e4': 10,
    'e3': 11,
    'd3': 12,
    'c3': 13,
    'c4': 14,
    'c5': 15,
    'd6': 16,
    'f6': 17,
    'f4': 18,
    'f2': 19,
    'd2': 20,
    'b2': 21,
    'b4': 22,
    'b6': 23,
    'd7': 24,
    'g7': 25,
    'g4': 26,
    'g1': 27,
    'd1': 28,
    'a1': 29,
    'a4': 30,
    'a7': 31,
  };

  static const Map<String, String> playOkToStandardNotation = <String, String>{
    '1': 'a7',
    '2': 'd7',
    '3': 'g7',
    '4': 'b6',
    '5': 'd6',
    '6': 'f6',
    '7': 'c5',
    '8': 'd5',
    '9': 'e5',
    '10': 'a4',
    '11': 'b4',
    '12': 'c4',
    '13': 'e4',
    '14': 'f4',
    '15': 'g4',
    '16': 'c3',
    '17': 'd3',
    '18': 'e3',
    '19': 'b2',
    '20': 'd2',
    '21': 'f2',
    '22': 'a1',
    '23': 'd1',
    '24': 'g1',
  };

  static int notationToLegacySquare(String notation) {
    return notationToSquare[notation.trim().toLowerCase()] ?? -1;
  }

  static int makeLegacySquare(int file, int rank) {
    assert(file != -2 && rank != -2);
    if (file == 0 && rank == 0) {
      return 0;
    }
    if (file == -1 && rank == -1) {
      return -1;
    }
    return (file << 3) + rank - 1;
  }

  static bool isLegacySquareOk(int square) {
    return square == 0 ||
        (square >= legacySquareBegin && square < legacySquareEnd);
  }

  static int fileOfLegacySquare(int square) {
    return square >> 3;
  }

  static int rankOfLegacySquare(int square) {
    return (square & 0x07) + 1;
  }

  static String legacySquareToNotation(int square) {
    return squareToNotation[square] ?? '';
  }

  static String nodeToNotation(int node) {
    final int? square = nodeToLegacySquare[node];
    return square == null ? '' : legacySquareToNotation(square);
  }

  static int notationToNode(String notation) {
    final int square = notationToLegacySquare(notation);
    return legacySquareToNode[square] ?? -1;
  }

  static const List<List<int>> standardMillNodeLines = <List<int>>[
    <int>[7, 0, 1],
    <int>[1, 2, 3],
    <int>[3, 4, 5],
    <int>[5, 6, 7],
    <int>[15, 8, 9],
    <int>[9, 10, 11],
    <int>[11, 12, 13],
    <int>[13, 14, 15],
    <int>[23, 16, 17],
    <int>[17, 18, 19],
    <int>[19, 20, 21],
    <int>[21, 22, 23],
    <int>[0, 8, 16],
    <int>[2, 10, 18],
    <int>[4, 12, 20],
    <int>[6, 14, 22],
  ];

  static const List<List<int>> diagonalMillNodeLines = <List<int>>[
    ...standardMillNodeLines,
    <int>[23, 15, 7],
    <int>[1, 9, 17],
    <int>[21, 13, 5],
    <int>[3, 11, 19],
  ];
}
