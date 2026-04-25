// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_id.dart';

/// Legacy Mill [Hive] typeIds are already allocated in model files (roughly
/// 0–13 and 30–38). New games must use unallocated high ranges; do not
/// reshuffle existing ids.
///
/// Box name pattern: `app.<scope>` for cross-game data, `game.<id>.<scope>`
/// for per-game data (future migration).
String? scopePrefixFor(GameId? id) {
  if (id == null) {
    return null;
  }
  return 'game.${id.value}.';
}
