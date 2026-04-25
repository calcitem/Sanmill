// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Backward-compatible session handle name used by existing modules.
///
/// New code should implement [GameSession] directly. Keeping this alias lets the
/// current Mill and probe modules migrate without a large mechanical change.
abstract class GameSessionHandle implements GameSession {}
