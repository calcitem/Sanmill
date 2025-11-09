// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_page.dart
//
// Main puzzle solving page

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_hint_service.dart';
import '../services/puzzle_manager.dart';
import '../services/puzzle_validator.dart';

/// Page for solving a specific puzzle
class PuzzlePage extends StatefulWidget {
  const PuzzlePage({
    required this.puzzle,
    this.onSolved,
    this.onFailed,
    super.key,
  });

  final PuzzleInfo puzzle;
  final VoidCallback? onSolved;
  final VoidCallback? onFailed;

  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

class _PuzzlePageState extends State<PuzzlePage> {
  late PuzzleValidator _validator;
  late PuzzleHintService _hintService;
  final PuzzleManager _puzzleManager = PuzzleManager();
  int _moveCount = 0;
  bool _hintsUsed = false;
  int _lastRecordedMoveIndex = -1;

  @override
  void initState() {
    super.initState();
    _validator = PuzzleValidator(puzzle: widget.puzzle);
    _hintService = PuzzleHintService(puzzle: widget.puzzle);
    _initializePuzzle();
  }

  @override
  void didUpdateWidget(covariant PuzzlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.puzzle.id != widget.puzzle.id) {
      _validator = PuzzleValidator(puzzle: widget.puzzle);
      _hintService = PuzzleHintService(puzzle: widget.puzzle);
      _initializePuzzle();
    }
  }

  void _initializePuzzle() {
    // Set up the game controller with puzzle position
    final GameController controller = GameController();

    // Ensure puzzle mode is active and reset the controller state
    controller.gameInstance.gameMode = GameMode.puzzle;
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.puzzle;

    // Load the initial position from FEN
    final bool loaded = controller.position.setFen(
      widget.puzzle.initialPosition,
    );
    if (!loaded) {
      logger.e(
        '[PuzzlePage] Failed to load puzzle position: '
        '${widget.puzzle.initialPosition}',
      );
    }

    // Store the starting position for exports and history
    controller.gameRecorder.setupPosition = widget.puzzle.initialPosition;

    // Refresh UI elements that depend on game state
    controller.headerIconsNotifier.showIcons();
    controller.boardSemanticsNotifier.updateSemantics();

    // Reset state
    _moveCount = 0;
    _lastRecordedMoveIndex = -1;
    _validator.reset();
    _hintService.reset();
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return WillPopScope(
      onWillPop: () async {
        final bool? shouldPop = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(s.exitPuzzle),
            content: Text(s.puzzleProgressWillBeLost),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.exit),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.puzzle.title),
          actions: <Widget>[
            // Hint button
            if (DB().puzzleSettings.showHints && _hintService.hasHints)
              IconButton(
                icon: const Icon(Icons.lightbulb_outline),
                onPressed: _showHint,
              ),
            // Reset button
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetPuzzle,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            // Puzzle info panel
            _buildInfoPanel(s),

            // Game board - properly constructed with GameMode
            Expanded(
              child: _PuzzleGameBoard(
                puzzle: widget.puzzle,
                onMoveCompleted: _onPlayerMove,
              ),
            ),

            // Action buttons
            _buildActionButtons(s),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel(S s) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Description
          Text(
            widget.puzzle.description,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildStatChip(s.moves, _moveCount.toString(), Icons.swap_horiz),
              _buildStatChip(
                s.optimal,
                widget.puzzle.optimalMoveCount.toString(),
                Icons.star,
              ),
              _buildStatChip(
                s.difficulty,
                widget.puzzle.difficulty.getDisplayName(S.of, context),
                Icons.signal_cellular_alt,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 10)),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(S s) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _checkSolution,
              icon: const Icon(Icons.check_circle),
              label: Text(s.checkSolution),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _giveUp,
              icon: const Icon(Icons.flag),
              label: Text(s.giveUp),
            ),
          ),
        ],
      ),
    );
  }

  void _onPlayerMove() {
    // Get the latest move from the game recorder
    final GameController controller = GameController();
    final List<ExtMove> moves = controller.gameRecorder.mainlineMoves;

    if (moves.length <= _lastRecordedMoveIndex + 1) {
      return;
    }

    for (int i = _lastRecordedMoveIndex + 1; i < moves.length; i++) {
      final ExtMove latestMove = moves[i];
      _lastRecordedMoveIndex = i;

      setState(() {
        _moveCount++;
        // Add move to validator using the move's string representation
        _validator.addMove(latestMove.move);
      });
    }

    // Auto-check after processing the new moves
    _checkSolution(autoCheck: true);
  }

  void _checkSolution({bool autoCheck = false}) {
    final GameController controller = GameController();
    final ValidationFeedback feedback = _validator.validateSolution(
      controller.position,
    );

    if (feedback.result == ValidationResult.correct) {
      _onPuzzleSolved(feedback);
    } else if (!autoCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback.message ?? 'Keep trying!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onPuzzleSolved(ValidationFeedback feedback) {
    // Record completion
    _puzzleManager.completePuzzle(
      puzzleId: widget.puzzle.id,
      moveCount: _moveCount,
      difficulty: widget.puzzle.difficulty,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      hintsUsed: _hintsUsed,
    );

    // Show completion dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _buildCompletionDialog(feedback),
    );
  }

  Widget _buildCompletionDialog(ValidationFeedback feedback) {
    final S s = S.of(context);
    final int stars = PuzzleProgress.calculateStars(
      moveCount: _moveCount,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      difficulty: widget.puzzle.difficulty,
      hintsUsed: _hintsUsed,
    );

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
          const SizedBox(width: 8),
          Text(s.puzzleSolved),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(
              3,
              (int index) => Icon(
                index < stars ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          Text('${s.moves}: $_moveCount'),
          Text('${s.optimal}: ${widget.puzzle.optimalMoveCount}'),
          if (_hintsUsed) Text(s.hintsUsed),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            _resetPuzzle();
          },
          child: Text(s.tryAgain),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: Text(s.backToList),
        ),
      ],
    );
  }

  void _showHint() {
    final PuzzleHint? hint = _hintService.getNextHint(_moveCount);

    if (hint == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No more hints available')));
      return;
    }

    setState(() {
      _hintsUsed = true;
    });

    _puzzleManager.recordAttempt(widget.puzzle.id, hintUsed: true);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.lightbulb, color: Colors.amber),
            SizedBox(width: 8),
            Text('Hint'),
          ],
        ),
        content: Text(hint.content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetPuzzle() {
    setState(() {
      _initializePuzzle();
      _moveCount = 0;
      _hintsUsed = false;
    });
    GameController().headerIconsNotifier.showIcons();
  }

  void _giveUp() {
    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(s.giveUp),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.solution),
            const SizedBox(height: 8),
            Text(
              widget.puzzle.solutionMoves.first.join(' → '),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _puzzleManager.recordAttempt(
                widget.puzzle.id,
                hintUsed: _hintsUsed,
              );
              Navigator.of(context).pop();
            },
            child: Text(s.backToList),
          ),
        ],
      ),
    );
  }
}

