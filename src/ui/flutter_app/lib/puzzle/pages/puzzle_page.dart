// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_page.dart
//
// Main puzzle solving page

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/services/mill.dart';
import '../../game_page/services/transform/transform.dart';
import '../../game_page/widgets/board_transform_picker_dialog.dart';
import '../../game_platform/game_session.dart';
import '../../games/mill/mill_board_transform_actions.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../generated/intl/l10n.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/widgets/lichess_action_sheet.dart';
import '../../shared/widgets/lichess_bottom_bar.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_auto_player.dart';
import '../services/puzzle_hint_service.dart';
import '../services/puzzle_manager.dart';
import '../services/puzzle_rating_service.dart';
import '../services/puzzle_rule_engine.dart';
import '../services/puzzle_selection_service.dart';
import '../services/puzzle_transform_service.dart';
import '../services/puzzle_validator.dart';
import '../widgets/puzzle_completion_confetti.dart';
import '../widgets/puzzle_game_board.dart';
import '../widgets/puzzle_solution_view.dart';

enum _PuzzleSolutionAction { stay, nextPuzzle, backToList }

enum _PuzzleCompletionAction { tryAgain, nextPuzzle, backToList }

enum _PuzzleAppBarAction { continueOrSkip }

enum _PuzzleBoardFeedback { yourTurn, notBestMove }

/// Page for solving a specific puzzle
class PuzzlePage extends StatefulWidget {
  const PuzzlePage({
    required this.puzzle,
    this.onSolved,
    this.onFailed,
    this.showSolvedDialogAfterCallback = false,
    super.key,
  });

  final PuzzleInfo puzzle;
  final VoidCallback? onSolved;
  final VoidCallback? onFailed;

  /// Whether a callback-driven puzzle should also show the normal result UI.
  ///
  /// Continuous challenge modes advance immediately and keep the default
  /// false. Daily puzzles record completion through [onSolved] but opt into
  /// the regular completion dialog.
  final bool showSolvedDialogAfterCallback;

  /// Test-only override for the random board symmetry transformation.
  ///
  /// Production always randomizes the transformation to prevent memorization.
  /// Widget tests that assert on specific move notations need a deterministic
  /// orientation; setting this forces every [PuzzlePage] instance to use the
  /// given transformation instead of a random one. Always reset it back to
  /// null in test teardown so it cannot leak across cases.
  @visibleForTesting
  static TransformationType? debugTransformationOverride;

  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

class _PuzzlePageState extends State<PuzzlePage> {
  late PuzzleValidator _validator;
  late PuzzleHintService _hintService;
  final PuzzleManager _puzzleManager = PuzzleManager();
  final PuzzleRatingService _ratingService = PuzzleRatingService();
  final ValueNotifier<int> _moveCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _annotationModeNotifier = ValueNotifier<bool>(
    false,
  );
  OverlayEntry? _confettiOverlayEntry;
  Timer? _confettiTimer;
  bool _hintsUsed = false;
  bool _solutionViewed = false;
  int _lastRecordedMoveIndex = -1;
  ThemeData? _settingsThemeForDialogs;
  PieceColor? _puzzleHumanColor;
  bool _isSolved = false;
  bool _isAutoPlayingOpponent = false;
  bool _isPlayingSolution = false;
  bool _isNavigatingHistory = false;
  bool _slowerWinFeedbackShown = false;
  _PuzzleBoardFeedback _boardFeedback = _PuzzleBoardFeedback.yourTurn;
  PgnNode<ExtMove>? _latestPuzzleNode;
  DateTime _attemptStartedAt = DateTime.now();

  // A random board symmetry is applied when the puzzle loads to prevent
  // memorization. Manual transformations are relative to the current board
  // and preserve the active attempt.
  late PuzzleInfo _activePuzzle;
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

    _activePuzzle = widget.puzzle;

    // Apply a random board symmetry transformation to prevent memorization.
    final TransformationType initialTransform =
        PuzzlePage.debugTransformationOverride ??
        randomTransformationType(excludeIdentity: false);
    _transformedPuzzle = PuzzleTransformService.transformPuzzle(
      _activePuzzle,
      initialTransform,
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

    _scheduleInitializePuzzle();
  }

  @override
  void didUpdateWidget(covariant PuzzlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.puzzle.id != widget.puzzle.id) {
      _removeSuccessConfetti();
      _annotationModeNotifier.value = false;
      _activePuzzle = widget.puzzle;
      // New puzzle — pick a fresh random transformation.
      final TransformationType initialTransform =
          PuzzlePage.debugTransformationOverride ??
          randomTransformationType(excludeIdentity: false);
      _transformedPuzzle = PuzzleTransformService.transformPuzzle(
        _activePuzzle,
        initialTransform,
      );
      _validator = PuzzleValidator(puzzle: _transformedPuzzle);
      _hintService = PuzzleHintService(puzzle: _transformedPuzzle);
      _scheduleInitializePuzzle();
    }
  }

  @override
  void dispose() {
    _removeSuccessConfetti();
    _annotationModeNotifier.dispose();
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

  /// Ensure the engine uses the correct *structural* rules for this puzzle.
  ///
  /// The variant-ID detection covers structural parameters that affect move
  /// legality (piece count, board topology, capture mechanics, etc.) but
  /// intentionally ignores generic tuning knobs (nMoveRule, endgameNMoveRule,
  /// threefoldRepetitionRule …).  Since puzzles are short tactical exercises,
  /// these tuning parameters are extremely unlikely to influence gameplay.
  ///
  /// Keeping the user's own tuning preferences when the variant already
  /// matches avoids silently overriding their settings with those of the
  /// puzzle creator — which would be unfriendly for imported puzzles.
  ///
  /// Resolution order:
  ///
  /// 1. **Variant IDs match** → do nothing.  The structural rules are
  ///    already correct; honour the solver's tuning preferences.
  /// 2. **Variant IDs differ + snapshot available** → apply the full
  ///    snapshot for exact reconstruction (essential for custom variants
  ///    that have no canonical entry).
  /// 3. **Variant IDs differ + canonical entry** → apply the named
  ///    variant's standard settings (for older puzzles without a snapshot).
  /// 4. **Variant IDs differ + nothing available** → warn the user.
  void _applyPuzzleRulesIfNeeded() {
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    final String puzzleVariantId = _activePuzzle.ruleVariantId;

    // --- 1) Variant IDs already agree — structural rules are correct ------

    if (puzzleVariantId == currentVariant.id) {
      return;
    }

    // --- 2) Try the embedded rule-settings snapshot -----------------------

    if (_activePuzzle.ruleSettingsJson != null) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(_activePuzzle.ruleSettingsJson!) as Map<String, dynamic>;
        final RuleSettings snapshotSettings = RuleSettings.fromJson(json);

        DB().ruleSettings = snapshotSettings;

        // Rule changes are picked up directly by
        // `MillVariantOptionsMapper.toTgfMillVariantOptions()` on the next
        // native session creation; no engine-side broadcast is needed.

        logger.i(
          '[PuzzlePage] Applied rule-settings snapshot '
          'for puzzle "${_activePuzzle.id}"',
        );
        return;
      } catch (e) {
        logger.e(
          '[PuzzlePage] Failed to deserialize ruleSettingsJson '
          'for puzzle "${_activePuzzle.id}": $e',
        );
        // Fall through to canonical lookup.
      }
    }

