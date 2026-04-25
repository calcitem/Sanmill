// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'game_session.dart';

/// Export-ready snapshot + action list for a [GameModule].
///
/// The shared shell is responsible for locating the active [GameSession];
/// each module decides what action history to expose for export.
@immutable
class GameExportData {
  const GameExportData({required this.snapshot, required this.actions});

  final GameStateSnapshot snapshot;
  final List<GameAction> actions;
}
