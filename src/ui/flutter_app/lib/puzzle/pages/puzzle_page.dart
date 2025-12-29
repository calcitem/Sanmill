// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_page.dart
//
// Main puzzle solving page

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../game_page/services/import_export/pgn.dart';
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
  bool _solutionViewed = false;
  int _lastRecordedMoveIndex = -1;
  ThemeData? _settingsThemeForDialogs;
  PieceColor? _puzzleHumanColor;
  bool _isSolved = false;
  bool _isAutoPlayingOpponent = false;
  bool _isPlayingSolution = false;

  // Store original game state to restore on exit
  GameMode? _previousGameMode;
  PieceColor? _previousPuzzleHumanColor;
  bool _previousIsPuzzleAutoMoveInProgress = false;

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
      controller.gameInstance.gameMode =
          _previousGameMode ?? GameMode.humanVsAi;
      controller.puzzleHumanColor = _previousPuzzleHumanColor;
      controller.isPuzzleAutoMoveInProgress =
          _previousIsPuzzleAutoMoveInProgress;

      logger.i('[PuzzlePage] Restored game mode to $_previousGameMode');
    }

    _moveCountNotifier.dispose();
    super.dispose();
  }

  void _initializePuzzle() {
    // Check rule variant compatibility first
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    if (widget.puzzle.ruleVariantId != currentVariant.id) {
      // Show warning dialog after build is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRuleMismatchWarning(currentVariant);
      });
    }

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
              title: Row(
                children: <Widget>[
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(S.of(dialogContext).puzzleInvalidPuzzle),
                ],
              ),
              content: Text(S.of(dialogContext).puzzleInvalidPuzzleMessage),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(S.of(dialogContext).puzzleBackToList),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  /// Show warning dialog when puzzle rules don't match current settings
  void _showRuleMismatchWarning(RuleVariant currentVariant) {
    if (!mounted) {
      return;
    }

    // Get friendly rule names instead of IDs
    final RuleVariant puzzleVariant = _getVariantById(
      widget.puzzle.ruleVariantId,
    );
    final String puzzleRuleName = puzzleVariant.name;
    final String currentRuleName = currentVariant.name;

    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: _settingsThemeForDialogs ?? Theme.of(dialogContext),
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                Text(s.puzzleRuleMismatch),
              ],
            ),
            content: Text(
              s.puzzleRuleMismatchWarning(puzzleRuleName, currentRuleName),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: Text(s.puzzleRuleMismatchContinue),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Get rule variant by ID, fallback to creating from puzzle's ID
  RuleVariant _getVariantById(String variantId) {
    // Try to get predefined variant
    final RuleVariant? predefined = PredefinedVariants.getById(variantId);
    if (predefined != null) {
      return predefined;
    }

    // Fallback: create a basic variant with the ID as name
    return RuleVariant(
      id: variantId,
      name: variantId
          .replaceAll('_', ' ')
          .split(' ')
          .map((String word) {
            return word.isEmpty
                ? ''
                : word[0].toUpperCase() + word.substring(1);
          })
          .join(' '),
      description: 'Custom variant: $variantId',
      ruleHash: '',
    );
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
                      ValueListenableBuilder<int>(
                        valueListenable: _moveCountNotifier,
                        builder:
                            (
                              BuildContext context,
                              int moveCount,
                              Widget? child,
                            ) {
                              final bool canUndo =
                                  moveCount > 0 && !_isPlayingSolution;

                              return IconButton(
                                icon: const Icon(Icons.undo),
                                onPressed: canUndo ? _undoMove : null,
                                tooltip: s.undo,
                              );
                            },
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
          // Show solution playback indicator
          if (_isPlayingSolution)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.puzzlePlayingSolution,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
          const SizedBox(height: 8),

          // Attempt counter - show current session attempts
          ValueListenableBuilder<PuzzleSettings>(
            valueListenable: _puzzleManager.settingsNotifier,
            builder:
                (BuildContext context, PuzzleSettings settings, Widget? child) {
                  final PuzzleProgress? progress = settings.getProgress(
                    widget.puzzle.id,
                  );
                  final int attempts = progress?.attempts ?? 0;

                  if (attempts > 0) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.replay,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.puzzleAttempts(attempts),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
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
                style: const TextStyle(fontSize: 11), // Increased from 10 to 11
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
      // Wrong solution - show error message with option to view solution
      if (!autoCheck && mounted) {
        _showWrongMoveDialog();
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

  /// Show dialog when user makes a wrong move
  void _showWrongMoveDialog() {
    final S s = S.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: _settingsThemeForDialogs ?? Theme.of(dialogContext),
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                const Icon(Icons.error_outline, color: Colors.red, size: 28),
                const SizedBox(width: 8),
                Expanded(child: Text(s.puzzleWrongMove)),
              ],
            ),
            content: Text(s.puzzleWrongMoveMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(s.tryAgain),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showSolution();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                ),
                child: Text(s.puzzleShowSolution),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Play the optimal solution automatically
  Future<void> _showSolution() async {
    if (_isPlayingSolution || _isSolved) {
      return;
    }

    final PuzzleSolution? solution = widget.puzzle.optimalSolution;
    if (solution == null || solution.moves.isEmpty) {
      logger.w('[PuzzlePage] No solution available to show');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).puzzleNoSolutionAvailable),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isPlayingSolution = true;
      _solutionViewed = true;
    });

    // Mark solution as viewed in progress
    final PuzzleSettings settings = _puzzleManager.settingsNotifier.value;
    final PuzzleProgress? currentProgress = settings.getProgress(
      widget.puzzle.id,
    );
    if (currentProgress != null) {
      final PuzzleProgress updatedProgress = currentProgress.copyWith(
        solutionViewed: true,
      );
      _puzzleManager.updateProgress(updatedProgress);
    }

    // Reset to initial position
    _resetPuzzle();

    // Show info message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzlePlayingSolution),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    }

    // Wait a moment before starting playback
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Play each move with delay
    final GameController controller = GameController();
    for (final PuzzleMove move in solution.moves) {
      if (!mounted || !_isPlayingSolution) {
        break;
      }

      // Try to make the move
      final bool success = controller.applyMove(
        ExtMove(move.notation, side: controller.position.sideToMove),
      );
      if (!success) {
        logger.e('[PuzzlePage] Failed to play solution move: ${move.notation}');
        break;
      }

      // Wait before next move
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    if (mounted) {
      setState(() {
        _isPlayingSolution = false;
      });

      // Show completion message after solution playback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleSolutionComplete),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
        .map(
          (PuzzleSolution s) =>
              s.moves.map((PuzzleMove m) => m.notation).toList(),
        )
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
              SnackBar(
                content: Text(S.of(context).puzzleWrongMove),
                duration: const Duration(seconds: 2),
              ),
            );
            await _undoMove(allowDuringAutoPlay: true);

            // Clear auto-play flags immediately after undo so subsequent moves can
            // trigger auto-play again. Otherwise, the finally block would only run
            // after autoPlayOpponentResponses completes (which is too late).
            controller.isPuzzleAutoMoveInProgress = false;
            _isAutoPlayingOpponent = false;
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
    // Record completion with solution viewed status
    _puzzleManager.completePuzzle(
      puzzleId: widget.puzzle.id,
      moveCount: _moveCountNotifier.value,
      difficulty: widget.puzzle.difficulty,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      hintsUsed: _hintsUsed,
      solutionViewed: _solutionViewed,
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
      solutionViewed: _solutionViewed,
    );

    final String? completionMessage = widget.puzzle
        .getLocalizedCompletionMessage(context);

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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Center(
              child: Column(
                children: <Widget>[
                  Text('${s.moves}: ${_moveCountNotifier.value}'),
                  Text('${s.optimal}: ${widget.puzzle.optimalMoveCount}'),
                  if (_hintsUsed) Text(s.hintsUsed),
                  if (_solutionViewed)
                    Text(
                      s.puzzleSolutionViewedNote,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

            // Completion message from puzzle author
            if (completionMessage != null &&
                completionMessage.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.lightbulb_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      completionMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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
      ).showSnackBar(SnackBar(content: Text(S.of(context).puzzleNoMoreHints)));
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
                title: Row(
                  children: <Widget>[
                    const Icon(Icons.lightbulb, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text(S.of(context).puzzleHintDialogTitle),
                  ],
                ),
                content: Text(hint.content),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(S.of(context).ok),
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

      // In Puzzle mode, we need to delete the move node from the PGN tree (not just
      // move the pointer). Otherwise, mainlineMoves will still include the old node,
      // causing the next appendMove to create a branch instead of extending the
      // mainline.
      final PgnNode<ExtMove>? currentNode = controller.gameRecorder.activeNode;
      if (currentNode != null && currentNode.children.isNotEmpty) {
        currentNode.children.clear();
        // Sync the moveCountNotifier with the new mainline length after clearing children.
        controller.gameRecorder.moveCountNotifier.value =
            controller.gameRecorder.mainlineMoves.length;
      }

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
    // Record retry attempt if puzzle was already started
    if (_moveCountNotifier.value > 0 && !_isSolved) {
      _puzzleManager.recordAttempt(widget.puzzle.id, hintUsed: _hintsUsed);
    }

    _initializePuzzle(); // This already resets _moveCountNotifier.value = 0
    setState(() {
      _hintsUsed = false;
      _solutionViewed = false;
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
                      // Show all solutions with expansion tiles
                      ...widget.puzzle.solutions.asMap().entries.map((
                        MapEntry<int, PuzzleSolution> solutionEntry,
                      ) {
                        final int solutionIndex = solutionEntry.key;
                        final PuzzleSolution solution = solutionEntry.value;
                        final bool isOnlySolution =
                            widget.puzzle.solutions.length == 1;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: isOnlySolution
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '${solution.isOptimal ? s.puzzleOptimalSolution : s.puzzleAlternativeSolution} (${solution.moves.length} moves):',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ..._buildSolutionMoves(solution, context),
                                  ],
                                )
                              : ExpansionTile(
                                  title: Row(
                                    children: <Widget>[
                                      Text(
                                        '${s.puzzleSolutionTab(solutionIndex + 1)} ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        solution.isOptimal
                                            ? s.puzzleOptimalSolution
                                            : s.puzzleAlternativeSolution,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: solution.isOptimal
                                              ? Colors.amber[300]
                                              : Colors.grey[400],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '(${solution.moves.length} moves)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                  initiallyExpanded: solutionIndex == 0,
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: _buildSolutionMoves(
                                          solution,
                                          context,
                                        ),
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
  ValueNotifier<int>? _boundMoveCountNotifier;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
    _bindMoveCountNotifier();
  }

  @override
  void didUpdateWidget(covariant _PuzzleGameBoard oldWidget) {
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

/// Helper method to build solution moves list
List<Widget> _buildSolutionMoves(
  PuzzleSolution solution,
  BuildContext context,
) {
  return solution.moves.asMap().entries.map((MapEntry<int, PuzzleMove> entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
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
          Expanded(
            child: Text(
              entry.value.notation,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          // Show side indicator (subtle)
          Text(
            entry.value.side == PieceColor.white ? '⚪' : '⚫',
            style: const TextStyle(fontSize: 12), // Increased from 10 to 12
          ),
        ],
      ),
    );
  }).toList();
}
