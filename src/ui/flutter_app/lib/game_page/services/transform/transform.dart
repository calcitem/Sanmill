// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// transform.dart
//
// Board symmetry transformation engine.
//
// Provides all 16 symmetry transformations of the Nine Men's Morris board
// (the dihedral group D4 combined with inner/outer ring swap = D4 × Z2).
// These transformations can be applied to:
//   - Board position strings (24-character strings)
//   - FEN strings
//   - Move notations (place, move, remove)
//   - Square attribute lists (for live game state)
//
// The 16 transformations match the C++ engine's perfect_symmetries.cpp.

import 'dart:math';

import '../mill.dart';

/// All 16 symmetry transformations of the Nine Men's Morris board.
///
/// The board has D4 symmetry (8 elements: 4 rotations × 2 reflections).
/// Combined with the inner-outer ring swap, this yields 16 total symmetries.
///
/// Naming follows the C++ engine's perfect_symmetries.cpp for consistency.
enum TransformationType {
  // --- Pure spatial transformations (no ring swap) ---
  identity,
  rotate90,
  rotate180,
  rotate270,
  mirrorVertical,
  mirrorHorizontal,
  mirrorBackslash,
  mirrorSlash,

  // --- Ring swap combined with spatial transformations ---
  swap,
  swapRotate90,
  swapRotate180,
  swapRotate270,
  swapMirrorVertical,
  swapMirrorHorizontal,
  swapMirrorBackslash,
  swapMirrorSlash,
}

// ---------------------------------------------------------------------------
// Transformation mapping tables
// ---------------------------------------------------------------------------

