// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_creation_page.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/game_page.dart';
import '../../generated/intl/l10n.dart';
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

class _PuzzleCreationPageState extends State<PuzzleCreationPage> {
  static const String _tag = "[PuzzleCreationPage]";

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _hintController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();

  PuzzleCategory _selectedCategory = PuzzleCategory.formMill;
  PuzzleDifficulty _selectedDifficulty = PuzzleDifficulty.easy;

  String? _capturedPosition;
  final List<String> _solutionMoves = <String>[];
  bool _isRecordingSolution = false;
  int _moveCountBeforeRecording = 0;

  bool get _isEditing => widget.puzzleToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadPuzzleForEditing();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _hintController.dispose();
    _tagsController.dispose();
    _authorController.dispose();
    super.dispose();
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
    _capturedPosition = puzzle.initialPosition;

    // Load existing solution moves
    // Take the first solution path if multiple exist
    if (puzzle.solutionMoves.isNotEmpty) {
      _solutionMoves.clear();
      _solutionMoves.addAll(puzzle.solutionMoves.first);
    }
  }

  /// Capture the current board position as the puzzle starting position
  void _capturePosition() {
    final GameController controller = GameController();
    final String fen = controller.position.fen ?? '';

    // Validate FEN format before capturing
    if (fen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleInvalidPosition),
          backgroundColor: Colors.red,
        ),
      );
      logger.e("$_tag Cannot capture empty FEN position");
      return;
    }

    // Create a temporary position to validate the FEN
    final Position tempPosition = Position();
    final bool isValid = tempPosition.validateFen(fen);

    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleInvalidPositionFormat),
          backgroundColor: Colors.red,
        ),
      );
      logger.e("$_tag Failed to validate FEN: $fen");
      return;
    }

    setState(() {
      _capturedPosition = fen;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).puzzlePositionCaptured),
        duration: const Duration(seconds: 2),
      ),
    );

    logger.i("$_tag Captured position: $fen");
  }

  /// Open the game board with the given mode and return when user goes back.
  /// This keeps the creation page on the stack so state is preserved.
  Future<void> _openGameBoard(GameMode mode) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GamePage(mode),
      ),
    );
  }

  /// Start recording solution moves
  void _startRecordingSolution() {
    if (_capturedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleCapturePositionFirst),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final GameController controller = GameController();

    // Load the captured position to the game board
    // This ensures the board is at the correct starting position when user returns
    final bool loaded = controller.position.setFen(_capturedPosition!);
    if (!loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleFailedLoadPosition),
          backgroundColor: Colors.red,
        ),
      );
      logger.e("$_tag Failed to load captured position for recording");
      return;
    }

    // Ensure we are in Human vs Human so AI will not interfere while recording.
    controller.gameInstance.gameMode = GameMode.humanVsHuman;

    // Reset the game recorder to clear all previous moves
    controller.gameRecorder.reset();
    controller.gameRecorder.setupPosition = _capturedPosition;

    // Refresh UI elements
    controller.headerIconsNotifier.showIcons();
    controller.boardSemanticsNotifier.updateSemantics();

    // Start recording from the current tail (more robust than assuming 0)
    _moveCountBeforeRecording = controller.gameRecorder.mainlineMoves.length;

    setState(() {
      _isRecordingSolution = true;
      _solutionMoves.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).puzzleRecordingStarted),
        backgroundColor: Colors.green,
      ),
    );

    logger.i("$_tag Started recording solution moves from captured position");
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

    setState(() {
      _isRecordingSolution = false;
      _solutionMoves.clear();
      _solutionMoves.addAll(recordedMoves);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S.of(context).puzzleRecordingStopped(_solutionMoves.length),
        ),
      ),
    );

    logger.i(
      "$_tag Stopped recording, captured ${_solutionMoves.length} moves",
    );
  }

  /// Clear recorded solution moves
  void _clearSolution() {
    setState(() {
      _solutionMoves.clear();
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

    if (_capturedPosition == null) {
      return S.of(context).puzzlePositionRequired;
    }

    // Validate FEN format before saving
    final Position tempPosition = Position();
    if (!tempPosition.validateFen(_capturedPosition!)) {
      return S.of(context).puzzleInvalidPositionFormatRecapture;
    }

    if (_solutionMoves.isEmpty) {
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

    // Create puzzle info
    final PuzzleInfo puzzle = PuzzleInfo(
      id: puzzleId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _selectedCategory,
      difficulty: _selectedDifficulty,
      initialPosition: _capturedPosition!,
      solutionMoves: <List<String>>[_solutionMoves],
      optimalMoveCount: _solutionMoves.length,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? S.of(context).puzzleEdit : S.of(context).puzzleCreateNew,
          style: AppTheme.appBarTheme.titleTextStyle,
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Instructions card
            _buildInstructionsCard(),
            const SizedBox(height: 16),

            // Position capture section
            _buildPositionCaptureSection(),
            const SizedBox(height: 16),

            // Solution recording section
            _buildSolutionRecordingSection(),
            const SizedBox(height: 24),

            // Metadata section
            _buildMetadataSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      color: AppTheme.cardColor,
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
              onPressed: _showWorkflowHelp,
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
  void _showWorkflowHelp() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.lightbulb_24_filled, color: Colors.amber[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(context).puzzleCreationWorkflow,
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
                '1',
                S.of(context).puzzleWorkflowStepSetup,
                S.of(context).puzzleWorkflowStepSetupDesc,
                _capturedPosition != null,
              ),
              _buildWorkflowStep(
                '2',
                S.of(context).puzzleWorkflowStepRecord,
                S.of(context).puzzleWorkflowStepRecordDesc,
                _solutionMoves.isNotEmpty,
              ),
              _buildWorkflowStep(
                '3',
                S.of(context).puzzleWorkflowStepDetails,
                S.of(context).puzzleWorkflowStepDetailsDesc,
                false,
              ),
              _buildWorkflowStep(
                '4',
                S.of(context).puzzleWorkflowStepSave,
                S.of(context).puzzleWorkflowStepSaveDesc,
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
                        S.of(context).puzzleWorkflowTip,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[200],
                        ),
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).ok),
          ),
        ],
      ),
    );
  }

  /// Show position capture help dialog
  void _showPositionCaptureHelp() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.info_24_filled, color: Colors.blue[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(context).puzzlePositionCaptureHelp,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            S.of(context).puzzlePositionCaptureHelpContent,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).ok),
          ),
        ],
      ),
    );
  }

  /// Show solution recording help dialog
  void _showSolutionRecordingHelp() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(FluentIcons.info_24_filled, color: Colors.blue[300]),
            const SizedBox(width: 8),
            // Wrap text in Expanded to prevent overflow on small screens
            Expanded(
              child: Text(
                S.of(context).puzzleSolutionRecordingHelp,
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
                S.of(context).puzzleSolutionRecordingHelpContent,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              _buildInstructionStep('1', S.of(context).puzzleSolutionStep1),
              _buildInstructionStep('2', S.of(context).puzzleSolutionStep2),
              _buildInstructionStep(
                '3',
                S.of(context).puzzleRecordingHintUseButton,
              ),
              _buildInstructionStep('4', S.of(context).puzzleSolutionStep4),
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
                        S.of(context).puzzleSolutionRecordingTip,
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).ok),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(
    String number,
    String title,
    String description,
    bool isCompleted,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green : Colors.blue,
              shape: BoxShape.circle,
            ),
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
                    color: isCompleted ? Colors.green[300] : Colors.white,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionCaptureSection() {
    return Card(
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
                // Help icon for position capture instructions
                IconButton(
                  icon: Icon(
                    FluentIcons.question_circle_24_regular,
                    color: Colors.blue[300],
                    size: 20,
                  ),
                  onPressed: _showPositionCaptureHelp,
                  tooltip: S.of(context).puzzleShowPositionCaptureHelp,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_capturedPosition != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    FluentIcons.checkmark_circle_24_filled,
                    color: Colors.green[300],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).puzzlePositionCaptured,
                    style: TextStyle(color: Colors.green[300], fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  _capturedPosition!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey[300],
                  ),
                ),
              ),
            ] else
              Row(
                children: <Widget>[
                  Icon(
                    FluentIcons.warning_24_regular,
                    color: Colors.grey[400],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).puzzleNoPositionCaptured,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            // Button to open board in setup mode (manually place pieces)
            OutlinedButton.icon(
              onPressed: () => _openGameBoard(GameMode.setupPosition),
              icon: const Icon(FluentIcons.window_new_24_regular),
              label: Text(S.of(context).puzzleOpenBoardSetup),
            ),
            const SizedBox(height: 8),
            // Button to open board in play mode (make moves to reach position)
            OutlinedButton.icon(
              onPressed: () => _openGameBoard(GameMode.humanVsHuman),
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(S.of(context).puzzleOpenBoardPlay),
            ),
            const SizedBox(height: 8),
            // Button to capture current board position
            ElevatedButton.icon(
              onPressed: _capturePosition,
              icon: const Icon(FluentIcons.camera_24_regular),
              label: Text(S.of(context).puzzleCapturePosition),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolutionRecordingSection() {
    return Card(
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
                  onPressed: _showSolutionRecordingHelp,
                  tooltip: S.of(context).puzzleShowSolutionRecordingHelp,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
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
            if (_solutionMoves.isNotEmpty) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    FluentIcons.checkmark_circle_24_filled,
                    color: Colors.green[300],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).puzzleSolutionMoves(_solutionMoves.length),
                    style: TextStyle(color: Colors.green[300], fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _solutionMoves.asMap().entries.map((
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
                    color: Colors.grey[400],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.of(context).puzzleNoSolutionRecorded,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
                  if (_solutionMoves.isNotEmpty)
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

  Widget _buildMetadataSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).puzzleDetails,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            ),
            const SizedBox(height: 12),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: S.of(context).puzzleDescription,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(FluentIcons.text_description_24_regular),
              ),
              maxLines: 3,
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
              items: PuzzleDifficulty.values.map((PuzzleDifficulty difficulty) {
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
    );
  }
}
