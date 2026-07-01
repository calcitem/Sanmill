// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Stable action type strings for Mill exports and session interactions.
///
/// These strings are consumed by [MillGameSession], [MillNotationPort], and
/// [MillGameModule.buildExportData]. Using constants avoids scattered bare
/// string literals and reduces future migration cost when legalActions are
/// fully enumerated.
abstract final class MillActionTypes {
  /// The active player must place a new piece on the board.
  static const String place = 'mill.place';

  /// The active player must move (slide) an existing piece.
  static const String move = 'mill.move';

  /// The active player must remove an opponent's piece after forming a mill.
  static const String remove = 'mill.remove';

  /// The active player must select a piece to move (two-step move semantics).
  static const String select = 'mill.select';
}

/// Event type strings emitted by [MillGameSession] via [GameSessionEvent.type].
///
/// Centralising these strings lets [MillGameSession] and any future
/// listeners share a single authoritative source rather than scattered
/// bare literals.
abstract final class MillEventTypes {
  static const String stateChanged = 'millStateChanged';
  static const String moveApplied = 'millMoveApplied';
  static const String moveRejected = 'millMoveRejected';
  static const String undoApplied = 'millUndoApplied';
  static const String redoApplied = 'millRedoApplied';
  static const String actionIgnored = 'millActionIgnored';
}

/// Phase name constants used in [GameStateSnapshot.phase] for Mill sessions.
///
/// [legacy] is reserved for compatibility snapshots emitted by deprecated
/// controller-backed paths.
abstract final class MillPhases {
  static const String legacy = 'legacy';
}