/// Mapping tables for all 16 symmetry transformations.
///
/// Each list has 24 entries (indices 0–23) representing the board positions
/// across three concentric rings:
///   - Inner ring : indices 0–7   (squares 8–15)
///   - Middle ring: indices 8–15  (squares 16–23)
///   - Outer ring : indices 16–23 (squares 24–31)
///
/// Semantics: `map[i] = j` means the piece at old position `i` moves to
/// new position `j` after the transformation.
///
/// All mappings are derived from the C++ engine (perfect_symmetries_slow.cpp)
/// and verified by composition identities.
final Map<TransformationType, List<int>> transformationMap =
    <TransformationType, List<int>>{
      TransformationType.identity: <int>[
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
      ],
      TransformationType.rotate90: <int>[
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
      TransformationType.rotate180: <int>[
        4,
        5,
        6,
        7,
        0,
        1,
        2,
        3,
        12,
        13,
        14,
        15,
        8,
        9,
        10,
        11,
        20,
        21,
        22,
        23,
        16,
        17,
        18,
        19,
      ],
      TransformationType.rotate270: <int>[
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
        21,
      ],
      TransformationType.mirrorVertical: <int>[
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
        21,
      ],
      TransformationType.mirrorHorizontal: <int>[
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
        17,
      ],
      TransformationType.mirrorBackslash: <int>[
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
        19,
      ],
      TransformationType.mirrorSlash: <int>[
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
        23,
      ],
      TransformationType.swap: <int>[
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
      TransformationType.swapRotate90: <int>[
        18,
        19,
        20,
        21,
        22,
        23,
        16,
        17,
        10,
        11,
        12,
        13,
        14,
        15,
        8,
        9,
        2,
        3,
        4,
        5,
        6,
        7,
        0,
        1,
      ],
      TransformationType.swapRotate180: <int>[
        20,
        21,
        22,
        23,
        16,
        17,
        18,
        19,
        12,
        13,
        14,
        15,
        8,
        9,
        10,
        11,
        4,
        5,
        6,
        7,
        0,
        1,
        2,
        3,
      ],
      TransformationType.swapRotate270: <int>[
        22,
        23,
        16,
        17,
        18,
        19,
        20,
        21,
        14,
        15,
        8,
        9,
        10,
        11,
        12,
        13,
        6,
        7,
        0,
        1,
        2,
        3,
        4,
        5,
      ],
      TransformationType.swapMirrorVertical: <int>[
        20,
        19,
        18,
        17,
        16,
        23,
        22,
        21,
        12,
        11,
        10,
        9,
        8,
        15,
        14,
        13,
        4,
        3,
        2,
        1,
        0,
        7,
        6,
        5,
      ],
      TransformationType.swapMirrorHorizontal: <int>[
        16,
        23,
        22,
        21,
        20,
        19,
        18,
        17,
        8,
        15,
        14,
        13,
        12,
        11,
        10,
        9,
        0,
        7,
        6,
        5,
        4,
        3,
        2,
        1,
      ],
      TransformationType.swapMirrorBackslash: <int>[
        18,
        17,
        16,
        23,
        22,
        21,
        20,
        19,
        10,
        9,
        8,
        15,
        14,
        13,
        12,
        11,
        2,
        1,
        0,
        7,
        6,
        5,
        4,
        3,
      ],
      TransformationType.swapMirrorSlash: <int>[
        22,
        21,
        20,
        19,
        18,
        17,
        16,
        23,
        14,
        13,
        12,
        11,
        10,
        9,
        8,
        15,
        6,
        5,
        4,
        3,
        2,
        1,
        0,
        7,
      ],
    };

// ---------------------------------------------------------------------------
// Square notation ↔ transform index mapping
// ---------------------------------------------------------------------------

/// Maps board square notation (e.g. "d5") to the 0-based transform index.
///
/// The transform index is `squareNumber - 8` where squareNumber comes from
/// the engine's internal numbering (8–31).
const Map<String, int> _notationToTransformIndex = <String, int>{
  // Inner ring (indices 0–7)
  'd5': 0, 'e5': 1, 'e4': 2, 'e3': 3,
  'd3': 4, 'c3': 5, 'c4': 6, 'c5': 7,
  // Middle ring (indices 8–15)
  'd6': 8, 'f6': 9, 'f4': 10, 'f2': 11,
  'd2': 12, 'b2': 13, 'b4': 14, 'b6': 15,
  // Outer ring (indices 16–23)
  'd7': 16, 'g7': 17, 'g4': 18, 'g1': 19,
  'd1': 20, 'a1': 21, 'a4': 22, 'a7': 23,
};

/// Maps 0-based transform index back to board square notation.
const List<String> _transformIndexToNotation = <String>[
  // Inner ring (indices 0–7)
  'd5', 'e5', 'e4', 'e3', 'd3', 'c3', 'c4', 'c5',
  // Middle ring (indices 8–15)
  'd6', 'f6', 'f4', 'f2', 'd2', 'b2', 'b4', 'b6',
  // Outer ring (indices 16–23)
  'd7', 'g7', 'g4', 'g1', 'd1', 'a1', 'a4', 'a7',
];

// ---------------------------------------------------------------------------
// Composition and inverse utilities
// ---------------------------------------------------------------------------

/// Returns the mapping array for the given transformation type.
List<int> getTransformMap(TransformationType type) {
  return transformationMap[type]!;
}

/// Composes two transformation mappings: applies [first], then [second].
///
/// Given `first[i] = j` and `second[j] = k`, the composed mapping
/// sends `i → k`, i.e. `result[i] = second[first[i]]`.
List<int> composeTransformMaps(List<int> first, List<int> second) {
  assert(first.length == 24);
  assert(second.length == 24);
  return List<int>.generate(24, (int i) => second[first[i]]);
}

/// Computes the inverse of a transformation mapping.
///
/// If `map[i] = j`, then `inverse[j] = i`.
List<int> inverseTransformMap(List<int> map) {
  assert(map.length == 24);
  final List<int> inverse = List<int>.filled(24, 0);
  for (int i = 0; i < 24; i++) {
    inverse[map[i]] = i;
  }
  return inverse;
}

/// Returns a random [TransformationType].
///
/// If [excludeIdentity] is true (the default), the identity transformation
/// is excluded from the pool so a visible change always occurs.
TransformationType randomTransformationType({bool excludeIdentity = true}) {
  final List<TransformationType> pool = excludeIdentity
      ? TransformationType.values
            .where((TransformationType t) => t != TransformationType.identity)
            .toList()
      : TransformationType.values.toList();
  return pool[Random().nextInt(pool.length)];
}

// ---------------------------------------------------------------------------
// Board position string transformation
// ---------------------------------------------------------------------------

/// Validates that the board string has exactly 24 characters.
void _validateInput(String s) {
  assert(s.length == 24, 'Input string must be exactly 24 characters long.');
}

/// Applies a transformation mapping to a 24-character board string.
///
/// Each character at old position `i` is placed at new position `map[i]`.
String _transformString(String s, List<int> map) {
  _validateInput(s);
  final List<String> result = List<String>.filled(24, '');
  for (int i = 0; i < 24; i++) {
    result[map[i]] = s[i];
  }
  return result.join();
}

/// Transforms a 24-character board string using the given transformation type.
String transformString(String s, TransformationType type) {
  return _transformString(s, getTransformMap(type));
}

// ---------------------------------------------------------------------------
// FEN string transformation
// ---------------------------------------------------------------------------

/// Transforms a FEN string using the given transformation type.
///
/// The first 26 characters (including `/` separators between rings) encode
/// the board.  This function strips the separators, transforms the 24-char
/// board string, re-inserts the separators, and appends the remainder.
String transformFEN(String fen, TransformationType type) {
  // Extract the first 26 characters, which include the board description.
  final String boardPart = fen.substring(0, 26);
  // The remainder contains side-to-move, counts, etc.
  final String otherPart = fen.substring(26);

  // Record the positions of each '/' separator.
  final List<int> slashPositions = <int>[];
  for (int i = 0; i < boardPart.length; i++) {
    if (boardPart[i] == '/') {
      slashPositions.add(i);
    }
  }

  // Remove all '/' characters and transform the pure board string.
  final String boardOnly = boardPart.replaceAll('/', '');
  final String transformed = transformString(boardOnly, type);

  // Re-insert '/' at the original positions.
  final StringBuffer result = StringBuffer();
  int slashIdx = 0;
  for (int i = 0; i < transformed.length; i++) {
    if (slashIdx < slashPositions.length &&
        i == slashPositions[slashIdx] - slashIdx) {
      result.write('/');
      slashIdx++;
    }
    result.write(transformed[i]);
  }

  return '$result$otherPart';
}

// ---------------------------------------------------------------------------
// Move notation transformation
// ---------------------------------------------------------------------------

/// Transforms a single square notation (e.g. "d5") using a mapping array.
///
/// Returns the transformed notation, or the original if the notation is
/// not recognized (e.g. "draw", "(none)").
String _transformSquareNotation(String notation, List<int> map) {
  final String lower = notation.toLowerCase();
  final int? index = _notationToTransformIndex[lower];
  if (index == null) {
    return notation; // Unrecognized notation; return unchanged.
  }
  return _transformIndexToNotation[map[index]];
}

/// Transforms a move notation string using the given transformation type.
///
/// Supported formats:
///   - Place:  `"d5"`     → transforms the target square
///   - Move:   `"d5-e4"`  → transforms both from and to squares
///   - Remove: `"xd5"`    → transforms the target square (preserves `x` prefix)
///   - Special: `"draw"`, `"(none)"`, `"none"` → returned unchanged
String transformMoveNotation(String move, TransformationType type) {
  return transformMoveNotationWithMap(move, getTransformMap(type));
}

/// Transforms a move notation string using an explicit mapping array.
///
/// This is the lower-level API that allows custom composed mappings.
String transformMoveNotationWithMap(String move, List<int> map) {
  final String trimmed = move.trim();

  // Handle special / non-board moves.
  if (trimmed == 'draw' || trimmed == '(none)' || trimmed == 'none') {
    return trimmed;
  }

  // Remove move: "xd5" → transform "d5", re-prepend "x".
  if (trimmed.startsWith('x') && trimmed.length == 3) {
    final String target = trimmed.substring(1);
    return 'x${_transformSquareNotation(target, map)}';
  }

  // Slide/move: "d5-e4" → transform both halves.
  if (trimmed.contains('-') && trimmed.length == 5) {
    final List<String> parts = trimmed.split('-');
    if (parts.length == 2) {
      final String from = _transformSquareNotation(parts[0], map);
      final String to = _transformSquareNotation(parts[1], map);
      return '$from-$to';
    }
  }

  // Place move: "d5" → transform single square.
  if (trimmed.length == 2 && RegExp(r'^[a-g][1-7]$').hasMatch(trimmed)) {
    return _transformSquareNotation(trimmed, map);
  }

  // Unrecognized format; return unchanged.
  return trimmed;
}

// ---------------------------------------------------------------------------
// Game state transformation (coupled to GameController)
// ---------------------------------------------------------------------------

/// Transforms the live game's square attribute list in place.
///
/// This function is specific to the setup-position feature and operates
/// directly on [GameController]'s position state.
void transformSquareSquareAttributeList(TransformationType type) {
  final List<SquareAttribute> newSqAttrList = List<SquareAttribute>.generate(
    sqNumber,
    (int index) => SquareAttribute(placedPieceNumber: 0),
  );

  final List<int> map = getTransformMap(type);

  for (int i = sqBegin; i < sqEnd; i++) {
    final int newPosition = map[i - rankNumber] + rankNumber;
    newSqAttrList[newPosition] = GameController().position.sqAttrList[i];
  }

  GameController().position.sqAttrList = newSqAttrList;
}
