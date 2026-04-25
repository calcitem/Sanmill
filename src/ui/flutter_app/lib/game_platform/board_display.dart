// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'game_session.dart';

enum BoardHighlightKind { selected, legalTarget, lastMove, warning }

@immutable
class BoardPieceView {
  const BoardPieceView({
    required this.coordinate,
    required this.owner,
    this.pieceType,
    this.payload = const <String, Object?>{},
  });

  final BoardCoordinate coordinate;
  final PlayerSeat owner;
  final String? pieceType;
  final Map<String, Object?> payload;
}

@immutable
class BoardHighlight {
  const BoardHighlight({
    required this.coordinate,
    required this.kind,
    this.payload = const <String, Object?>{},
  });

  final BoardCoordinate coordinate;
  final BoardHighlightKind kind;
  final Map<String, Object?> payload;
}

/// Optional rendering projection derived from an engine-backed game snapshot.
///
/// Game modules own painting and animation. This model gives shared widgets and
/// tests a common way to inspect occupancy and interaction hints without
/// duplicating game rules in Dart.
@immutable
class BoardDisplaySnapshot {
  const BoardDisplaySnapshot({
    required this.gameState,
    this.pieces = const <BoardPieceView>[],
    this.highlights = const <BoardHighlight>[],
    this.payload = const <String, Object?>{},
  });

  final GameStateSnapshot gameState;
  final List<BoardPieceView> pieces;
  final List<BoardHighlight> highlights;
  final Map<String, Object?> payload;
}
