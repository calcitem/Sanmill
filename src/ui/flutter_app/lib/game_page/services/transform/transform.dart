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

enum TransformationType {
  identity,
  rotate90Degrees,
  horizontalFlip,
  verticalFlip,
  innerOuterFlip
}

// Transformation mapping configuration
final Map<TransformationType, List<int>> transformationMap =
    <TransformationType, List<int>>{
  TransformationType.identity: List<int>.generate(24, (int i) => i),
  TransformationType.rotate90Degrees: <int>[
    2,
    3,
    4,
    5,
    6,
    7,
    0,
    1,
    10,
    11,
    12,
    13,
    14,
    15,
    8,
    9,
    18,
    19,
    20,
    21,
    22,
    23,
    16,
    17,
  ],
  TransformationType.horizontalFlip: <int>[
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
  ],
  TransformationType.verticalFlip: <int>[
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
  ],
  TransformationType.innerOuterFlip: <int>[
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
    7,
  ],
};

// Validator to ensure correct string length
void _validateInput(String s) {
  if (s.length != 24) {
    throw ArgumentError('Input string must be exactly 24 characters long.');
  }
}

// Core transformation function using mapping
String _transformString(String s, List<int> newPosition) {
  _validateInput(s);
  final List<String> result = List<String>.filled(24, '');
  for (int i = 0; i < 24; i++) {
    result[newPosition[i]] = s[i];
  }
  return result.join();
}

// Public function to perform transformation based on the type
String transformString(String s, TransformationType transformationType) {
  final List<int> newPosition = transformationMap[transformationType] ??
      List<int>.generate(24, (int i) => i);
  return _transformString(s, newPosition);
}

String transformFEN(String fen, TransformationType transformationType) {
  // Extract the first 26 characters, which include the board description part of the FEN string
  final String boardPart = fen.substring(0, 26);
  // Extract the remainder of the FEN string
  final String otherPart = fen.substring(26);

  // Record the positions of each '/' character
  final List<int> slashPositions = <int>[];
  for (int i = 0; i < boardPart.length; i++) {
    if (boardPart[i] == '/') {
      slashPositions.add(i);
    }
  }

  // Remove all '/' characters
  final String transformedInput = boardPart.replaceAll('/', '');

  // Transform the string using the given transformation type
  final String transformedOutput =
      transformString(transformedInput, transformationType);

  // Insert '/' back into their original positions
  final StringBuffer newBoardPart = StringBuffer();
  int slashIndex = 0;
  for (int i = 0; i < transformedOutput.length; i++) {
    // When the current index reaches a position where '/' should be reinserted, insert it
    if (slashIndex < slashPositions.length &&
        i == slashPositions[slashIndex] - slashIndex) {
      newBoardPart.write('/');
      slashIndex++;
    }
    newBoardPart.write(transformedOutput[i]);
  }

  // Combine the transformed board string with the rest of the original FEN string
  return '$newBoardPart$otherPart';
}

void transformSquareSquareAttributeList(TransformationType transformationType) {
  final List<SquareAttribute> newSqAttrList = List<SquareAttribute>.generate(
    sqNumber,
    (int index) => SquareAttribute(placedPieceNumber: 0),
  );

  for (int i = sqBegin; i < sqEnd; i++) {
    final int newPosition =
        transformationMap[transformationType]![i - rankNumber] + rankNumber;
    newSqAttrList[newPosition] = GameController().position.sqAttrList[i];
  }

  GameController().position.sqAttrList = newSqAttrList;
}
