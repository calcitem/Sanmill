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

void _validateInput(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }
}

String _transformString(String s, List<int> newPosition) {
  _validateInput(s);
  final List<String> result = List<String>.filled(24, '');
  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }
  return result.join();
}

// Identity Transformation
String identityTransform(String s) {
  return s; // This function directly returns the input as it is.
}

// Rotate 90 Degrees
String rotate90Degrees(String s) {
  final List<int> newPosition = <int>[
    6, 7, 0, 1, 2, 3, 4, 5,
    14, 15, 8, 9, 10, 11, 12, 13,
    22, 23, 16, 17, 18, 19, 20, 21
  ];
  return _transformString(s, newPosition);
}

// Rotate 180 Degrees
String rotate180Degrees(String s) {
  return rotate90Degrees(rotate90Degrees(s));
}

// Rotate 270 Degrees
String rotate270Degrees(String s) {
  return rotate90Degrees(rotate180Degrees(s));
}

// Vertical Flip
String verticalFlip(String s) {
  final List<int> newPosition = <int>[
    4, 3, 2, 1, 0, 7, 6, 5,
    12, 11, 10, 9, 8, 15, 14, 13,
    20, 19, 18, 17, 16, 23, 22, 21
  ];
  return _transformString(s, newPosition);
}

// Horizontal Flip
String horizontalFlip(String s) {
  final List<int> newPosition = <int>[
    0, 7, 6, 5, 4, 3, 2, 1,
    8, 15, 14, 13, 12, 11, 10, 9,
    16, 23, 22, 21, 20, 19, 18, 17
  ];
  return _transformString(s, newPosition);
}

// Diagonal Flip (Backslash)
String diagonalFlipBackslash(String s) {
  final List<int> newPosition = <int>[
    2, 1, 0, 7, 6, 5, 4, 3,
    10, 9, 8, 15, 14, 13, 12, 11,
    18, 17, 16, 23, 22, 21, 20, 19
  ];
  return _transformString(s, newPosition);
}

// Diagonal Flip (Forward Slash)
String diagonalFlipForwardSlash(String s) {
  final List<int> newPosition = <int>[
    6, 5, 4, 3, 2, 1, 0, 7,
    14, 13, 12, 11, 10, 9, 8, 15,
    22, 21, 20, 19, 18, 17, 16, 23
  ];
  return _transformString(s, newPosition);
}

// Swap Upper and Lower Half
String swapUpperLowerHalf(String s) {
  final List<int> newPosition = <int>[
    16, 17, 18, 19, 20, 21, 22, 23,
    8, 9, 10, 11, 12, 13, 14, 15,
    0, 1, 2, 3, 4, 5, 6, 7
  ];
  return _transformString(s, newPosition);
}

// Combined Transformations, e.g., Swap and Rotate 90 Degrees
String swapAndRotate90Degrees(String s) {
  return swapUpperLowerHalf(rotate90Degrees(s));
}

// Swap and Rotate 180 Degrees
String swapAndRotate180Degrees(String s) {
  return swapUpperLowerHalf(rotate180Degrees(s));
}

// Swap and Rotate 270 Degrees
String swapAndRotate270Degrees(String s) {
  return swapUpperLowerHalf(rotate270Degrees(s));
}

// Swap and Vertical Flip
String swapAndVerticalFlip(String s) {
  return swapUpperLowerHalf(verticalFlip(s));
}

// Swap and Horizontal Flip
String swapAndHorizontalFlip(String s) {
  return swapUpperLowerHalf(horizontalFlip(s));
}

// Swap and Diagonal Flip (Backslash)
String swapAndDiagonalFlipBackslash(String s) {
  return swapUpperLowerHalf(diagonalFlipBackslash(s));
}

// Swap and Diagonal Flip (Forward Slash)
String swapAndDiagonalFlipForwardSlash(String s) {
  return swapUpperLowerHalf(diagonalFlipForwardSlash(s));
}
