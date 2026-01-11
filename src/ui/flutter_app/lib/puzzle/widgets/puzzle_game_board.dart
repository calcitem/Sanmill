// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../models/puzzle_models.dart';

/// Wrapper widget for GamePage that monitors move completion
class PuzzleGameBoard extends StatefulWidget {
  const PuzzleGameBoard({
    required this.puzzle,
    required this.onMoveCompleted,
    super.key,
  });

  final PuzzleInfo puzzle;
  final VoidCallback onMoveCompleted;

  @override
  State<PuzzleGameBoard> createState() => _PuzzleGameBoardState();
}

class _PuzzleGameBoardState extends State<PuzzleGameBoard> {
  late final GameController _controller;
  ValueNotifier<int>? _boundMoveCountNotifier;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
    _bindMoveCountNotifier();
  }

  @override
  void didUpdateWidget(covariant PuzzleGameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindMoveCountNotifier();
  }

  @override
  void dispose() {
    // Detach from the last bound notifier to avoid leaking listeners.
    _boundMoveCountNotifier?.removeListener(_onMoveCountChanged);
    super.dispose();
  }

  /// Ensures we listen to the current [GameRecorder.moveCountNotifier].
  ///
  /// NOTE: `GameController.reset()` creates a new `GameRecorder`, so the notifier
  /// instance can change across "retry" / "reset" flows. If we don't rebind,
  /// the puzzle page won't receive move completion callbacks anymore.
  void _bindMoveCountNotifier() {
    final ValueNotifier<int> current =
        _controller.gameRecorder.moveCountNotifier;
    if (identical(_boundMoveCountNotifier, current)) {
      return;
    }

    _boundMoveCountNotifier?.removeListener(_onMoveCountChanged);
    _boundMoveCountNotifier = current;

    current.addListener(_onMoveCountChanged);
  }

  void _onMoveCountChanged() {
    // Notify parent on any move history change.
    //
    // IMPORTANT: After taking back moves, adding a new move can shorten the
    // PGN mainline (branching replaces the remainder). We still want to notify
    // the parent so it can process the new move and trigger auto-play.
    widget.onMoveCompleted();
  }

  @override
  Widget build(BuildContext context) {
    // Make sure we stay bound even if the recorder changes without a parent rebuild.
    _bindMoveCountNotifier();

    // Use GamePage with puzzle mode
    return GamePage(GameMode.puzzle, key: const Key('puzzle_game'));
  }
}
