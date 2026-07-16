// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'game_id.dart';
import 'game_menu.dart';

/// Optional play surface supplied by an application entry point.
///
/// Keeping this contract in the game platform layer lets distribution-specific
/// entry points omit an entire feature module from their Dart import graph.
abstract interface class PlayModeContribution {
  GameId get gameId;

  GameModeEntry buildEntry(BuildContext context);
}
