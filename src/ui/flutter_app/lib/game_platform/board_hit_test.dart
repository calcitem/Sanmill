// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:ui';

import 'game_session.dart';

/// Converts pointer positions into game coordinates.
abstract class BoardHitTest {
  BoardCoordinate? coordinateFor(Offset localPosition, Size boardSize);
}
