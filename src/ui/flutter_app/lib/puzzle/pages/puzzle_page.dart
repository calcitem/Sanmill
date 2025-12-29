// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_page.dart
//
// Main puzzle solving page

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_auto_player.dart';
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
  final ValueNotifier<int> _moveCountNotifier = ValueNotifier<int>(0);
  bool _hintsUsed = false;
  int _lastRecordedMoveIndex = -1;
  ThemeData? _settingsThemeForDialogs;
  PieceColor? _puzzleHumanColor;
  bool _isSolved = false;
  bool _isAutoPlayingOpponent = false;

  // Store original game state to restore on exit
  GameMode? _previousGameMode;
  PieceColor? _previousPuzzleHumanColor;
  bool _previousIsPuzzleAutoMoveInProgress = false;

  bool get _canUndo => _moveCountNotifier.value > 0;

  @override
  void initState() {
    super.initState();
    _validator = PuzzleValidator(puzzle: widget.puzzle);
    _hintService = PuzzleHintService(puzzle: widget.puzzle);
    
    // Save current game state before entering puzzle mode
    final GameController controller = GameController();
    _previousGameMode = controller.gameInstance.gameMode;
    _previousPuzzleHumanColor = controller.puzzleHumanColor;
    _previousIsPuzzleAutoMoveInProgress = controller.isPuzzleAutoMoveInProgress;
    
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

  @override
  void dispose() {
    // Restore previous game state when leaving puzzle mode
    final GameController controller = GameController();
    
    // Only restore if we're still in puzzle mode (not already changed by another page)
    if (controller.gameInstance.gameMode == GameMode.puzzle) {
      controller.gameInstance.gameMode = _previousGameMode ?? GameMode.humanVsAi;
      controller.puzzleHumanColor = _previousPuzzleHumanColor;
      controller.isPuzzleAutoMoveInProgress = _previousIsPuzzleAutoMoveInProgress;
      
      logger.i('[PuzzlePage] Restored game mode to ${_previousGameMode}');
    }
    
    _moveCountNotifier.dispose();
    super.dispose();
  }

  void _initializePuzzle() {
    // Set up the game controller with puzzle position
    final GameController controller = GameController();

    // Ensure puzzle mode is active and reset the controller state
    controller.gameInstance.gameMode = GameMode.puzzle;
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.puzzle;

    // Validate FEN format before loading
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(widget.puzzle.initialPosition)) {
      logger.e(
        '[PuzzlePage] Invalid FEN format: ${widget.puzzle.initialPosition}',
      );
      _showFenErrorDialog();
      return;
    }

    // Load the initial position from FEN
    final bool loaded = controller.position.setFen(
      widget.puzzle.initialPosition,
    );
    if (!loaded) {
      logger.e(
        '[PuzzlePage] Failed to load puzzle position: '
        '${widget.puzzle.initialPosition}',
      );
      _showFenErrorDialog();
      return;
    }

    // Puzzle mode: the human plays the side-to-move from the initial position.
    _puzzleHumanColor = controller.position.sideToMove;
    controller.puzzleHumanColor = _puzzleHumanColor;
    controller.isPuzzleAutoMoveInProgress = false;
    // Re-apply puzzle mode so whoIsAI can reflect the resolved human side.
    controller.gameInstance.gameMode = GameMode.puzzle;
    _isSolved = false;
    _isAutoPlayingOpponent = false;

    // Store the starting position for exports and history
    controller.gameRecorder.setupPosition = widget.puzzle.initialPosition;

    // Refresh UI elements that depend on game state
    controller.headerIconsNotifier.showIcons();
    controller.boardSemanticsNotifier.updateSemantics();

    // Reset state
    _moveCountNotifier.value = 0;
    _lastRecordedMoveIndex = -1;
    _validator.reset();
    _hintService.reset();
  }

  /// Show error dialog when FEN validation fails
  void _showFenErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return Theme(
            data: _settingsThemeForDialogs ?? Theme.of(dialogContext),
            child: AlertDialog(
              title: const Row(
                children: <Widget>[
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Invalid Puzzle'),
                ],
              ),
              content: const Text(
                'This puzzle has an invalid position format and cannot be loaded. '
                'Please contact the puzzle author or try a different puzzle.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Back to List'),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);
        _settingsThemeForDialogs = settingsTheme;

        // Use Builder to ensure the context has the correct theme.
        // This prevents computing text styles from a context outside the Theme wrapper.
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (bool didPop, Object? result) async {
                  if (didPop) {
                    return;
                  }
                  final bool? shouldPop = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return Theme(
                        data: settingsTheme,
                        child: AlertDialog(
                          title: Text(s.exitPuzzle),
                          content: Text(s.puzzleProgressWillBeLost),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: Text(s.cancel),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(s.exit),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                  // Check if user confirmed exit and widget is still mounted
                  if (shouldPop ?? false) {
                    if (!mounted) {
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: Scaffold(
                  backgroundColor: useDarkSettingsUi
                      ? settingsTheme.scaffoldBackgroundColor
                      : AppTheme.lightBackgroundColor,
                  appBar: AppBar(
                    title: Text(
                      widget.puzzle.title,
                      style: useDarkSettingsUi
                          ? null
                          : AppTheme.appBarTheme.titleTextStyle,
                    ),
                    actions: <Widget>[
                      // Undo button
                      IconButton(
                        icon: const Icon(Icons.undo),
                        onPressed: _canUndo ? _undoMove : null,
                        tooltip: s.undo,
                      ),
                      // Hint button
                      if (DB().puzzleSettings.showHints &&
                          _hintService.hasHints)
                        IconButton(
                          icon: const Icon(Icons.lightbulb_outline),
                          onPressed: _showHint,
                          tooltip: s.hint,
                        ),
                      // Reset button
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _resetPuzzle,
                        tooltip: s.reset,
                      ),
                    ],
                  ),
                  body: Column(
                    children: <Widget>[
                      // Puzzle info panel - only rebuilds when move count changes
                      ValueListenableBuilder<int>(
                        valueListenable: _moveCountNotifier,
                        builder:
                            (
                              BuildContext context,
                              int moveCount,
                              Widget? child,
                            ) {
                              return _buildInfoPanel(
                                context,
                                s,
                                moveCount,
                                useDarkSettingsUi,
                              );
                            },
                      ),

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
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoPanel(
    BuildContext context,
    S s,
    int moveCount,
    bool useDarkSettingsUi,
  ) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: useDarkSettingsUi
          ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.primaryContainer.withValues(
              alpha: 0.1,
            ), // Use theme color
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Description
          Text(
            widget.puzzle.description,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Flexible(
                child: _buildStatChip(
                  s.moves,
                  moveCount.toString(),
                  Icons.swap_horiz,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: _buildStatChip(
                  s.optimal,
                  widget.puzzle.optimalMoveCount.toString(),
                  Icons.star,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: _buildStatChip(
                  s.difficulty,
                  widget.puzzle.difficulty.getDisplayName(S.of, context),
                  Icons.signal_cellular_alt,
                ),
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
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(S s) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: <Widget>[
          // Give up button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _giveUp,
              icon: const Icon(Icons.flag),
              label: Text(
                s.giveUp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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

      // Update move count without rebuilding entire widget tree
      _moveCountNotifier.value++;
      // Add move to validator using the move's string representation
      _validator.addMove(latestMove.move);
    }

    // Auto-check after processing the new moves
    final ValidationFeedback feedback = _checkSolution(autoCheck: true);
    if (feedback.result != ValidationResult.correct) {
      _maybeAutoPlayOpponentResponse();
    }
  }

  ValidationFeedback _checkSolution({bool autoCheck = false}) {
    final GameController controller = GameController();
    final ValidationFeedback feedback = _validator.validateSolution(
      controller.position,
    );

    if (feedback.result == ValidationResult.correct) {
      _onPuzzleSolved(feedback);
      return feedback;
    } else if (feedback.result == ValidationResult.wrong) {
      // Wrong solution - show error message
      if (!autoCheck && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(feedback.message ?? 'Wrong approach. Try again!'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (!autoCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback.message ?? 'Keep trying!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return feedback;
  }

  void _maybeAutoPlayOpponentResponse() {
    if (!mounted || _isSolved || _isAutoPlayingOpponent) {
      return;
    }

    final GameController controller = GameController();
    if (controller.gameInstance.gameMode != GameMode.puzzle) {
      return;
    }

    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;
    if (humanColor == null) {
      return;
    }

    if (controller.position.phase == Phase.gameOver) {
      return;
    }

    // Only auto-play when it's the opponent's turn.
    if (controller.position.sideToMove == humanColor) {
      return;
    }

    _isAutoPlayingOpponent = true;
    controller.isPuzzleAutoMoveInProgress = true;

    // Convert solutions to legacy format for auto-player
    final List<List<String>> legacySolutions = widget.puzzle.solutions
        .map((PuzzleSolution s) =>
            s.moves.map((PuzzleMove m) => m.notation).toList())
        .toList();

    Future<void>.delayed(Duration.zero, () async {
      try {
        await PuzzleAutoPlayer.autoPlayOpponentResponses(
          solutions: legacySolutions,
          humanColor: humanColor,
          isGameOver: () =>
              !mounted || controller.position.phase == Phase.gameOver,
          sideToMove: () => controller.position.sideToMove,
          movesSoFar: () => controller.gameRecorder.mainlineMoves
              .map((ExtMove m) => m.move)
              .toList(growable: false),
          applyMove: (String move) {
            final bool ok = controller.applyMove(
              ExtMove(move, side: controller.position.sideToMove),
            );
            if (!ok) {
              logger.e('[PuzzlePage] Failed to auto-play move: $move');
            }
            return ok;
          },
          onWrongMove: () async {
            // No solution matches the current line. Undo the last move to prevent
            // a deadlock (human input is restricted to one side in puzzle mode).
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Wrong move. Try again.'),
                duration: Duration(seconds: 2),
              ),
            );
            await _undoMove(allowDuringAutoPlay: true);
          },
        );
      } finally {
        controller.isPuzzleAutoMoveInProgress = false;
        _isAutoPlayingOpponent = false;
        controller.headerIconsNotifier.showIcons();
        controller.boardSemanticsNotifier.updateSemantics();
      }
    });
  }

  void _onPuzzleSolved(ValidationFeedback feedback) {
    _isSolved = true;
    // Record completion
    _puzzleManager.completePuzzle(
      puzzleId: widget.puzzle.id,
      moveCount: _moveCountNotifier.value,
      difficulty: widget.puzzle.difficulty,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      hintsUsed: _hintsUsed,
    );

    // Show completion dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final ThemeData theme =
            _settingsThemeForDialogs ?? Theme.of(dialogContext);
        return Theme(
          data: theme,
          child: Builder(
            builder: (BuildContext context) {
              return _buildCompletionDialog(context, feedback);
            },
          ),
        );
      },
    );
  }

  Widget _buildCompletionDialog(
    BuildContext context,
    ValidationFeedback feedback,
  ) {
    final S s = S.of(context);
    final int stars = PuzzleProgress.calculateStars(
      moveCount: _moveCountNotifier.value,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      difficulty: widget.puzzle.difficulty,
      hintsUsed: _hintsUsed,
    );

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(
            Icons.emoji_events,
            color: Theme.of(context).colorScheme.primary, // Use primary green
            size: 32,
          ),
          const SizedBox(width: 8),
          // Wrap text in Expanded to prevent overflow on small screens
          Expanded(
            child: Text(s.puzzleSolved, overflow: TextOverflow.ellipsis),
          ),
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
                color: Colors.amber, // Keep amber for stars
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          Text('${s.moves}: ${_moveCountNotifier.value}'),
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
            _loadNextPuzzle();
          },
          child: Text(s.next),
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

  void _loadNextPuzzle() {
    // Get a random unsolved puzzle from the same category or difficulty
    final List<PuzzleInfo> allPuzzles = _puzzleManager.getAllPuzzles();
    final PuzzleSettings settings = _puzzleManager.settingsNotifier.value;

    // Filter for unsolved puzzles, preferring same category or difficulty
    final List<PuzzleInfo> candidates = allPuzzles.where((PuzzleInfo p) {
      final PuzzleProgress? progress = settings.getProgress(p.id);
      return progress == null || !progress.completed;
    }).toList();

    if (candidates.isEmpty) {
      // All puzzles solved! Show message and go back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).allPuzzlesCompleted)),
      );
      Navigator.of(context).pop();
      return;
    }

    // Prefer puzzles from same category
    final List<PuzzleInfo> sameCategoryPuzzles = candidates
        .where(
          (PuzzleInfo p) =>
              p.category == widget.puzzle.category && p.id != widget.puzzle.id,
        )
        .toList();

    PuzzleInfo nextPuzzle;
    if (sameCategoryPuzzles.isNotEmpty) {
      nextPuzzle = sameCategoryPuzzles.first;
    } else {
      nextPuzzle = candidates.first;
    }

    // Replace current page with new puzzle
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PuzzlePage(puzzle: nextPuzzle),
      ),
    );
  }

  void _showHint() {
    final PuzzleHint? hint = _hintService.getNextHint(_moveCountNotifier.value);

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
      builder: (BuildContext dialogContext) {
        final ThemeData theme =
            _settingsThemeForDialogs ?? Theme.of(dialogContext);
        return Theme(
          data: theme,
          child: Builder(
            builder: (BuildContext context) {
              return AlertDialog(
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
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _undoMove({bool allowDuringAutoPlay = false}) async {
    final GameController controller = GameController();
    if (controller.gameRecorder.mainlineMoves.isEmpty) {
      return;
    }

    if (!allowDuringAutoPlay &&
        (_isAutoPlayingOpponent || controller.isPuzzleAutoMoveInProgress)) {
      return;
    }

    // In puzzle mode, a single user decision is typically followed by an
    // auto-played opponent response. Undo should bring the user back to a
    // position where it's the human side to move again, otherwise input would
    // be locked to prevent playing for the opponent.
    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;
    final int maxSteps = controller.gameRecorder.mainlineMoves.length;
    int undone = 0;

    while (controller.gameRecorder.mainlineMoves.isNotEmpty &&
        undone < maxSteps) {
      await HistoryNavigator.takeBack(context, pop: false);
      undone++;

      // Update state without rebuilding entire widget tree
      if (_moveCountNotifier.value > 0) {
        _moveCountNotifier.value--;
      }
      _lastRecordedMoveIndex--;
      _validator.undoLastMove();

      if (humanColor == null || controller.position.sideToMove == humanColor) {
        break;
      }
    }
  }

  void _resetPuzzle() {
    _initializePuzzle(); // This already resets _moveCountNotifier.value = 0
    setState(() {
      _hintsUsed = false;
    });
    _isSolved = false;
    _isAutoPlayingOpponent = false;
    GameController().headerIconsNotifier.showIcons();
  }

  void _giveUp() {
    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme =
            _settingsThemeForDialogs ?? Theme.of(dialogContext);
        return Theme(
          data: theme,
          child: Builder(
            builder: (BuildContext context) {
              return AlertDialog(
                title: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary, // Use primary color
                    ),
                    const SizedBox(width: 8),
                    // Wrap text in Expanded to prevent overflow on small screens
                    Expanded(
                      child: Text(s.solution, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Optimal solution (${widget.puzzle.solutions.first.moves.length} moves):',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      // Show solution as numbered list
                      ...widget.puzzle.solutions.first.moves.asMap().entries.map((
                        MapEntry<int, PuzzleMove> entry,
                      ) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(
                                        alpha: 0.2,
                                      ), // Use primary color
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                entry.value.notation,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
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
              );
            },
          ),
        );
      },
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

    // Listen to the proper business logic notifier for move changes
    _controller.gameRecorder.moveCountNotifier.addListener(_onMoveCountChanged);
  }

  @override
  void didUpdateWidget(covariant _PuzzleGameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastMoveCount = _controller.gameRecorder.mainlineMoves.length;
  }

  @override
  void dispose() {
    _controller.gameRecorder.moveCountNotifier
        .removeListener(_onMoveCountChanged);
    super.dispose();
  }

  void _onMoveCountChanged() {
    final int currentMoveCount = _controller.gameRecorder.mainlineMoves.length;

    // Ignore if move count decreased (undo operation)
    if (currentMoveCount < _lastMoveCount) {
      _lastMoveCount = currentMoveCount;
      return;
    }

    // New move(s) added - notify parent
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
