// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Opaque per-session object; Mill maps this to [GameController] in later
/// refactors. The probe can hold minimal state.
abstract class GameSessionHandle {
  void dispose();
}
