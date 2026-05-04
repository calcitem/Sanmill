// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_types.dart
//
// Stable public Mill vocabulary that does NOT depend on the legacy
// `Position` / `Game` rule machine.  Owned outside the `mill.dart`
// part-of family so the enums and helpers survive the upcoming
// deletion of `engine/position.dart` and friends.
//
// `mill.dart` re-exports every symbol from this file, so existing
// consumers that import the legacy `mill.dart` keep working without
// any change.  Consumers that only need these enums (without the
// rest of the legacy library) should `import` this file directly.

import 'package:flutter/material.dart' show Color;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int abs(int value) => value > 0 ? value : -value;

Color getAverageColor(Color a, Color b) {
  return Color.fromARGB(
    (a.a + b.a) ~/ 2,
    (a.a + b.r) ~/ 2,
    (a.a + b.g) ~/ 2,
    (a.a + b.b) ~/ 2,
  );
}

Color getTranslucentColor(Color c, double opacity) {
  return c.withValues(alpha: opacity);
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Logical owner of a board node.
///
/// `none` means an empty square; `marked` is a delayed-removal placeholder
/// used by certain Mill variants; `nobody` and `draw` are sentinel values
/// for terminal states.
enum PieceColor { none, white, black, marked, nobody, draw }

/// Whether the AI move comes from the engine's traditional search or from
/// the ensemble (consensus) path.
enum AiMoveType { unknown, traditional, consensus }

/// Mill game phases.
enum Phase { ready, placing, moving, gameOver }

/// Action expected from the active side at any given moment.
enum Act { select, place, remove }

/// Move type for an individual recorded ply.
enum MoveType { place, move, remove, draw, none }
