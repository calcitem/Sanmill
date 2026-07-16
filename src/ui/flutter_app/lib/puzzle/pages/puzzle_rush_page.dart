// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import 'puzzle_streak_page.dart';

/// Compatibility entry for builds or saved routes that still open Puzzle Rush.
///
/// Timed puzzle play is intentionally retired. Existing callers now receive
/// the untimed, mistake-ended continuous challenge instead.
class PuzzleRushPage extends StatelessWidget {
  const PuzzleRushPage({super.key});

  @override
  Widget build(BuildContext context) => const PuzzleStreakPage();
}
