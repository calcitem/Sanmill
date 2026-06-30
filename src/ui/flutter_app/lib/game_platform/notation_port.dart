// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Converts game-specific moves and positions to portable text formats.
///
/// Each module owns its notation grammar and file text. Shared import/export
/// code should call this port rather than assuming PGN or Mill move syntax.
abstract class NotationPort {
  String encodeMoveList(Iterable<GameAction> actions);
  List<GameAction> decodeMoveList(String notation);
  String describeMove(GameAction action);
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions);
}
