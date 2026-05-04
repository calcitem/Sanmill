// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_score.dart
//
// In-memory tally of game outcomes for the current Mill app session.
// Bumped by the game-result notifier when a game ends (or a fresh
// New Game is started) and read by the info dialog and the
// import-PGN parser to surface a "x-y-z" score string.
//
// Lives outside the legacy `Position` class (where the static map
// previously hid) so it survives the rule-machine deletion.

import 'mill_types.dart';

/// Cumulative win / draw / loss tally for the current process.
///
/// Keys are restricted to [PieceColor.white], [PieceColor.black] and
/// [PieceColor.draw].  Resetting the app does not persist this map;
/// it is intentional in-memory only.
final Map<PieceColor, int> millScore = <PieceColor, int>{
  PieceColor.white: 0,
  PieceColor.black: 0,
  PieceColor.draw: 0,
};

/// Convenience accessor that mirrors the legacy
/// `Position.scoreString` getter (`"<white> - <draw> - <black>"`).
String get millScoreString =>
    "${millScore[PieceColor.white]} - "
    "${millScore[PieceColor.draw]} - "
    "${millScore[PieceColor.black]}";

/// Resets the cumulative tally back to zero.
void resetMillScore() {
  millScore[PieceColor.white] = 0;
  millScore[PieceColor.black] = 0;
  millScore[PieceColor.draw] = 0;
}
