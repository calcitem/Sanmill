// This file is part of Sanmill.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
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

// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

String funcIdString(String s) {
  return s;
}

// Rotate 90 degrees Transformation

String rot90String(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    6,
    7,
    0,
    1,
    2,
    3,
    4,
    5,
    14,
    15,
    8,
    9,
    10,
    11,
    12,
    13,
    22,
    23,
    16,
    17,
    18,
    19,
    20,
    21
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

String rot180String(String s) {
  return rot90String(rot90String(s));
}

String rot270String(String s) {
  return rot90String(rot180String(s));
}

// Vertical Flip Transformation

String ttFuggolegesString(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    4,
    3,
    2,
    1,
    0,
    7,
    6,
    5,
    12,
    11,
    10,
    9,
    8,
    15,
    14,
    13,
    20,
    19,
    18,
    17,
    16,
    23,
    22,
    21
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

// Horizontal Flip Transformation

String ttVizszintesString(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    0,
    7,
    6,
    5,
    4,
    3,
    2,
    1,
    8,
    15,
    14,
    13,
    12,
    11,
    10,
    9,
    16,
    23,
    22,
    21,
    20,
    19,
    18,
    17
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

// Backslash Diagonal Flip Transformation

String ttBSlashString(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    2,
    1,
    0,
    7,
    6,
    5,
    4,
    3,
    10,
    9,
    8,
    15,
    14,
    13,
    12,
    11,
    18,
    17,
    16,
    23,
    22,
    21,
    20,
    19
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

// Forward Slash Diagonal Flip Transformation

String ttSlashString(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    6,
    5,
    4,
    3,
    2,
    1,
    0,
    7,
    14,
    13,
    12,
    11,
    10,
    9,
    8,
    15,
    22,
    21,
    20,
    19,
    18,
    17,
    16,
    23
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

// Swap Upper and Lower Half

String swapString(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }

  final List<int> newPosition = <int>[
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7
  ];

  final List<String> result = List<String>.filled(24, '');

  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }

  return result.join();
}

String swapRot90String(String s) {
  return swapString(rot90String(s));
}

String swapRot180String(String s) {
  return swapString(rot180String(s));
}

String swapRot270String(String s) {
  return swapString(rot270String(s));
}

String swapTtFuggolegesString(String s) {
  return swapString(ttFuggolegesString(s));
}

String swapTtVizszintesString(String s) {
  return swapString(ttVizszintesString(s));
}

String swapTtBSlashString(String s) {
  return swapString(ttBSlashString(s));
}

String swapTtSlashString(String s) {
  return swapString(ttSlashString(s));
}