    // --- 3) Canonical lookup by variant ID --------------------------------

    final RuleSettings? canonicalSettings =
        RuleVariant.canonicalSettings[puzzleVariantId];

    if (canonicalSettings != null) {
      DB().ruleSettings = canonicalSettings;

      // Same as above: rule changes propagate via the
      // RuleSettings -> NativeMillVariantOptions mapping, no engine
      // broadcast required.

      logger.i(
        '[PuzzlePage] Auto-switched rules to "$puzzleVariantId" '
        'for puzzle "${_activePuzzle.id}"',
      );
      return;
    }

    // --- 4) No snapshot, no canonical match — warn the user ---------------

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRuleMismatchWarning(currentVariant);
    });
  }

  /// Defers puzzle session setup until after the current build frame.
  ///
  /// [initState] and [didUpdateWidget] run while the framework is still
  /// building widgets. Calling [GameController.reset] there synchronously
  /// updates [NativeMillGameSession.state], which notifies
  /// [AnimatedBuilder]s (e.g. on [GameBoard]) and triggers
  /// `setState() during build`.
  void _scheduleInitializePuzzle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _initializePuzzle();
    });
  }

  /// Publishes session/UI listenable updates after the current build frame.
  ///
  /// The app shell listens to [GameController.activeSessionSnapshotNotifier]
  /// via [ListenableBuilder]. Updating it from [initState] or
  /// [didUpdateWidget] triggers `setState() during build`.
  void _publishGameUiAfterBuild({required GameStateSnapshot snapshot}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final GameController controller = GameController();
      controller.activeSessionSnapshot = snapshot;
      controller.headerIconsNotifier.showIcons();
      controller.boardSemanticsNotifier.updateSemantics();
    });
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
    if (!PuzzleRuleEngine.isValidFen(_transformedPuzzle.initialPosition)) {
      logger.e(
        '[PuzzlePage] Invalid FEN format: '
        '${_transformedPuzzle.initialPosition}',
      );
      _showFenErrorDialog();
      return;
    }

    // Load the transformed initial position into the shell's native session.
    final NativeMillGameSession? nativeSession =
        controller.activeNativeMillSession;
    final bool loaded =
        nativeSession?.loadFen(_transformedPuzzle.initialPosition) ?? false;
    if (!loaded || nativeSession == null) {
      logger.e(
        '[PuzzlePage] Failed to load puzzle position: '
        '${_transformedPuzzle.initialPosition}',
      );
      _showFenErrorDialog();
      return;
    }

    // loadFen updates the native session immediately, but the app-shell
    // snapshot listener may publish only on the next frame. Sync here so
    // puzzleHumanColor reflects the loaded position, not the reset() board.
    _publishGameUiAfterBuild(snapshot: nativeSession.state.value);

    // Puzzle mode: the human plays the side-to-move from the initial position.
    _puzzleHumanColor = nativeSession.sideToMove;
    controller.puzzleHumanColor = _puzzleHumanColor;
    controller.isPuzzleAutoMoveInProgress = false;
    // Re-apply puzzle mode so whoIsAI can reflect the resolved human side.
    controller.gameInstance.gameMode = GameMode.puzzle;
    _isSolved = false;
    _isAutoPlayingOpponent = false;
    _isNavigatingHistory = false;
    _slowerWinFeedbackShown = false;
    _boardFeedback = _PuzzleBoardFeedback.yourTurn;
    _latestPuzzleNode = controller.gameRecorder.activeNode;

    // Store the starting position for exports and history
    controller.gameRecorder.setupPosition = _transformedPuzzle.initialPosition;

    // Reset state
    _moveCountNotifier.value = 0;
    _lastRecordedMoveIndex = -1;
    _validator.reset();
    _hintService.reset();
    _attemptStartedAt = DateTime.now();

    // controller.reset() above replaces gameRecorder; rebuild so PuzzleGameBoard
    // rebinds moveCountNotifier and _onPlayerMove fires after human moves.
    if (mounted) {
      setState(() {});
    }
  }

  /// Applies a symmetry relative to the current puzzle position.
  ///
  /// This is a presentation change, so the active attempt is preserved. The
  /// live session, recorder/move list, accepted solutions, validator history,
  /// and future hints must all move into the same coordinate frame.
  void _transformPuzzleBoard(TransformationType type) {
    final GameController controller = GameController();
    if (_isPlayingSolution ||
        _isAutoPlayingOpponent ||
        controller.isPuzzleAutoMoveInProgress) {
      return;
    }

    final PuzzleInfo nextPuzzle = PuzzleTransformService.transformPuzzle(
      _transformedPuzzle,
      type,
    );
    final bool transformed = controller.transformActiveLocalGame(type);
    if (!transformed) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.of(context).cannotTransform)));
      }
      return;
    }

    _validator.transformCoordinates(type, transformedPuzzle: nextPuzzle);
    _hintService.updatePuzzle(nextPuzzle);
    _lastRecordedMoveIndex = _activePuzzleMoves(controller).length - 1;

    if (!mounted) {
      return;
    }
    setState(() {
      _transformedPuzzle = nextPuzzle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).transformed),
        duration: const Duration(seconds: 1),
      ),
    );
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
      _activePuzzle.ruleVariantId,
    );
    final String puzzleRuleName = puzzleVariant.name;
    final String currentRuleName = currentVariant.name;

    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData dialogTheme =
            _settingsThemeForDialogs ?? Theme.of(dialogContext);
        return Theme(
          data: dialogTheme,
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(Icons.warning, color: dialogTheme.colorScheme.tertiary),
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
                style: TextButton.styleFrom(
                  foregroundColor: dialogTheme.colorScheme.tertiary,
                ),
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
    final ThemeData settingsTheme = Theme.of(context);
    final GameController controller = GameController();
    final bool canContinueOrSkipPuzzle =
        !_isPlayingSolution &&
        !_isAutoPlayingOpponent &&
        !_isNavigatingHistory &&
        !controller.isPuzzleAutoMoveInProgress;
    _settingsThemeForDialogs = settingsTheme;

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
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(s.cancel),
                  ),
                  TextButton(
                    key: const Key('puzzle_exit_confirm'),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(s.exitPuzzleAction),
                  ),
                ],
              ),
            );
          },
        );
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
        key: const Key('puzzle_page_scaffold'),
        backgroundColor: settingsTheme.colorScheme.surface,
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _activePuzzle.titleForDisplay(
                  showHints: DB().puzzleSettings.showHints,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                s.puzzleReference(_activePuzzle.referenceCode),
                key: const Key('puzzle_page_reference'),
                style: settingsTheme.textTheme.labelSmall?.copyWith(
                  color: settingsTheme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            if (DB().displaySettings.isAnnotationToolbarShown)
              ValueListenableBuilder<bool>(
                valueListenable: _annotationModeNotifier,
                builder:
                    (BuildContext context, bool isSelected, Widget? child) {
                      return IconButton(
                        key: const Key('puzzle_page_app_bar_annotation_button'),
                        tooltip: isSelected
                            ? s.exitAnnotationMode
                            : s.enterAnnotationMode,
                        isSelected: isSelected,
                        selectedIcon: const Icon(
                          FluentIcons.draw_image_24_filled,
                        ),
                        icon: const Icon(FluentIcons.draw_image_24_regular),
                        style: const ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll<Color>(
                            Colors.transparent,
                          ),
                        ),
                        onPressed: canContinueOrSkipPuzzle
                            ? () => _annotationModeNotifier.value = !isSelected
                            : null,
                      );
                    },
              ),
            PopupMenuButton<_PuzzleAppBarAction>(
              key: const Key('puzzle_page_app_bar_more'),
              tooltip: s.menu,
              icon: const Icon(Icons.more_vert),
              onSelected: (_PuzzleAppBarAction action) {
                switch (action) {
                  case _PuzzleAppBarAction.continueOrSkip:
                    if (_isSolved) {
                      _loadNextPuzzle();
                    } else {
                      _skipPuzzle();
                    }
                }
              },
              itemBuilder: (BuildContext context) {
                return <PopupMenuEntry<_PuzzleAppBarAction>>[
                  PopupMenuItem<_PuzzleAppBarAction>(
                    key: Key(
                      _isSolved
                          ? 'puzzle_page_app_bar_next'
                          : 'puzzle_page_app_bar_skip',
                    ),
                    value: _PuzzleAppBarAction.continueOrSkip,
                    enabled: canContinueOrSkipPuzzle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(_isSolved ? Icons.arrow_forward : Icons.skip_next),
                        const SizedBox(width: 12),
                        Text(_isSolved ? s.puzzleContinueNext : s.puzzleSkip),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            ValueListenableBuilder<int>(
              valueListenable: _moveCountNotifier,
              builder: (BuildContext context, int moveCount, Widget? child) {
                return _buildInfoPanel(context, s, moveCount);
              },
            ),
            _buildPuzzleBoardFeedback(context, s),
            Expanded(
              child: IgnorePointer(
                key: const Key('puzzle_page_board_interaction_guard'),
                ignoring: !_isPuzzleBoardInteractive,
                child: PuzzleGameBoard(
                  puzzle: _activePuzzle,
                  onMoveCompleted: _onPlayerMove,
                  annotationModeNotifier: _annotationModeNotifier,
                ),
              ),
            ),
            _buildPlayerElo(context, s),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: _moveCountNotifier,
          builder: (BuildContext context, int moveCount, Widget? child) {
            return _buildPuzzleBottomBar(context, s, moveCount);
          },
        ),
      ),
    );
  }

  bool get _isAtLatestPuzzlePosition {
    final PgnNode<ExtMove>? latest = _latestPuzzleNode;
    if (latest == null) {
      return true;
    }
    return identical(GameController().gameRecorder.activeNode, latest);
  }

  bool get _isPuzzleBoardInteractive {
    final GameController controller = GameController();
    return _isAtLatestPuzzlePosition &&
        !_isSolved &&
        !_isPlayingSolution &&
        !_isAutoPlayingOpponent &&
        !_isNavigatingHistory &&
        !controller.isPuzzleAutoMoveInProgress;
  }

  Widget _buildPuzzleBoardFeedback(BuildContext context, S s) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isError = _boardFeedback == _PuzzleBoardFeedback.notBestMove;
    final String message = isError ? s.puzzleNotBestMove : s.puzzleYourTurn;

    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        key: const Key('puzzle_page_board_feedback'),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 36),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            message,
            key: ValueKey<_PuzzleBoardFeedback>(_boardFeedback),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isError ? colors.error : colors.onSurfaceVariant,
              fontWeight: isError ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  void _updateBoardFeedback(_PuzzleBoardFeedback feedback) {
    if (!mounted || _boardFeedback == feedback) {
      return;
    }
    setState(() => _boardFeedback = feedback);
  }

  Widget _buildPlayerElo(BuildContext context, S s) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return ValueListenableBuilder<PuzzleSettings>(
      valueListenable: _puzzleManager.settingsNotifier,
      builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
        return Container(
          key: const Key('puzzle_page_player_elo'),
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
          child: Text(
            s.eloRating(settings.userRating),
            key: const Key('puzzle_page_player_elo_text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoPanel(BuildContext context, S s, int moveCount) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, maxHeight: 56),
            child: _isPlayingSolution
                ? _buildPlayingSolutionBanner(context, s)
                : SingleChildScrollView(
                    child: Text(
                      _activePuzzle.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<PuzzleSettings>(
            valueListenable: _puzzleManager.settingsNotifier,
            builder:
                (BuildContext context, PuzzleSettings settings, Widget? child) {
                  final PuzzleProgress? progress = settings.getProgress(
                    _activePuzzle.id,
                  );
                  final int attempts = progress?.attempts ?? 0;

                  return Row(
                    key: const Key('puzzle_page_stats_row'),
                    children: <Widget>[
                      Flexible(
                        child: _buildStatChip(
                          context,
                          s.moves,
                          moveCount.toString(),
                          Icons.swap_horiz,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _buildStatChip(
                          context,
                          s.optimal,
                          _activePuzzle.optimalMoveCount.toString(),
                          Icons.star,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _buildStatChip(
                          context,
                          s.difficulty,
                          _activePuzzle.difficulty.getDisplayName(
                            S.of,
                            context,
                          ),
                          Icons.signal_cellular_alt,
                          key: const Key('puzzle_difficulty_stat_chip'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _buildStatChip(
                          context,
                          s.whoMovesFirst,
                          _puzzleFirstMoverLabel(s),
                          Icons.play_arrow,
                          key: const Key('puzzle_first_move_stat_chip'),
                        ),
                      ),
                      if (attempts > 0) ...<Widget>[
                        const SizedBox(width: 4),
                        Flexible(
                          child: _buildStatChip(
                            context,
                            s.puzzleAttemptsLabel,
                            attempts.toString(),
                            Icons.numbers,
                            key: const Key('puzzle_attempts_stat_chip'),
                          ),
                        ),
                      ],
                    ],
                  );
                },
          ),
        ],
      ),
    );
  }

  String _puzzleFirstMoverLabel(S s) {
    return switch (_activePuzzle.playerSide) {
      PieceColor.white => s.offlineBoardWhite,
      PieceColor.black => s.offlineBoardBlack,
      final PieceColor side => throw StateError(
        'Puzzle ${_activePuzzle.id} has invalid initial side to move: $side',
      ),
    };
  }

  Widget _buildPlayingSolutionBanner(BuildContext context, S s) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.puzzlePlayingSolution,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Key? key,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPuzzleBottomBar(BuildContext context, S s, int moveCount) {
    final GameController controller = GameController();
    assert(moveCount >= 0, 'Puzzle move count cannot be negative.');
    final bool canNavigate =
        !_isPlayingSolution &&
        !_isAutoPlayingOpponent &&
        !_isNavigatingHistory &&
        !controller.isPuzzleAutoMoveInProgress;
    final bool canUseActions =
        canNavigate && !_isSolved && _isAtLatestPuzzlePosition;
    final PgnNode<ExtMove>? previousTurn = canNavigate
        ? _previousPuzzleTurnNode()
        : null;
    final PgnNode<ExtMove>? nextTurn = canNavigate
        ? _nextPuzzleTurnNode()
        : null;

    return LichessBottomBar(
      key: const Key('puzzle_page_lichess_bottom_bar'),
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('puzzle_page_bottom_bar_menu'),
          icon: Icons.menu,
          label: s.menu,
          onTap: canUseActions ? () => _openPuzzleMenu(context) : null,
        ),
        LichessBottomBarButton(
          key: const Key('puzzle_page_bottom_bar_give_up'),
          icon: Icons.flag_outlined,
          label: s.giveUp,
          onTap: canUseActions ? _giveUp : null,
        ),
        LichessBottomBarButton(
          key: const Key('puzzle_page_bottom_bar_previous'),
          icon: Icons.chevron_left,
          label: s.previous,
          onTap: previousTurn == null
              ? null
              : () => _navigatePuzzleHistory(previousTurn),
          showTooltip: false,
        ),
        LichessBottomBarButton(
          key: const Key('puzzle_page_bottom_bar_next'),
          icon: Icons.chevron_right,
          label: s.next,
          onTap: nextTurn == null
              ? null
              : () => _navigatePuzzleHistory(nextTurn),
          showTooltip: false,
        ),
      ],
    );
  }

  /// Returns the position immediately before the current complete Mill turn.
  ///
  /// A Mill turn may contain a placement/movement followed by one or more
  /// removals by the same side. History navigation keeps that group atomic so
  /// the board never stops halfway through a completed turn.
  PgnNode<ExtMove>? _previousPuzzleTurnNode() {
    final GameRecorder recorder = GameController().gameRecorder;
    final PgnNode<ExtMove>? active = recorder.activeNode;
    if (active == null || identical(active, recorder.pgnRoot)) {
      return null;
    }

    assert(active.data != null, 'A non-root puzzle history node needs a move.');
    final PieceColor side = active.data!.side;
    assert(
      side == PieceColor.white || side == PieceColor.black,
      'Puzzle history moves must belong to a playable side.',
    );
    PgnNode<ExtMove>? target = active.parent;
    while (target != null &&
        !identical(target, recorder.pgnRoot) &&
        target.data?.side == side) {
      target = target.parent;
    }
    return target ?? recorder.pgnRoot;
  }

  /// Returns the end of the next complete turn on the recorded active line.
  PgnNode<ExtMove>? _nextPuzzleTurnNode() {
    final GameRecorder recorder = GameController().gameRecorder;
    final PgnNode<ExtMove>? latest = _latestPuzzleNode;
    final PgnNode<ExtMove>? active = recorder.activeNode;
    if (latest == null || active == null || identical(active, latest)) {
      return null;
    }

    final List<PgnNode<ExtMove>> latestPath = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? node = latest;
    while (node != null && !identical(node, recorder.pgnRoot)) {
      latestPath.add(node);
      node = node.parent;
    }
    if (node == null) {
      return null;
    }
    final List<PgnNode<ExtMove>> orderedPath = latestPath.reversed.toList(
      growable: false,
    );

    final int activeIndex = identical(active, recorder.pgnRoot)
        ? -1
        : orderedPath.indexOf(active);
    if ((!identical(active, recorder.pgnRoot) && activeIndex == -1) ||
        activeIndex + 1 >= orderedPath.length) {
      return null;
    }

    int targetIndex = activeIndex + 1;
    assert(
      orderedPath[targetIndex].data != null,
      'A puzzle history path cannot contain an empty move node.',
    );
    final PieceColor side = orderedPath[targetIndex].data!.side;
    assert(
      side == PieceColor.white || side == PieceColor.black,
      'Puzzle history moves must belong to a playable side.',
    );
    while (targetIndex + 1 < orderedPath.length &&
        orderedPath[targetIndex + 1].data?.side == side) {
      targetIndex++;
    }
    return orderedPath[targetIndex];
  }

  Future<void> _navigatePuzzleHistory(PgnNode<ExtMove> target) async {
    final GameController controller = GameController();
    if (!mounted ||
        _isPlayingSolution ||
        _isAutoPlayingOpponent ||
        _isNavigatingHistory ||
        controller.isPuzzleAutoMoveInProgress ||
        identical(controller.gameRecorder.activeNode, target)) {
      return;
    }

    setState(() => _isNavigatingHistory = true);
    try {
      final HistoryResponse? response = await HistoryNavigator.gotoNode(
        context,
        target,
        pop: false,
      );
      if (response is! HistoryOK) {
        logger.w('[PuzzlePage] Failed to navigate puzzle history: $response');
      }
    } finally {
      if (mounted) {
        setState(() => _isNavigatingHistory = false);
      } else {
        _isNavigatingHistory = false;
      }
    }
  }

  void _openPuzzleMenu(BuildContext context) {
    final S s = S.of(context);
    final String boardLayout = _activePuzzleBoardLayoutForTransformPreview();
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('puzzle_page_action_sheet'),
      title: Text(s.menu),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('puzzle_page_action_rotate'),
          leading: const Icon(Icons.rotate_right),
          trailing: const Icon(Icons.chevron_right),
          dismissOnPress: false,
          makeLabel: (BuildContext context) => Text(s.rotate),
          onPressed: () {},
          onPressedWithContext: (BuildContext menuActionContext) {
            final NavigatorState navigator = Navigator.of(menuActionContext);
            navigator.pushReplacement<void, void>(
              DialogRoute<void>(
                context: navigator.context,
                builder: (BuildContext dialogContext) {
                  final ThemeData theme =
                      _settingsThemeForDialogs ?? Theme.of(dialogContext);
                  final ColorScheme colors = theme.colorScheme;
                  return Theme(
                    data: theme,
                    child: BoardTransformPickerDialog(
                      sheetKey: const Key('puzzle_page_board_transform_sheet'),
                      keyPrefix: 'puzzle_page_board_transform',
                      title: s.rotate,
                      currentBoardLayout: boardLayout,
                      backgroundColor:
                          theme.dialogTheme.backgroundColor ??
                          colors.surfaceContainer,
                      foregroundColor: colors.onSurface,
                      onSelected: (MillBoardTransformAction action) =>
                          _transformPuzzleBoard(action.type),
                    ),
                  );
                },
              ),
            );
          },
        ),
        if (DB().puzzleSettings.showHints && _hintService.hasHints)
          LichessActionSheetAction(
            key: const Key('puzzle_page_action_hint'),
            leading: const Icon(Icons.lightbulb_outline),
            makeLabel: (BuildContext context) => Text(s.hint),
            onPressed: _showHint,
          ),
        LichessActionSheetAction(
          key: const Key('puzzle_page_action_show_solution'),
          leading: const Icon(Icons.play_arrow),
          makeLabel: (BuildContext context) => Text(s.puzzleShowSolution),
          onPressed: () {
            _showSolution();
          },
        ),
        LichessActionSheetAction(
          key: const Key('puzzle_page_action_reset'),
          leading: const Icon(Icons.refresh),
          makeLabel: (BuildContext context) => Text(s.reset),
          onPressed: _resetPuzzle,
        ),
      ],
    );
  }

  String _activePuzzleBoardLayoutForTransformPreview() {
    final String fen =
        GameController().activeNativeMillSession?.getFen() ??
        _transformedPuzzle.initialPosition;
    assert(
      fen.length >= 26,
      'Puzzle board transform preview requires a complete FEN.',
    );
    return fen.substring(0, 26);
  }

  void _onPlayerMove() {
    if (_isNavigatingHistory) {
      return;
    }

    // Get the latest move from the game recorder
    final GameController controller = GameController();
    final List<ExtMove> moves = _activePuzzleMoves(controller);

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
    }
    _latestPuzzleNode = controller.gameRecorder.activeNode;
    assert(
      humanColor != null,
      'Puzzle human side must be known after loading.',
    );
    if (humanColor != null) {
      _moveCountNotifier.value = _countLogicalMovesForSide(moves, humanColor);
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

  /// Re-check puzzle completion after opponent auto-play finishes.
  ///
  /// Some solution lines end with forced opponent moves. The completion check
  /// that ran on the human move may have been too early, before those moves
  /// were recorded.
  void _checkPuzzleCompletionAfterProgress() {
    if (!mounted || _isSolved || _isPlayingSolution) {
      return;
    }
    _checkSolution(autoCheck: true);
  }

  ValidationFeedback _checkSolution({bool autoCheck = false}) {
    final S s = S.of(context);
    final GameController controller = GameController();
    {
      final PuzzleSolution? matchedSolution =
          _findMatchingPuzzleSolutionFromRecorder();
      final int moveCount = _activePlayerLogicalMoveCount(controller);
      final bool hasExplicitOptimal = _transformedPuzzle.solutions.any(
        (PuzzleSolution solution) => solution.isOptimal,
      );
      if (matchedSolution != null &&
          hasExplicitOptimal &&
          !matchedSolution.isOptimal) {
        return _showSlowerWinFeedback(moveCount);
      }
      if (matchedSolution != null) {
        final ValidationFeedback feedback = ValidationFeedback(
          result: ValidationResult.correct,
          isOptimal: true,
          moveCount: moveCount,
        );
        _onPuzzleSolved(feedback);
        return feedback;
      }

      // A terminal line may differ from the single display line while still
      // taking the same minimum number of solver turns. Accept that equal
      // shortest continuation without requiring the full strategy tree in
      // the compact app asset.
      final bool goalAchieved = _isPuzzleGoalAchievedByTerminalState();
      if (goalAchieved && moveCount == _transformedPuzzle.optimalMoveCount) {
        final ValidationFeedback feedback = ValidationFeedback(
          result: ValidationResult.correct,
          isOptimal: true,
          moveCount: moveCount,
        );
        _onPuzzleSolved(feedback);
        return feedback;
      }
      if (goalAchieved && moveCount > _transformedPuzzle.optimalMoveCount) {
        return _showSlowerWinFeedback(moveCount);
      }
      if (!autoCheck) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.keepGoingObjectiveNotAchieved),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return ValidationFeedback(
        result: ValidationResult.inProgress,
        moveCount: moveCount,
      );
    }
  }

  ValidationFeedback _showSlowerWinFeedback(int moveCount) {
    if (!_slowerWinFeedbackShown) {
      _slowerWinFeedbackShown = true;
      final S s = S.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.puzzleSlowerWinningLine),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: s.tryAgain, onPressed: _resetPuzzle),
        ),
      );
    }
    return ValidationFeedback(
      result: ValidationResult.slowerWin,
      moveCount: moveCount,
    );
  }

  /// Returns true when the active native session has reached a terminal state
  /// that satisfies this puzzle's objective for the human side.
  ///
  /// Used as a fallback to [_findMatchingPuzzleSolutionFromRecorder] so that
  /// reaching the goal (e.g. winning the game) is recognized even if the move
  /// notation in the recorder does not match a stored solution byte-for-byte.
  bool _isPuzzleGoalAchievedByTerminalState() {
    final GameController controller = GameController();
    final NativeMillGameSession? nativeSession =
        controller.activeNativeMillSession;
    if (nativeSession == null || !nativeSession.outcome.isTerminal) {
      return false;
    }
    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;
    if (humanColor == null) {
      return false;
    }
    final PieceColor? winner = controller.activeSessionWinner;
    switch (_activePuzzle.category) {
      case PuzzleCategory.winGame:
      case PuzzleCategory.endgame:
        return winner == humanColor;
      case PuzzleCategory.defend:
        return winner != humanColor.opponent;
      case PuzzleCategory.formMill:
      case PuzzleCategory.capturePieces:
      case PuzzleCategory.findBestMove:
      case PuzzleCategory.opening:
      case PuzzleCategory.mixed:
        return false;
    }
  }

  PuzzleSolution? _findMatchingPuzzleSolutionFromRecorder() {
    final List<String> moves = _activePuzzleMoveNotations(GameController());
    for (final PuzzleSolution solution in _acceptedPuzzleSolutions()) {
      final List<String> expected = solution.moves
          .map((PuzzleMove m) => PuzzleAutoPlayer.normalizeMove(m.notation))
          .toList(growable: false);
      if (expected.length != moves.length) {
        continue;
      }
      bool matches = true;
      for (int i = 0; i < expected.length; i++) {
        if (expected[i] != moves[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return solution;
      }
    }
    return null;
  }

  /// Solution lines accepted while the player is solving the puzzle.
  ///
  /// Generated puzzle sets can retain longer winning alternatives for review.
  /// Once a puzzle explicitly identifies one or more optimal lines, those
  /// alternatives remain visible in the solution dialog but must not make a
  /// non-optimal move appear correct during play.
  List<PuzzleSolution> _acceptedPuzzleSolutions() {
    final List<PuzzleSolution> optimalSolutions = _transformedPuzzle.solutions
        .where((PuzzleSolution solution) => solution.isOptimal)
        .toList(growable: false);
    return optimalSolutions.isNotEmpty
        ? optimalSolutions
        : _transformedPuzzle.solutions;
  }

  /// Show dialog when user makes a wrong move.
  // ignore: unused_element
  void _showWrongMoveDialog() {
    final S s = S.of(context);
    showDialog<void>(
      context: context,
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
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.of(context).puzzleNoSolutionAvailable,
              style: TextStyle(color: colorScheme.onTertiaryContainer),
            ),
            backgroundColor: colorScheme.tertiaryContainer,
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
        settings.getProgress(_activePuzzle.id) ??
        PuzzleProgress(puzzleId: _activePuzzle.id);
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

    // Wait a moment before starting playback
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Play each move with delay
    final GameController controller = GameController();
    for (final PuzzleMove move in solution.moves) {
      if (!mounted || !_isPlayingSolution) {
        break;
      }

      // Try to make the move through the shell's native session.
      final NativeMillGameSession? nativeSession =
          controller.activeNativeMillSession;
      final bool success =
          nativeSession?.applyMoveString(move.notation) ?? false;
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

    final NativeMillGameSession? nativeSession =
        controller.activeNativeMillSession;
    if (nativeSession == null) {
      return;
    }

    if (nativeSession.outcome.isTerminal) {
      return;
    }

    // Convert transformed solutions to legacy format for auto-player.
    // The transformed notations match the current board orientation.
    final List<List<String>> legacySolutions = _acceptedPuzzleSolutions()
        .map(
          (PuzzleSolution s) =>
              s.moves.map((PuzzleMove m) => m.notation).toList(),
        )
        .toList();
    final bool matchesAcceptedPrefix =
        PuzzleAutoPlayer.pickSolutionForPrefix(
          solutions: legacySolutions,
          movesSoFar: _activePuzzleMoveNotations(controller),
        ) !=
        null;
    final bool isOpponentTurn =
        _nativePuzzleSideToAct(nativeSession) != humanColor;

    // A mill-forming action keeps the same player in control until the
    // compulsory removal is made. Validate the solution prefix before the
    // side-to-act gate so a wrong mill is rejected immediately instead of
    // misleading the solver into choosing a capture first.
    if (matchesAcceptedPrefix && !isOpponentTurn) {
      _updateBoardFeedback(_PuzzleBoardFeedback.yourTurn);
      return;
    }

    _isAutoPlayingOpponent = true;
    controller.isPuzzleAutoMoveInProgress = true;
    bool wrongMoveDetected = !matchesAcceptedPrefix;

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        if (controller.hasAnimationManager) {
          await controller.animationManager.waitForBoardAnimations();
        }
        if (!matchesAcceptedPrefix) {
          await _showWrongMoveAndUndo(controller);
          return;
        }
        await PuzzleAutoPlayer.autoPlayOpponentResponses(
          solutions: legacySolutions,
          humanColor: humanColor,
          isGameOver: () => !mounted || nativeSession.outcome.isTerminal,
          sideToMove: () => _nativePuzzleSideToAct(nativeSession),
          movesSoFar: () => _activePuzzleMoveNotations(controller),
          applyMove: (String move) {
            final bool ok = nativeSession.applyMoveString(move);
            if (!ok) {
              logger.e('[PuzzlePage] Failed to auto-play move: $move');
            }
            return ok;
          },
          onAfterApplyMove: controller.hasAnimationManager
              ? controller.animationManager.waitForBoardAnimations
              : null,
          onWrongMove: () async {
            // No solution matches the current line. Undo the last move to prevent
            // a deadlock (human input is restricted to one side in puzzle mode).
            wrongMoveDetected = true;
            await _showWrongMoveAndUndo(controller);
          },
        );
        if (!wrongMoveDetected) {
          _updateBoardFeedback(_PuzzleBoardFeedback.yourTurn);
        }
      } finally {
        controller.isPuzzleAutoMoveInProgress = false;
        if (mounted) {
          setState(() {
            _isAutoPlayingOpponent = false;
          });
        } else {
          _isAutoPlayingOpponent = false;
        }
        controller.headerIconsNotifier.showIcons();
        controller.boardSemanticsNotifier.updateSemantics();
        _checkPuzzleCompletionAfterProgress();
      }
    });
  }

  Future<void> _showWrongMoveAndUndo(GameController controller) async {
    if (!mounted) {
      return;
    }
    _updateBoardFeedback(_PuzzleBoardFeedback.notBestMove);
    await _undoMove(allowDuringAutoPlay: true);

    // Clear auto-play flags immediately after undo so the corrected move can
    // trigger validation without waiting for the surrounding callback.
    controller.isPuzzleAutoMoveInProgress = false;
    _isAutoPlayingOpponent = false;
  }

  PieceColor _nativePuzzleSideToAct(NativeMillGameSession nativeSession) {
    final Object? rawPayload = nativeSession.state.value.payload['tgfPayload'];
    assert(
      rawPayload == null || rawPayload is Uint8List,
      'Native Mill snapshot payload must be a Uint8List.',
    );
    if (rawPayload is! Uint8List || rawPayload.length < 30) {
      return nativeSession.sideToMove;
    }

    // Bytes 28..29 mirror MillBoardView: pending removals for White/Black.
    // During a remove action the side with a pending removal is the actor,
    // regardless of UI snapshot lag while auto-play chains moves.
    final bool whitePending = rawPayload[28] > 0;
    final bool blackPending = rawPayload[29] > 0;
    if (!whitePending && !blackPending) {
      return nativeSession.sideToMove;
    }
    assert(
      whitePending != blackPending,
      'Remove action must have exactly one pending remover.',
    );
    if (whitePending) {
      return PieceColor.white;
    }
    if (blackPending) {
      return PieceColor.black;
    }
    return nativeSession.sideToMove;
  }

  void _onPuzzleSolved(ValidationFeedback feedback) {
    if (_isSolved) {
      return;
    }
    _isSolved = true;
    _showSuccessConfetti();
    final DateTime now = DateTime.now();
    final Duration timeSpent = now.difference(_attemptStartedAt);
    final int hintsUsed = _hintService.hintsGiven;
    final int movesPlayed = _moveCountNotifier.value;
    final int oldRating = DB().puzzleSettings.userRating;

    // Check persisted solutionViewed status to prevent star inflation.
    // The local _solutionViewed flag can be reset by _resetPuzzle(), so we
    // must also consult the persisted progress to detect prior solution views.
    final PuzzleProgress? priorProgress = _puzzleManager.getProgress(
      _activePuzzle.id,
    );
    final bool wasAlreadyCompleted = priorProgress?.completed ?? false;
    final bool effectiveSolutionViewed =
        _solutionViewed || (priorProgress?.solutionViewed ?? false);
    final int? previousBestMoveCount = priorProgress?.bestMoveCount;
    final bool isNewBestMoveCount =
        previousBestMoveCount == null || movesPlayed < previousBestMoveCount;

    // Record completion with solution viewed status.
    // Use _hintsUsed (current session only) instead of merging with
    // priorProgress.hintsUsed so that a clean retry can earn full stars.
    _puzzleManager.completePuzzle(
      puzzleId: _activePuzzle.id,
      moveCount: _moveCountNotifier.value,
      difficulty: _activePuzzle.difficulty,
      optimalMoveCount: _activePuzzle.optimalMoveCount,
      hintsUsed: _hintsUsed,
      solutionViewed: effectiveSolutionViewed,
    );

    final int newRating = DB().puzzleSettings.userRating;
    final int ratingChange = newRating - oldRating;
    _ratingService.saveAttemptResult(
      PuzzleAttemptResult(
        puzzleId: _activePuzzle.id,
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
    final bool isCallbackPuzzle =
        widget.onSolved != null && _activePuzzle.id == widget.puzzle.id;
    if (isCallbackPuzzle) {
      widget.onSolved!.call();
    }

    // In Rush/Streak mode the parent has already advanced to the next puzzle
    // via setState, so showing a completion dialog here would target a stale
    // widget tree and cause timing conflicts.
    if (isCallbackPuzzle && !widget.showSolvedDialogAfterCallback) {
      return;
    }

    if (wasAlreadyCompleted) {
      _showRepeatSolveFeedback(
        isNewBestMoveCount: isNewBestMoveCount && previousBestMoveCount != null,
        moveCount: movesPlayed,
      );
    }

    // Always show the completion dialog in standalone puzzle mode, including
    // repeat solves, so the solver can continue directly to another puzzle.
    _showCompletionDialog(feedback);
  }

  void _showSuccessConfetti() {
    _removeSuccessConfetti();
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) =>
          PuzzleCompletionConfetti(difficulty: _activePuzzle.difficulty),
    );
    _confettiOverlayEntry = entry;

    // Insert after the completion dialog route has been pushed so the
    // celebration remains visible above its modal barrier.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _confettiOverlayEntry != entry) {
        return;
      }
      overlay.insert(entry);
      _confettiTimer = Timer(
        PuzzleCompletionConfetti.displayDuration,
        _removeSuccessConfetti,
      );
    });
  }

  void _removeSuccessConfetti() {
    _confettiTimer?.cancel();
    _confettiTimer = null;
    final OverlayEntry? entry = _confettiOverlayEntry;
    _confettiOverlayEntry = null;
    if (entry?.mounted ?? false) {
      entry!.remove();
    }
  }

  Future<void> _showCompletionDialog(ValidationFeedback feedback) async {
    final _PuzzleCompletionAction? action =
        await showDialog<_PuzzleCompletionAction>(
          context: context,
          barrierDismissible: true,
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

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _PuzzleCompletionAction.tryAgain:
        _resetPuzzle();
      case _PuzzleCompletionAction.nextPuzzle:
        _loadNextPuzzle();
      case _PuzzleCompletionAction.backToList:
        Navigator.of(context).pop();
    }
  }

  void _showRepeatSolveFeedback({
    required bool isNewBestMoveCount,
    required int moveCount,
  }) {
    final S s = S.of(context);
    final String message = isNewBestMoveCount
        ? '${s.puzzleSolvedAgain}\n${s.puzzleNewBestMoves(moveCount)}'
        : s.puzzleSolvedAgain;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Widget _buildCompletionDialog(
    BuildContext context,
    ValidationFeedback feedback,
  ) {
    final S s = S.of(context);

    // Use persisted progress to compute stars consistently with completePuzzle().
    final PuzzleProgress? priorProgress = _puzzleManager.getProgress(
      _activePuzzle.id,
    );
    final bool effectiveSolutionViewed =
        _solutionViewed || (priorProgress?.solutionViewed ?? false);

    final int stars = PuzzleProgress.calculateStars(
      moveCount: _moveCountNotifier.value,
      optimalMoveCount: _activePuzzle.optimalMoveCount,
      difficulty: _activePuzzle.difficulty,
      hintsUsed: _hintsUsed,
      solutionViewed: effectiveSolutionViewed,
    );

    final String? completionMessage = _activePuzzle
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
                  Text('${s.optimal}: ${_activePuzzle.optimalMoveCount}'),
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
          key: const Key('puzzle_completion_try_again'),
          onPressed: () =>
              Navigator.of(context).pop(_PuzzleCompletionAction.tryAgain),
          child: Text(s.tryAgain),
        ),
        TextButton(
          key: const Key('puzzle_completion_next_puzzle'),
          onPressed: () =>
              Navigator.of(context).pop(_PuzzleCompletionAction.nextPuzzle),
          child: Text(s.puzzleNextPuzzle),
        ),
        TextButton(
          key: const Key('puzzle_completion_back_to_list'),
          onPressed: () =>
              Navigator.of(context).pop(_PuzzleCompletionAction.backToList),
          child: Text(s.backToList),
        ),
      ],
    );
  }

  void _loadNextPuzzle() {
    _removeSuccessConfetti();
    _annotationModeNotifier.value = false;
    // Keep continuous practice on the same guided difficulty curve as the
    // daily puzzle. Previously this selected randomly from every unsolved
    // puzzle, allowing a beginner puzzle to jump directly to expert.
    final List<PuzzleInfo> allPuzzles = _puzzleManager.getAllPuzzles();
    final PuzzleSettings settings = _puzzleManager.settingsNotifier.value;

    // Filter for unsolved puzzles (excluding the current one).
    List<PuzzleInfo> candidates = allPuzzles.where((PuzzleInfo p) {
      if (p.id == _activePuzzle.id) {
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

    // Built-in practice should not unexpectedly jump into a custom puzzle.
    if (!_activePuzzle.isCustom) {
      final List<PuzzleInfo> builtInCandidates = candidates
          .where((PuzzleInfo puzzle) => !puzzle.isCustom)
          .toList();
      if (builtInCandidates.isNotEmpty) {
        candidates = builtInCandidates;
      }
    }

    final List<PuzzleInfo> guidedCandidates = const PuzzleSelectionService()
        .candidatesForExperience(
          candidates,
          experience: settings.totalCompleted,
          userRating: settings.userRating,
        );

    // Within the guided difficulty, prefer the same tactical category.
    final List<PuzzleInfo> sameCategoryPuzzles = guidedCandidates
        .where((PuzzleInfo p) => p.category == _activePuzzle.category)
        .toList();

    final List<PuzzleInfo> pool = sameCategoryPuzzles.isNotEmpty
        ? sameCategoryPuzzles
        : guidedCandidates;
    pool.sort((PuzzleInfo a, PuzzleInfo b) {
      final int aDistance = a.rating == null
          ? 1 << 30
          : (a.rating! - settings.userRating).abs();
      final int bDistance = b.rating == null
          ? 1 << 30
          : (b.rating! - settings.userRating).abs();
      final int ratingComparison = aDistance.compareTo(bDistance);
      return ratingComparison != 0 ? ratingComparison : a.id.compareTo(b.id);
    });
    final PuzzleInfo nextPuzzle = pool.first;

    // Keep the same route alive while changing puzzles. Replacing the route
    // would dispose the old PuzzlePage after the new one initializes, causing
    // the old page to restore human-vs-AI mode over the new puzzle session.
    final TransformationType initialTransform =
        PuzzlePage.debugTransformationOverride ??
        randomTransformationType(excludeIdentity: false);
    setState(() {
      _activePuzzle = nextPuzzle;
      _transformedPuzzle = PuzzleTransformService.transformPuzzle(
        nextPuzzle,
        initialTransform,
      );
      _validator = PuzzleValidator(puzzle: _transformedPuzzle);
      _hintService = PuzzleHintService(puzzle: _transformedPuzzle);
      _hintsUsed = false;
      _solutionViewed = false;
      _isPlayingSolution = false;
    });
    _scheduleInitializePuzzle();
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

    _puzzleManager.recordHintUsed(_activePuzzle.id);

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
    if (_activePuzzleMoves(controller).isEmpty) {
      return;
    }

    if (!allowDuringAutoPlay &&
        (_isAutoPlayingOpponent || controller.isPuzzleAutoMoveInProgress)) {
      return;
    }

    // In Puzzle mode, a single user decision is typically followed by an
    // auto-played opponent response. Undo should bring the user back to a
    // position where it's the human side to move again, otherwise input would
    // be locked to prevent playing for the opponent.
    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;

    await _undoNativePuzzleMove(controller, humanColor);
  }

  Future<void> _undoNativePuzzleMove(
    GameController controller,
    PieceColor? humanColor,
  ) async {
    final int maxSteps = _activePuzzleMoves(controller).length;
    int undone = 0;

    while (_activePuzzleMoves(controller).isNotEmpty && undone < maxSteps) {
      final int moveCountBeforeUndo = _activePuzzleMoves(controller).length;
      final PgnNode<ExtMove>? target =
          controller.gameRecorder.activeNode?.parent;
      assert(
        target != null,
        'A non-empty puzzle path must have a parent history node.',
      );
      if (target == null || !mounted) {
        return;
      }
      await HistoryNavigator.gotoNode(context, target, pop: false);
      final bool movedBack =
          _activePuzzleMoves(controller).length == moveCountBeforeUndo - 1;
      assert(movedBack, 'Puzzle history replay failed to take back one move.');
      if (!movedBack) {
        return;
      }
      undone++;

      _lastRecordedMoveIndex--;
      _validator.undoLastMove();

      if (humanColor == null ||
          controller.activeSessionSideToMove == humanColor) {
        break;
      }
    }
    assert(humanColor != null, 'Puzzle human side must be known before undo.');
    _latestPuzzleNode = controller.gameRecorder.activeNode;
    if (humanColor != null) {
      _moveCountNotifier.value = _countLogicalMovesForSide(
        _activePuzzleMoves(controller),
        humanColor,
      );
    }
  }

  void _resetPuzzle() {
    _removeSuccessConfetti();
    _annotationModeNotifier.value = false;
    // Record retry attempt if puzzle was already started
    if (_moveCountNotifier.value > 0 && !_isSolved) {
      _puzzleManager.recordAttempt(_activePuzzle.id);
      _ratingService.saveAttemptResult(
        PuzzleAttemptResult(
          puzzleId: _activePuzzle.id,
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

  /// Active puzzle line from root to the current position.
  ///
  /// Undo keeps rolled-back moves as PGN variations, so [GameRecorder.mainlineMoves]
  /// can still contain a prior wrong attempt even when [currentPath] is empty.
  List<ExtMove> _activePuzzleMoves(GameController controller) {
    return controller.gameRecorder.currentPath;
  }

  int _activePlayerLogicalMoveCount(GameController controller) {
    final PieceColor? humanColor =
        _puzzleHumanColor ?? controller.puzzleHumanColor;
    assert(
      humanColor != null,
      'Puzzle human side must be known after loading.',
    );
    if (humanColor == null) {
      return 0;
    }
    return _countLogicalMovesForSide(
      _activePuzzleMoves(controller),
      humanColor,
    );
  }

  int _countLogicalMovesForSide(List<ExtMove> moves, PieceColor side) {
    return moves.where((ExtMove move) {
      final String notation = move.move.trimLeft().toLowerCase();
      return move.side == side && !notation.startsWith('x');
    }).length;
  }

  List<String> _activePuzzleMoveNotations(GameController controller) {
    return _activePuzzleMoves(controller)
        .map((ExtMove m) => PuzzleAutoPlayer.normalizeMove(m.move))
        .toList(growable: false);
  }

  Future<void> _giveUp() async {
    final S s = S.of(context);

    // The dialog reveals the full solution, so mark solutionViewed immediately.
    // Even if the user cancels and returns to the puzzle, they have already
    // seen the answer and should not earn full stars on a subsequent solve.
    _solutionViewed = true;
    final PuzzleProgress currentProgress =
        _puzzleManager.getProgress(_activePuzzle.id) ??
        PuzzleProgress(puzzleId: _activePuzzle.id);
    _puzzleManager.updateProgress(
      currentProgress.copyWith(solutionViewed: true),
    );

    final _PuzzleSolutionAction?
    action = await showDialog<_PuzzleSolutionAction>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme =
            _settingsThemeForDialogs ?? Theme.of(dialogContext);
        return Theme(
          data: theme,
          child: Builder(
            builder: (BuildContext context) {
              final ColorScheme colorScheme = Theme.of(context).colorScheme;
              return AlertDialog(
                key: const Key('puzzle_solution_dialog'),
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
                                      '${solution.isOptimal ? s.puzzleOptimalSolution : s.puzzleAlternativeSolution} · ${s.puzzleSolutionActionCount(solution.moves.length)}:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ...buildSolutionMoves(
                                      solution,
                                      context,
                                      initialPosition:
                                          _transformedPuzzle.initialPosition,
                                      ruleSettings: DB().ruleSettings,
                                      keyPrefix:
                                          'puzzle_solution_${solutionIndex + 1}',
                                    ),
                                  ],
                                )
                              : ExpansionTile(
                                  title: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: <Widget>[
                                      Text(
                                        s.puzzleSolutionTab(solutionIndex + 1),
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
                                              ? colorScheme.tertiary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        '(${s.puzzleSolutionActionCount(solution.moves.length)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
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
                                          initialPosition: _transformedPuzzle
                                              .initialPosition,
                                          ruleSettings: DB().ruleSettings,
                                          keyPrefix:
                                              'puzzle_solution_${solutionIndex + 1}',
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
                    key: const Key('puzzle_solution_cancel'),
                    onPressed: () =>
                        Navigator.of(context).pop(_PuzzleSolutionAction.stay),
                    child: Text(s.cancel),
                  ),
                  TextButton(
                    key: const Key('puzzle_solution_next_puzzle'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_PuzzleSolutionAction.nextPuzzle),
                    child: Text(s.puzzleNextPuzzle),
                  ),
                  TextButton(
                    key: const Key('puzzle_solution_back_to_list'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_PuzzleSolutionAction.backToList),
                    child: Text(s.backToList),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (action == null || action == _PuzzleSolutionAction.stay || !mounted) {
      return;
    }

    _puzzleManager.recordAttempt(_activePuzzle.id);
    if (_moveCountNotifier.value > 0 || _hintsUsed) {
      _ratingService.saveAttemptResult(
        PuzzleAttemptResult(
          puzzleId: _activePuzzle.id,
          success: false,
          timeSpent: DateTime.now().difference(_attemptStartedAt),
          hintsUsed: _hintService.hintsGiven,
          movesPlayed: _moveCountNotifier.value,
          timestamp: DateTime.now(),
        ),
      );
    }
    if (action == _PuzzleSolutionAction.nextPuzzle) {
      if (widget.onFailed != null && _activePuzzle.id == widget.puzzle.id) {
        widget.onFailed!.call();
      } else {
        _loadNextPuzzle();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  void _skipPuzzle() {
    if (_isSolved || _isPlayingSolution || _isAutoPlayingOpponent) {
      return;
    }

    _puzzleManager.recordAttempt(_activePuzzle.id);
    _ratingService.saveAttemptResult(
      PuzzleAttemptResult(
        puzzleId: _activePuzzle.id,
        success: false,
        timeSpent: DateTime.now().difference(_attemptStartedAt),
        hintsUsed: _hintService.hintsGiven,
        movesPlayed: _moveCountNotifier.value,
        timestamp: DateTime.now(),
      ),
    );
    if (widget.onFailed != null && _activePuzzle.id == widget.puzzle.id) {
      widget.onFailed!.call();
    } else {
      _loadNextPuzzle();
    }
  }
}