/// Wrapper widget for GamePage that monitors move completion
class _PuzzleGameBoard extends StatefulWidget {
  const _PuzzleGameBoard({required this.puzzle, required this.onMoveCompleted});

  final PuzzleInfo puzzle;
  final VoidCallback onMoveCompleted;

  @override
  State<_PuzzleGameBoard> createState() => _PuzzleGameBoardState();
}

class _PuzzleGameBoardState extends State<_PuzzleGameBoard> {
  late final GameController _controller;
  int _lastMoveCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
    _lastMoveCount = _controller.gameRecorder.mainlineMoves.length;

    // Listen for game state updates to detect when moves are made
    _controller.headerIconsNotifier.addListener(_onControllerUpdated);
  }

  @override
  void didUpdateWidget(covariant _PuzzleGameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastMoveCount = _controller.gameRecorder.mainlineMoves.length;
  }

  @override
  void dispose() {
    _controller.headerIconsNotifier.removeListener(_onControllerUpdated);
    super.dispose();
  }

  void _onControllerUpdated() {
    final int currentMoveCount = _controller.gameRecorder.mainlineMoves.length;

    if (currentMoveCount < _lastMoveCount) {
      _lastMoveCount = currentMoveCount;
      return;
    }

    if (currentMoveCount > _lastMoveCount) {
      _lastMoveCount = currentMoveCount;
      widget.onMoveCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use GamePage with puzzle mode
    return GamePage(GameMode.puzzle, key: const Key('puzzle_game'));
  }
}
