// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_page.dart
//
// Main puzzle solving page

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/services/mill.dart';
import '../../game_page/services/transform/transform.dart';
import '../../generated/intl/l10n.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_auto_player.dart';
import '../services/puzzle_hint_service.dart';
import '../services/puzzle_manager.dart';
import '../services/puzzle_rating_service.dart';
import '../services/puzzle_transform_service.dart';
import '../services/puzzle_validator.dart';
import '../widgets/puzzle_game_board.dart';
import '../widgets/puzzle_solution_view.dart';

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
  final PuzzleRatingService _ratingService = PuzzleRatingService();
  final ValueNotifier<int> _moveCountNotifier = ValueNotifier<int>(0);
  bool _hintsUsed = false;
  bool _solutionViewed = false;
  int _lastRecordedMoveIndex = -1;
  ThemeData? _settingsThemeForDialogs;
  PieceColor? _puzzleHumanColor;
  bool _isSolved = false;
  bool _isAutoPlayingOpponent = false;
  bool _isPlayingSolution = false;
  DateTime _attemptStartedAt = DateTime.now();

  // Board symmetry transformation state.
  // A random transformation is applied when the puzzle loads to prevent
  // memorization and increase replayability.  The player can also cycle
  // through transformations manually via the AppBar button.
  TransformationType _currentTransform = TransformationType.identity;
  late PuzzleInfo _transformedPuzzle;

  // Store original game state to restore on exit
  GameMode? _previousGameMode;
  PieceColor? _previousPuzzleHumanColor;
  bool _previousIsPuzzleAutoMoveInProgress = false;

  // Store original rule settings so they can be restored when the user
  // leaves puzzle mode.  Null when the rules were not switched.
  RuleSettings? _originalRuleSettings;

  @override
  void initState() {
    super.initState();

    // Apply a random board symmetry transformation to prevent memorization.
    _currentTransform = randomTransformationType(excludeIdentity: false);
    _transformedPuzzle = PuzzleTransformService.transformPuzzle(
      widget.puzzle,
      _currentTransform,
    );

    _validator = PuzzleValidator(puzzle: _transformedPuzzle);
    _hintService = PuzzleHintService(puzzle: _transformedPuzzle);

    // Save current game state before entering puzzle mode
    final GameController controller = GameController();
    _previousGameMode = controller.gameInstance.gameMode;
    _previousPuzzleHumanColor = controller.puzzleHumanColor;
    _previousIsPuzzleAutoMoveInProgress = controller.isPuzzleAutoMoveInProgress;

    // Snapshot the user's rule settings once.  All rule-switching during
    // this puzzle session will be undone against this snapshot.
    _originalRuleSettings = DB().ruleSettings;

    _initializePuzzle();
  }

  @override
  void didUpdateWidget(covariant PuzzlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.puzzle.id != widget.puzzle.id) {
      // New puzzle — pick a fresh random transformation.
      _currentTransform = randomTransformationType(excludeIdentity: false);
      _transformedPuzzle = PuzzleTransformService.transformPuzzle(
        widget.puzzle,
        _currentTransform,
      );
      _validator = PuzzleValidator(puzzle: _transformedPuzzle);
      _hintService = PuzzleHintService(puzzle: _transformedPuzzle);
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

    // Restore the user's original rule settings if they were overridden for
    // this puzzle.  The DB setter automatically schedules an engine update
    // via its debounce timer, so the engine will pick up the restored rules
    // shortly after the page is popped.
    if (_originalRuleSettings != null) {
      DB().ruleSettings = _originalRuleSettings!;
      logger.i('[PuzzlePage] Restored original rule settings');
    }

    _moveCountNotifier.dispose();
    super.dispose();
  }

  /// Ensure the engine is configured with the rules required by this puzzle.
  ///
  /// Resolution order:
  /// 1. If the current active rules already match the puzzle — do nothing.
  /// 2. Look up [RuleVariant.canonicalSettings] by the puzzle's variant ID.
  /// 3. Deserialize the embedded [PuzzleInfo.ruleSettingsJson] snapshot
  ///    (covers user-customised rule sets that are not among the 13 named
  ///    variants).
  /// 4. If none of the above succeeds, show a mismatch warning.
  void _applyPuzzleRulesIfNeeded() {
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    final String puzzleVariantId = widget.puzzle.ruleVariantId;

    // Rules already match — nothing to do.
    if (puzzleVariantId == currentVariant.id) {
      return;
    }

    // 1) Try canonical lookup for the 13 named variants.
    RuleSettings? puzzleSettings =
        RuleVariant.canonicalSettings[puzzleVariantId];

    // 2) Fallback: try the embedded rule-settings snapshot.
    if (puzzleSettings == null && widget.puzzle.ruleSettingsJson != null) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(widget.puzzle.ruleSettingsJson!) as Map<String, dynamic>;
        puzzleSettings = RuleSettings.fromJson(json);
      } catch (e) {
        logger.e(
          '[PuzzlePage] Failed to deserialize ruleSettingsJson '
          'for puzzle "${widget.puzzle.id}": $e',
        );
      }
    }

    if (puzzleSettings != null) {
      // Apply the resolved settings so the engine validates moves correctly.
      DB().ruleSettings = puzzleSettings;

      // Force an immediate engine update after the current frame so that
      // move-legality checks use the new rules from the start.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GameController().engine.setRuleOptions();
      });

      logger.i(
        '[PuzzlePage] Auto-switched rules to "$puzzleVariantId" '
        'for puzzle "${widget.puzzle.id}"',
      );
    } else {
      // No canonical entry and no snapshot — warn the user.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRuleMismatchWarning(currentVariant);
      });
    }
  }

  void _initializePuzzle() {
    // Ensure the engine uses the correct rules for this puzzle.
    _applyPuzzleRulesIfNeeded();

    // Set up the game controller with the *transformed* puzzle position.
    final GameController controller = GameController();

    // Ensure puzzle mode is active and reset the controller state
    controller.gameInstance.gameMode = GameMode.puzzle;
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.puzzle;

    // Validate FEN format before loading
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(_transformedPuzzle.initialPosition)) {
      logger.e(
        '[PuzzlePage] Invalid FEN format: '
        '${_transformedPuzzle.initialPosition}',
      );
      _showFenErrorDialog();
      return;
    }

    // Load the transformed initial position from FEN
    final bool loaded = controller.position.setFen(
      _transformedPuzzle.initialPosition,
    );
    if (!loaded) {
      logger.e(
        '[PuzzlePage] Failed to load puzzle position: '
        '${_transformedPuzzle.initialPosition}',
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
    controller.gameRecorder.setupPosition = _transformedPuzzle.initialPosition;

    // Refresh UI elements that depend on game state
    controller.headerIconsNotifier.showIcons();
    controller.boardSemanticsNotifier.updateSemantics();

    // Reset state
    _moveCountNotifier.value = 0;
    _lastRecordedMoveIndex = -1;
    _validator.reset();
    _hintService.reset();
    _attemptStartedAt = DateTime.now();
  }

  /// Applies a new board symmetry transformation to the puzzle.
  ///
  /// Recomputes the transformed puzzle from the original [widget.puzzle],
  /// recreates the validator and hint service with the new data, and
  /// re-initializes the game board.
  void _applyTransformation(TransformationType type) {
    _currentTransform = type;
    _transformedPuzzle = PuzzleTransformService.transformPuzzle(
      widget.puzzle,
      _currentTransform,
    );
    _validator = PuzzleValidator(puzzle: _transformedPuzzle);
    _hintService = PuzzleHintService(puzzle: _transformedPuzzle);

    _initializePuzzle();
    setState(() {
      _hintsUsed = false;
      _solutionViewed = false;
    });
    _isSolved = false;
    _isAutoPlayingOpponent = false;
    GameController().headerIconsNotifier.showIcons();
  }

  /// Cycles to the next transformation type and re-initializes the puzzle.
  void _cycleTransformation() {
    if (_isPlayingSolution) {
      return;
    }

    const List<TransformationType> allTypes = TransformationType.values;
    final int currentIndex = allTypes.indexOf(_currentTransform);
    final int nextIndex = (currentIndex + 1) % allTypes.length;

    _applyTransformation(allTypes[nextIndex]);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).transformed),
          duration: const Duration(seconds: 1),
        ),
      );
    }
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
                      // Transform button — cycle through board symmetries
                      IconButton(
                        icon: const Icon(Icons.rotate_right),
                        onPressed: _isPlayingSolution
                            ? null
                            : _cycleTransformation,
                        tooltip: s.rotate,
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
                        child: PuzzleGameBoard(
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

    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;

    for (int i = _lastRecordedMoveIndex + 1; i < moves.length; i++) {
      final ExtMove latestMove = moves[i];
      _lastRecordedMoveIndex = i;

      // Add move to validator using the move's string representation
      _validator.addMove(latestMove.move);

      // Count only *player* moves so it aligns with optimalMoveCount and hint index.
      if (humanColor == null || latestMove.side == humanColor) {
        _moveCountNotifier.value++;
      }
    }

    // During solution playback we only want to update internal counters;
    // avoid triggering validation dialogs / completion flows.
    if (_isPlayingSolution) {
      return;
    }

    // Auto-check after processing the new moves
    final ValidationFeedback feedback = _checkSolution(autoCheck: true);
    if (feedback.result != ValidationResult.correct) {
      _maybeAutoPlayOpponentResponse();
    }
  }

  ValidationFeedback _checkSolution({bool autoCheck = false}) {
    final S s = S.of(context);
    final GameController controller = GameController();
    final ValidationFeedback feedback = _validator.validateSolution(
      controller.position,
    );

    if (feedback.result == ValidationResult.correct) {
      _onPuzzleSolved(feedback);
      return feedback;
    } else if (feedback.result == ValidationResult.wrong) {
      // Wrong solution - notify parent and show error message
      widget.onFailed?.call();
      if (!autoCheck && mounted) {
        _showWrongMoveDialog();
      }
    } else if (!autoCheck) {
      final String message = feedback.result == ValidationResult.inProgress
          ? s.keepGoingObjectiveNotAchieved
          : s.keepTrying;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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

    // Use the transformed puzzle's solution so moves match the board.
    final PuzzleSolution? solution = _transformedPuzzle.optimalSolution;
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

    // Persist solutionViewed BEFORE resetting so the flag survives the reset.
    // Always create progress if none exists; otherwise a fresh puzzle would
    // lose the solutionViewed flag and the user could earn full stars after
    // viewing the solution.
    final PuzzleSettings settings = _puzzleManager.settingsNotifier.value;
    final PuzzleProgress currentProgress =
        settings.getProgress(widget.puzzle.id) ??
        PuzzleProgress(puzzleId: widget.puzzle.id);
    _puzzleManager.updateProgress(
      currentProgress.copyWith(solutionViewed: true),
    );

    // Reset to initial position first so the board is ready for playback.
    // _resetPuzzle() clears local flags (_solutionViewed, _hintsUsed), so we
    // must set _solutionViewed = true AFTER the reset to keep it consistent.
    _resetPuzzle();

    setState(() {
      _isPlayingSolution = true;
      _solutionViewed = true;
    });

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

    // Convert transformed solutions to legacy format for auto-player.
    // The transformed notations match the current board orientation.
    final List<List<String>> legacySolutions = _transformedPuzzle.solutions
        .map(
          (PuzzleSolution s) =>
              s.moves.map((PuzzleMove m) => m.notation).toList(),
        )
        .toList();

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
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
    final DateTime now = DateTime.now();
    final Duration timeSpent = now.difference(_attemptStartedAt);
    final int hintsUsed = _hintService.hintsGiven;
    final int movesPlayed = _moveCountNotifier.value;
    final int oldRating = DB().puzzleSettings.userRating;

    // Check persisted solutionViewed status to prevent star inflation.
    // The local _solutionViewed flag can be reset by _resetPuzzle(), so we
    // must also consult the persisted progress to detect prior solution views.
    final PuzzleProgress? priorProgress = _puzzleManager.getProgress(
      widget.puzzle.id,
    );
    final bool effectiveSolutionViewed =
        _solutionViewed || (priorProgress?.solutionViewed ?? false);

    // Record completion with solution viewed status.
    // Use _hintsUsed (current session only) instead of merging with
    // priorProgress.hintsUsed so that a clean retry can earn full stars.
    _puzzleManager.completePuzzle(
      puzzleId: widget.puzzle.id,
      moveCount: _moveCountNotifier.value,
      difficulty: widget.puzzle.difficulty,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      hintsUsed: _hintsUsed,
      solutionViewed: effectiveSolutionViewed,
    );

    final int newRating = DB().puzzleSettings.userRating;
    final int ratingChange = newRating - oldRating;
    _ratingService.saveAttemptResult(
      PuzzleAttemptResult(
        puzzleId: widget.puzzle.id,
        success: true,
        timeSpent: timeSpent,
        hintsUsed: hintsUsed,
        movesPlayed: movesPlayed,
        timestamp: now,
        oldRating: ratingChange == 0 ? null : oldRating,
        newRating: ratingChange == 0 ? null : newRating,
        ratingChange: ratingChange == 0 ? null : ratingChange,
      ),
    );

    // Notify parent (e.g. PuzzleRush / PuzzleStreak) that the puzzle was solved.
    widget.onSolved?.call();

    // In Rush/Streak mode the parent has already advanced to the next puzzle
    // via setState, so showing a completion dialog here would target a stale
    // widget tree and cause timing conflicts.
    if (widget.onSolved != null) {
      return;
    }

    // Show completion dialog (standalone puzzle mode only)
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

    // Use persisted progress to compute stars consistently with completePuzzle().
    final PuzzleProgress? priorProgress = _puzzleManager.getProgress(
      widget.puzzle.id,
    );
    final bool effectiveSolutionViewed =
        _solutionViewed || (priorProgress?.solutionViewed ?? false);

    final int stars = PuzzleProgress.calculateStars(
      moveCount: _moveCountNotifier.value,
      optimalMoveCount: widget.puzzle.optimalMoveCount,
      difficulty: widget.puzzle.difficulty,
      hintsUsed: _hintsUsed,
      solutionViewed: effectiveSolutionViewed,
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
    // Pick a random unsolved puzzle, preferring the same category.
    final List<PuzzleInfo> allPuzzles = _puzzleManager.getAllPuzzles();
    final PuzzleSettings settings = _puzzleManager.settingsNotifier.value;
    final Random rng = Random();

    // Filter for unsolved puzzles (excluding the current one).
    final List<PuzzleInfo> candidates = allPuzzles.where((PuzzleInfo p) {
      if (p.id == widget.puzzle.id) {
        return false;
      }
      final PuzzleProgress? progress = settings.getProgress(p.id);
      return progress == null || !progress.completed;
    }).toList();

    if (candidates.isEmpty) {
      // All puzzles solved! Show message and go back.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).allPuzzlesCompleted)),
      );
      Navigator.of(context).pop();
      return;
    }

    // Prefer puzzles from the same category; fall back to any unsolved puzzle.
    final List<PuzzleInfo> sameCategoryPuzzles = candidates
        .where((PuzzleInfo p) => p.category == widget.puzzle.category)
        .toList();

    final List<PuzzleInfo> pool = sameCategoryPuzzles.isNotEmpty
        ? sameCategoryPuzzles
        : candidates;
    final PuzzleInfo nextPuzzle = pool[rng.nextInt(pool.length)];

    // Replace current page with new puzzle.
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

    _puzzleManager.recordHintUsed(widget.puzzle.id);

    final S s = S.of(context);
    final String content = switch (hint.type) {
      HintType.textual => hint.content,
      HintType.nextMove => s.nextMoveHint(hint.content),
      HintType.showSolution => s.completeSolutionHint(hint.content),
      HintType.highlight => hint.content,
    };

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
                content: Text(content),
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
      final ExtMove lastMove = controller.gameRecorder.mainlineMoves.last;
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

      // Update state without rebuilding entire widget tree.
      // Only decrement when we undo a *player* move.
      if (humanColor == null || lastMove.side == humanColor) {
        if (_moveCountNotifier.value > 0) {
          _moveCountNotifier.value--;
        }
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
      _puzzleManager.recordAttempt(widget.puzzle.id);
      _ratingService.saveAttemptResult(
        PuzzleAttemptResult(
          puzzleId: widget.puzzle.id,
          success: false,
          timeSpent: DateTime.now().difference(_attemptStartedAt),
          hintsUsed: _hintService.hintsGiven,
          movesPlayed: _moveCountNotifier.value,
          timestamp: DateTime.now(),
        ),
      );
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

    // The dialog reveals the full solution, so mark solutionViewed immediately.
    // Even if the user cancels and returns to the puzzle, they have already
    // seen the answer and should not earn full stars on a subsequent solve.
    _solutionViewed = true;
    final PuzzleProgress currentProgress =
        _puzzleManager.getProgress(widget.puzzle.id) ??
        PuzzleProgress(puzzleId: widget.puzzle.id);
    _puzzleManager.updateProgress(
      currentProgress.copyWith(solutionViewed: true),
    );

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
                      // Show transformed solutions matching current board.
                      ..._transformedPuzzle.solutions.asMap().entries.map((
                        MapEntry<int, PuzzleSolution> solutionEntry,
                      ) {
                        final int solutionIndex = solutionEntry.key;
                        final PuzzleSolution solution = solutionEntry.value;
                        final bool isOnlySolution =
                            _transformedPuzzle.solutions.length == 1;

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
                                    ...buildSolutionMoves(solution, context),
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
                                        children: buildSolutionMoves(
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
                      _puzzleManager.recordAttempt(widget.puzzle.id);
                      if (_moveCountNotifier.value > 0 || _hintsUsed) {
                        _ratingService.saveAttemptResult(
                          PuzzleAttemptResult(
                            puzzleId: widget.puzzle.id,
                            success: false,
                            timeSpent: DateTime.now().difference(
                              _attemptStartedAt,
                            ),
                            hintsUsed: _hintService.hintsGiven,
                            movesPlayed: _moveCountNotifier.value,
                            timestamp: DateTime.now(),
                          ),
                        );
                      }
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
