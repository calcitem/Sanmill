// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_creation_page.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';

/// Page for creating custom puzzles
class PuzzleCreationPage extends StatefulWidget {
  const PuzzleCreationPage({super.key, this.puzzleToEdit});

  /// If provided, edit this puzzle instead of creating a new one
  final PuzzleInfo? puzzleToEdit;

  @override
  State<PuzzleCreationPage> createState() => _PuzzleCreationPageState();
}

class _PuzzleCreationPageState extends State<PuzzleCreationPage>
    with TickerProviderStateMixin {
  static const String _tag = "[PuzzleCreationPage]";

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _hintController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();

  PuzzleCategory _selectedCategory = PuzzleCategory.formMill;
  PuzzleDifficulty _selectedDifficulty = PuzzleDifficulty.easy;

  String? _snapshottedPosition;

  // Multi-solution support
  final List<_SolutionData> _solutions = <_SolutionData>[];
  int _currentSolutionIndex = 0;
  bool _isRecordingSolution = false;
  int _moveCountBeforeRecording = 0;

  // Tab controller for solution tabs
  late TabController _tabController;

  bool get _isEditing => widget.puzzleToEdit != null;

  // Current solution being edited/recorded
  _SolutionData get _currentSolution {
    if (_solutions.isEmpty) {
      _solutions.add(_SolutionData());
    }
    return _solutions[_currentSolutionIndex];
  }

  @override
  void initState() {
    super.initState();
    // Initialize with one empty solution
    _solutions.add(_SolutionData(isOptimal: true));
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_onTabChanged);

    if (_isEditing) {
      _loadPuzzleForEditing();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _hintController.dispose();
    _tagsController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  /// Handle tab change
  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _currentSolutionIndex = _tabController.index;
      });
    }
  }

  /// Add a new solution
  void _addSolution() {
    setState(() {
      _solutions.add(_SolutionData());
      _currentSolutionIndex = _solutions.length - 1;
      _tabController.dispose();
      _tabController = TabController(
        length: _solutions.length,
        vsync: this,
        initialIndex: _currentSolutionIndex,
      );
      _tabController.addListener(_onTabChanged);
    });
  }

  /// Remove current solution
  void _removeSolution() {
    if (_solutions.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).puzzleAtLeastOneSolution)),
      );
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).puzzleRemoveSolutionConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.of(context).remove),
            ),
          ],
        );
      },
    ).then((bool? confirmed) {
      if (confirmed ?? false) {
        setState(() {
          _solutions.removeAt(_currentSolutionIndex);
          if (_currentSolutionIndex >= _solutions.length) {
            _currentSolutionIndex = _solutions.length - 1;
          }
          _tabController.dispose();
          _tabController = TabController(
            length: _solutions.length,
            vsync: this,
            initialIndex: _currentSolutionIndex,
          );
          _tabController.addListener(_onTabChanged);
        });
      }
    });
  }

  /// Toggle optimal status of current solution
  void _toggleOptimalStatus() {
    setState(() {
      // If marking as optimal, unmark all others
      if (!_currentSolution.isOptimal) {
        for (final _SolutionData solution in _solutions) {
          solution.isOptimal = false;
        }
      }
      _currentSolution.isOptimal = !_currentSolution.isOptimal;
    });
  }

  /// Load puzzle data when editing
  void _loadPuzzleForEditing() {
    final PuzzleInfo puzzle = widget.puzzleToEdit!;
    _titleController.text = puzzle.title;
    _descriptionController.text = puzzle.description;
    _hintController.text = puzzle.hint ?? '';
    _tagsController.text = puzzle.tags.join(', ');
    _authorController.text = puzzle.author ?? '';
    _selectedCategory = puzzle.category;
    _selectedDifficulty = puzzle.difficulty;
    _snapshottedPosition = puzzle.initialPosition;

    // Load all solutions
    _solutions.clear();
    for (final PuzzleSolution solution in puzzle.solutions) {
      final _SolutionData solutionData = _SolutionData(
        isOptimal: solution.isOptimal,
      );
      for (final PuzzleMove move in solution.moves) {
        solutionData.moves.add(move.notation);
      }
      _solutions.add(solutionData);
    }

    // Update tab controller
    if (_solutions.isNotEmpty) {
      _tabController.dispose();
      _tabController = TabController(length: _solutions.length, vsync: this);
      _tabController.addListener(_onTabChanged);
    }
  }

  /// Open the game board with the given mode and return when user goes back.
  /// This keeps the creation page on the stack so state is preserved.
  Future<void> _openGameBoard(GameMode mode) async {
    final GameController controller = GameController();

    // If we have a snapshotted position, load it into the controller so the user
    // can continue editing from where they left off.
    if (_snapshottedPosition != null) {
      controller.position.setFen(_snapshottedPosition!);
      // Also update the recorder so if they undo, they go back to this state?
      // For setup mode, we usually just care about the board state.
      // But clearing setupPosition ensures we are in a "fresh" edit mode from this fen.
      controller.gameRecorder.setupPosition = _snapshottedPosition;
    } else {
      // If no position snapshotted, start with a fresh board
      // Ensure we don't carry over state from a previous session
      controller.reset(force: true);
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GamePage(mode),
      ),
    );

    // Auto-update snapshot when returning from board editor
    _checkAndSnapshotPosition(silent: true);
  }

  /// Check if the current game board position is valid and different from
  /// the snapshotted position, and if so, update the snapshot.
  void _checkAndSnapshotPosition({bool silent = false}) {
    final GameController controller = GameController();
    final String fen = controller.position.fen ?? '';

    // If empty or invalid, ignore (unless we want to allow clearing?)
    // But usually we don't want to auto-clear valid positions with empty ones
    // unless explicit.
    if (fen.isEmpty) {
      return;
    }

    // Validate FEN
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(fen)) {
      return;
    }

    // Check if changed
    if (fen == _snapshottedPosition) {
      return;
    }

    setState(() {
      _snapshottedPosition = fen;
    });

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzlePositionSnapshotted),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Maybe a subtle indicator or just log?
      // User requested they "don't realize they need to click capture".
      // So updating silently updates the UI (MiniBoard), which is the visual feedback.
      logger.i("$_tag Auto-snapshotted position: $fen");
    }
  }

  /// Snapshot the current board position as the puzzle starting position
  void _snapshotPosition() {
    _checkAndSnapshotPosition();
  }

  /// Start recording solution moves
  void _startRecordingSolution() {
    if (_snapshottedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleSnapshotPositionFirst),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final GameController controller = GameController();

    // Load the snapshotted position to the game board
    // This ensures the board is at the correct starting position when user returns
    final bool loaded = controller.position.setFen(_snapshottedPosition!);
    if (!loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleFailedLoadPosition),
          backgroundColor: Colors.red,
        ),
      );
      logger.e("$_tag Failed to load snapshotted position for recording");
      return;
    }

    // Ensure we are in Human vs Human so AI will not interfere while recording.
    controller.gameInstance.gameMode = GameMode.humanVsHuman;

    // Reset the game recorder to clear all previous moves
    controller.gameRecorder.reset();
    controller.gameRecorder.setupPosition = _snapshottedPosition;

    // Refresh UI elements
    controller.headerIconsNotifier.showIcons();
    controller.boardSemanticsNotifier.updateSemantics();

    // Start recording from the current tail (more robust than assuming 0)
    _moveCountBeforeRecording = controller.gameRecorder.mainlineMoves.length;

    setState(() {
      _isRecordingSolution = true;
      _currentSolution.moves.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).puzzleRecordingStarted),
        backgroundColor: Colors.green,
      ),
    );

    logger.i(
      "$_tag Started recording solution ${_currentSolutionIndex + 1} moves from snapshotted position",
    );
  }

  /// Stop recording solution moves
  void _stopRecordingSolution() {
    final GameController controller = GameController();
    final List<ExtMove> allMoves = controller.gameRecorder.mainlineMoves;

    // Extract moves recorded during solution recording
    final List<String> recordedMoves = <String>[];
    for (int i = _moveCountBeforeRecording; i < allMoves.length; i++) {
      recordedMoves.add(allMoves[i].move);
    }

    // Snapshot the final position after all solution moves
    final String? finalFen = controller.position.fen;

    setState(() {
      _isRecordingSolution = false;
      _currentSolution.moves.clear();
      _currentSolution.moves.addAll(recordedMoves);
      _currentSolution.finalPosition = finalFen;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S.of(context).puzzleRecordingStopped(_currentSolution.moves.length),
        ),
      ),
    );

    logger.i(
      "$_tag Stopped recording, snapshotted ${_currentSolution.moves.length} moves for solution ${_currentSolutionIndex + 1}",
    );
  }

  /// Clear recorded solution moves
  void _clearSolution() {
    setState(() {
      _currentSolution.moves.clear();
      _isRecordingSolution = false;
    });
  }

  /// Validate puzzle data before saving
  String? _validatePuzzle() {
    if (_titleController.text.trim().isEmpty) {
      return S.of(context).puzzleTitleRequired;
    }

    if (_descriptionController.text.trim().isEmpty) {
      return S.of(context).puzzleDescriptionRequired;
    }

    if (_snapshottedPosition == null) {
      return S.of(context).puzzlePositionRequired;
    }

    // Validate FEN format before saving
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(_snapshottedPosition!)) {
      return S.of(context).puzzleInvalidPositionFormatRecapture;
    }

    if (_solutions.every((_SolutionData s) => s.moves.isEmpty)) {
      return S.of(context).puzzleSolutionRequired;
    }

    return null;
  }

  /// Save the puzzle
  Future<void> _savePuzzle() async {
    final String? error = _validatePuzzle();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    // Generate puzzle ID
    final String puzzleId = _isEditing
        ? widget.puzzleToEdit!.id
        : 'custom_${DateTime.now().millisecondsSinceEpoch}';

    // Parse tags
    final List<String> tags = _tagsController.text
        .split(',')
        .map((String tag) => tag.trim())
        .where((String tag) => tag.isNotEmpty)
        .toList();

    // Create PuzzleSolution objects from all recorded solutions
    // Get starting side from initial position
    final Position tempPos = Position();
    tempPos.setFen(_snapshottedPosition!);
    final PieceColor startingSide = tempPos.sideToMove;

    final List<PuzzleSolution> puzzleSolutions = <PuzzleSolution>[];
    for (final _SolutionData solutionData in _solutions) {
      // Skip empty solutions
      if (solutionData.moves.isEmpty) {
        continue;
      }

      // Convert move notations to PuzzleMove objects
      PieceColor currentSide = startingSide;
      final List<PuzzleMove> puzzleMoves = <PuzzleMove>[];
      for (final String notation in solutionData.moves) {
        puzzleMoves.add(PuzzleMove(notation: notation, side: currentSide));
        currentSide = currentSide.opponent;
      }

      puzzleSolutions.add(
        PuzzleSolution(moves: puzzleMoves, isOptimal: solutionData.isOptimal),
      );
    }

    // Ensure at least one solution is marked as optimal
    if (!puzzleSolutions.any((PuzzleSolution s) => s.isOptimal)) {
      puzzleSolutions.first = PuzzleSolution(
        moves: puzzleSolutions.first.moves,
      );
    }

    // Create puzzle info
    final PuzzleInfo puzzle = PuzzleInfo(
      id: puzzleId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _selectedCategory,
      difficulty: _selectedDifficulty,
      initialPosition: _snapshottedPosition!,
      solutions: puzzleSolutions,
      hint: _hintController.text.trim().isEmpty
          ? null
          : _hintController.text.trim(),
      tags: tags,
      isCustom: true,
      author: _authorController.text.trim().isEmpty
          ? null
          : _authorController.text.trim(),
    );

    // Save puzzle
    final PuzzleManager manager = PuzzleManager();
    final bool success = _isEditing
        ? manager.updatePuzzle(puzzle)
        : manager.addCustomPuzzle(puzzle);

    if (success) {
      logger.i("$_tag Puzzle saved: ${puzzle.title}");
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? S.of(context).puzzleUpdated
                : S.of(context).puzzleCreated,
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } else {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleSaveFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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

        // Use Builder to ensure the context has the correct theme.
        // This prevents computing styles from a context outside the Theme wrapper.
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                backgroundColor: useDarkSettingsUi
                    ? settingsTheme.scaffoldBackgroundColor
                    : AppTheme.lightBackgroundColor,
                // Prevent scaffold from resizing when keyboard appears
                // This improves performance by avoiding layout recalculation
                resizeToAvoidBottomInset: true,
                appBar: AppBar(
                  title: Text(
                    _isEditing
                        ? S.of(context).puzzleEdit
                        : S.of(context).puzzleCreateNew,
                    style: useDarkSettingsUi
                        ? null
                        : AppTheme.appBarTheme.titleTextStyle,
                  ),
                  actions: <Widget>[
                    IconButton(
                      icon: const Icon(FluentIcons.save_24_regular),
                      onPressed: _savePuzzle,
                      tooltip: S.of(context).save,
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  // Use physics that don't interfere with keyboard animation
                  physics: const ClampingScrollPhysics(),
                  // Reduce rebuild overhead with const key
                  key: const PageStorageKey<String>('puzzle_creation_scroll'),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Instructions card
                      _buildInstructionsCard(context),
                      const SizedBox(height: 16),

                      // Position snapshot section
                      _buildPositionSnapshotSection(context),
                      const SizedBox(height: 16),

                      // Solution recording section
                      _buildSolutionRecordingSection(context),
                      const SizedBox(height: 24),

                      // Metadata section
                      _buildMetadataSection(context),
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

  Widget _buildInstructionsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0), // Reduced padding
        child: Row(
          children: <Widget>[
            Icon(
              FluentIcons.lightbulb_24_regular,
              size: 20,
              color: Colors.amber[300],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.of(context).puzzleCreationInstructions,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Help icon button to show detailed workflow
            IconButton(
              icon: Icon(
                FluentIcons.question_circle_24_regular,
                color: Colors.blue[300],
                size: 24,
              ),
              onPressed: () => _showWorkflowHelp(context),
              tooltip: S.of(context).puzzleShowDetailedWorkflow,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  /// Show detailed workflow help dialog
  void _showWorkflowHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.lightbulb_24_filled, color: Colors.amber[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(dialogContext).puzzleCreationWorkflow,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildWorkflowStep(
                dialogContext,
                '1',
                S.of(dialogContext).puzzleWorkflowStepSetup,
                S.of(dialogContext).puzzleWorkflowStepSetupDesc,
                _snapshottedPosition != null,
              ),
              _buildWorkflowStep(
                dialogContext,
                '2',
                S.of(dialogContext).puzzleWorkflowStepRecord,
                S.of(dialogContext).puzzleWorkflowStepRecordDesc,
                _currentSolution.moves.isNotEmpty,
              ),
              _buildWorkflowStep(
                dialogContext,
                '3',
                S.of(dialogContext).puzzleWorkflowStepDetails,
                S.of(dialogContext).puzzleWorkflowStepDetailsDesc,
                false,
              ),
              _buildWorkflowStep(
                dialogContext,
                '4',
                S.of(dialogContext).puzzleWorkflowStepSave,
                S.of(dialogContext).puzzleWorkflowStepSaveDesc,
                false,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 16,
                      color: Colors.orange[300],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(dialogContext).puzzleWorkflowTip,
                        // Avoid forcing a low-contrast color; let the theme decide.
                        style: const TextStyle(fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).ok),
          ),
        ],
      ),
    );
  }

  /// Show position snapshot help dialog
  void _showPositionSnapshotHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.info_24_filled, color: Colors.blue[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(dialogContext).puzzlePositionSnapshotHelp,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            S.of(dialogContext).puzzlePositionSnapshotHelpContent,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).ok),
          ),
        ],
      ),
    );
  }

  /// Show solution recording help dialog
  void _showSolutionRecordingHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.info_24_filled, color: Colors.blue[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(dialogContext).puzzleSolutionRecordingHelp,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                S.of(dialogContext).puzzleSolutionRecordingHelpContent,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              _buildInstructionStep(
                '1',
                S.of(dialogContext).puzzleSolutionStep1,
              ),
              _buildInstructionStep(
                '2',
                S.of(dialogContext).puzzleSolutionStep2,
              ),
              _buildInstructionStep(
                '3',
                S.of(dialogContext).puzzleRecordingHintUseButton,
              ),
              _buildInstructionStep(
                '4',
                S.of(dialogContext).puzzleSolutionStep4,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 16,
                      color: Colors.orange[300],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(dialogContext).puzzleSolutionRecordingTip,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).ok),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(
    BuildContext context,
    String number,
    String title,
    String description,
    bool isCompleted,
  ) {
    final Color stepColor = isCompleted
        ? Colors.green
        : Theme.of(context).colorScheme.primary;
    final Color titleColor = isCompleted
        ? Colors.green
        : Theme.of(context).colorScheme.onSurface;
    final Color descriptionColor = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: stepColor, shape: BoxShape.circle),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: descriptionColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSnapshotSection(BuildContext context) {
    final Color hintColor = Theme.of(context).colorScheme.onSurfaceVariant;
    // Wrap in RepaintBoundary for performance isolation
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Section title with help icon
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      S.of(context).puzzleSetupPosition,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Help icon for position snapshot instructions
                  IconButton(
                    icon: Icon(
                      FluentIcons.question_circle_24_regular,
                      color: Colors.blue[300],
                      size: 20,
                    ),
                    onPressed: () => _showPositionSnapshotHelp(context),
                    tooltip: S.of(context).puzzleShowPositionSnapshotHelp,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_snapshottedPosition != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            FluentIcons.checkmark_circle_24_filled,
                            color: Colors.green[300],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.of(context).puzzlePositionSnapshotted2,
                              style: TextStyle(
                                color: Colors.green[300],
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Mini board preview of snapshotted position
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Mini board with subtle animation border
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: SizedBox(
                              width: 120,
                              height: 120,
                              child: MiniBoard(
                                boardLayout:
                                    _extractBoardLayout(_snapshottedPosition!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // FEN string
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: SelectableText(
                                _snapshottedPosition!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Colors.grey[300],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else
                Row(
                  children: <Widget>[
                    Icon(
                      FluentIcons.warning_24_regular,
                      color: hintColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      S.of(context).puzzleNoPositionSnapshotted,
                      style: TextStyle(color: hintColor, fontSize: 14),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              // Two options to set up the position: manually or by playing
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Option 1: Manual Setup
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openGameBoard(GameMode.setupPosition),
                        icon: const Icon(FluentIcons.window_new_24_regular),
                        label: Text(
                          S.of(context).puzzleOpenBoardSetup,
                          textAlign: TextAlign.center,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Option 2: Play to Reach Position
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openGameBoard(GameMode.humanVsHuman),
                        icon: const Icon(FluentIcons.play_24_regular),
                        label: Text(
                          S.of(context).puzzleOpenBoardPlay,
                          textAlign: TextAlign.center,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Button to snapshot current board position
              ElevatedButton.icon(
                onPressed: _snapshotPosition,
                icon: const Icon(FluentIcons.camera_24_regular),
                label: Text(S.of(context).puzzleSnapshotPosition),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSolutionRecordingSection(BuildContext context) {
    final Color hintColor = Theme.of(context).colorScheme.onSurfaceVariant;
    // Wrap in RepaintBoundary for performance isolation
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Section title with help icon
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      S.of(context).puzzleRecordSolution,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Help icon for solution recording instructions
                  IconButton(
                    icon: Icon(
                      FluentIcons.question_circle_24_regular,
                      color: Colors.blue[300],
                      size: 20,
                    ),
                    onPressed: () => _showSolutionRecordingHelp(context),
                    tooltip: S.of(context).puzzleShowSolutionRecordingHelp,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Multi-solution tabs with improved visual design
              Row(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          // Solution tabs with custom styling to avoid confusion
                          for (int i = 0; i < _solutions.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _currentSolutionIndex = i;
                                    _tabController.animateTo(i);
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _currentSolutionIndex == i
                                        ? Colors.blue.withValues(alpha: 0.3)
                                        : Colors.grey.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _currentSolutionIndex == i
                                          ? Colors.blue
                                          : Colors.grey.withValues(alpha: 0.4),
                                      width: _currentSolutionIndex == i ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      if (_solutions[i].isOptimal)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 4),
                                          child: Text(
                                            '⭐',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      Text(
                                        S.of(context).puzzleSolutionTab(i + 1),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: _currentSolutionIndex == i
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: _currentSolutionIndex == i
                                              ? Colors.blue[100]
                                              : Colors.grey[300],
                                        ),
                                      ),
                                      if (_solutions[i].moves.isNotEmpty) ...<Widget>[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${_solutions[i].moves.length}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.green[200],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Add solution button
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: OutlinedButton.icon(
                              onPressed: _addSolution,
                              icon: const Icon(
                                FluentIcons.add_24_regular,
                                size: 16,
                              ),
                              label: Text(S.of(context).puzzleAddSolution),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Solution control buttons (mark as optimal, delete)
              if (_solutions.length > 1 || !_currentSolution.isOptimal)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (!_currentSolution.isOptimal)
                      OutlinedButton.icon(
                        onPressed: _toggleOptimalStatus,
                        icon: const Icon(FluentIcons.star_24_regular, size: 16),
                        label: Text(S.of(context).puzzleMarkAsOptimal),
                      ),
                    if (_solutions.length > 1)
                      OutlinedButton.icon(
                        onPressed: _removeSolution,
                        icon: const Icon(
                          FluentIcons.delete_24_regular,
                          size: 16,
                        ),
                        label: Text(S.of(context).puzzleRemoveSolution),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[300],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              
              // Info about multiple solutions
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 16,
                      color: Colors.blue[300],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(context).puzzleMultipleSolutionsSupported,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Recording in progress indicator (compact)
              if (_isRecordingSolution)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        FluentIcons.record_24_filled,
                        color: Colors.red[400],
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.of(context).puzzleRecording,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              if (_currentSolution.moves.isNotEmpty) ...<Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      FluentIcons.checkmark_circle_24_filled,
                      color: Colors.green[300],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      S
                          .of(context)
                          .puzzleSolutionMoves(_currentSolution.moves.length),
                      style: TextStyle(color: Colors.green[300], fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Display both initial and final positions as mini boards
                if (_snapshottedPosition != null &&
                    _currentSolution.finalPosition != null)
                  Row(
                    children: <Widget>[
                      // Initial position
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              S.of(context).puzzleInitialPosition,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: MiniBoard(
                                boardLayout: _extractBoardLayout(
                                  _snapshottedPosition!,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        FluentIcons.arrow_right_24_filled,
                        color: Colors.grey[400],
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      // Final position
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              S.of(context).puzzleFinalPosition,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: MiniBoard(
                                boardLayout: _extractBoardLayout(
                                  _currentSolution.finalPosition!,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _currentSolution.moves.asMap().entries.map((
                    MapEntry<int, String> entry,
                  ) {
                    return Chip(
                      label: Text(
                        '${entry.key + 1}. ${entry.value}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.blue[700],
                    );
                  }).toList(),
                ),
              ] else if (!_isRecordingSolution)
                Row(
                  children: <Widget>[
                    Icon(
                      FluentIcons.warning_24_regular,
                      color: hintColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      S.of(context).puzzleNoSolutionRecorded,
                      style: TextStyle(color: hintColor, fontSize: 14),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (_isRecordingSolution)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => _openGameBoard(GameMode.humanVsHuman),
                      icon: const Icon(FluentIcons.window_new_24_regular),
                      label: Text(S.of(context).puzzleOpenBoardPlay),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _stopRecordingSolution,
                      icon: const Icon(FluentIcons.stop_24_regular),
                      label: Text(S.of(context).puzzleStopRecording),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: _startRecordingSolution,
                      icon: const Icon(FluentIcons.record_24_regular),
                      label: Text(S.of(context).puzzleStartRecording),
                    ),
                    if (_currentSolution.moves.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _clearSolution,
                        icon: const Icon(FluentIcons.delete_24_regular),
                        label: Text(S.of(context).puzzleClearSolution),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// Extract board layout from FEN string
  /// FEN format: "boardLayout activeColor phase action counts..."
  /// Example: "OO******/********/******** w p p 2 7 0 9 0 0 0 0 0 0 0 0 1"
  /// Returns just the board layout part: "OO******/********/********"
  String _extractBoardLayout(String fen) {
    final List<String> parts = fen.split(' ');
    if (parts.isEmpty) {
      // Return empty board if FEN is invalid
      return '********/********/********';
    }
    return parts[0];
  }

  Widget _buildMetadataSection(BuildContext context) {
    // Wrap in RepaintBoundary to isolate repaints from keyboard animation
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                S.of(context).puzzleDetails,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: S.of(context).puzzleTitle,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.textbox_24_regular),
                ),
                // Enable platform optimizations
                enableInteractiveSelection: true,
                // Reduce rebuilds on text changes
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: S.of(context).puzzleDescription,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    FluentIcons.text_description_24_regular,
                  ),
                ),
                maxLines: 3,
                // Reduce rebuilds on text changes
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 12),

              // Category
              DropdownButtonFormField<PuzzleCategory>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: S.of(context).puzzleCategory,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.folder_24_regular),
                ),
                items: PuzzleCategory.values.map((PuzzleCategory category) {
                  return DropdownMenuItem<PuzzleCategory>(
                    value: category,
                    child: Text(category.displayName(context)),
                  );
                }).toList(),
                onChanged: (PuzzleCategory? value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Difficulty
              DropdownButtonFormField<PuzzleDifficulty>(
                initialValue: _selectedDifficulty,
                decoration: InputDecoration(
                  labelText: S.of(context).puzzleDifficulty,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.star_24_regular),
                ),
                items: PuzzleDifficulty.values.map((
                  PuzzleDifficulty difficulty,
                ) {
                  return DropdownMenuItem<PuzzleDifficulty>(
                    value: difficulty,
                    child: Text(difficulty.displayName(context)),
                  );
                }).toList(),
                onChanged: (PuzzleDifficulty? value) {
                  if (value != null) {
                    setState(() {
                      _selectedDifficulty = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Hint (optional)
              TextField(
                controller: _hintController,
                decoration: InputDecoration(
                  labelText:
                      '${S.of(context).puzzleHint} (${S.of(context).optional})',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.lightbulb_24_regular),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Tags (optional)
              TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  labelText:
                      '${S.of(context).puzzleTags} (${S.of(context).optional})',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.tag_24_regular),
                  hintText: S.of(context).puzzleTagsHint,
                ),
              ),
              const SizedBox(height: 12),

              // Author (optional)
              TextField(
                controller: _authorController,
                decoration: InputDecoration(
                  labelText:
                      '${S.of(context).puzzleAuthor} (${S.of(context).optional})',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.person_24_regular),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class to store solution data during creation/editing
class _SolutionData {
  _SolutionData({this.isOptimal = false});

  final List<String> moves = <String>[];
  bool isOptimal;
  String? finalPosition; // Store the final FEN position after solution moves
}
