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
/// an optional advisory source.
enum AiMoveType {
  unknown,
  traditional,
  perfect,
  consensus,
  openingBook,
  humanDatabase,
}

/// Statistics for the HumanDB candidate that supplied the latest AI move.
class HumanDatabaseMoveStats {
  const HumanDatabaseMoveStats({
    required this.notation,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.total,
    required this.scoreDelta,
  });

  final String notation;
  final int wins;
  final int losses;
  final int draws;
  final int total;
  final double scoreDelta;

  double get winPercent => _percent(wins);

  double get lossPercent => _percent(losses);

  double get drawPercent => _percent(draws);

  double _percent(int count) {
    assert(total >= 0, 'Human DB sample count must not be negative.');
    if (total == 0) {
      return 0;
    }
    return count * 100.0 / total;
  }
}

/// Mill game phases.
enum Phase { ready, placing, moving, gameOver }

/// Action expected from the active side at any given moment.
enum Act { select, place, remove }

/// Move type for an individual recorded ply.
enum MoveType { place, move, remove, draw, none }
