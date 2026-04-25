// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Converts game-specific moves and positions to portable text formats.
abstract class NotationPort {
  String encodeMoveList(Iterable<GameAction> actions);
  List<GameAction> decodeMoveList(String notation);
  String describeMove(GameAction action);
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions);
}
