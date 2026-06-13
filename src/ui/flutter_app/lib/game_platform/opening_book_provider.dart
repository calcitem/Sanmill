// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Game-neutral hook for consulting a static opening book before search.
abstract class OpeningBookProvider {
  /// Returns a legal action for the current position, or null when the book
  /// has no entry (caller falls back to engine search).
  GameAction? lookup(GameSession session);
}
