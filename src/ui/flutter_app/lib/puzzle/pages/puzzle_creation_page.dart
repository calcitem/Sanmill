// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_creation_page.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../game_page/services/controller.dart';
import '../../game_page/services/engine/engine.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';

/// Page for creating custom puzzles
class PuzzleCreationPage extends StatefulWidget {
  const PuzzleCreationPage({
    super.key,
    this.puzzleToEdit,
  });

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
    // Note: Can't reload solution moves into the game board
  }

  /// Capture the current board position as the puzzle starting position
  void _capturePosition() {
    final GameController controller = GameController();
    final String fen = controller.position.fen;

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
    _moveCountBeforeRecording = controller.recorder.movesMainLine.length;

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

    logger.i("$_tag Started recording solution moves");
  }

  /// Stop recording solution moves
  void _stopRecordingSolution() {
    final GameController controller = GameController();
    final List<ExtMove> allMoves = controller.recorder.movesMainLine;

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

    logger.i("$_tag Stopped recording, captured ${_solutionMoves.length} moves");
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
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
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
      if (!mounted) return;

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
      if (!mounted) return;

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
          _isEditing
              ? S.of(context).puzzleEdit
              : S.of(context).puzzleCreateNew,
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
      color: AppTheme.puzzleCardColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(FluentIcons.info_24_regular, size: 20),
                const SizedBox(width: 8),
                Text(
                  S.of(context).puzzleCreationInstructions,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).puzzleCreationSteps,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[300],
              ),
            ),
          ],
        ),
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
            Text(
              S.of(context).puzzleSetupPosition,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (_capturedPosition != null) ...<Widget>[
              Text(
                S.of(context).puzzlePositionCaptured,
                style: TextStyle(color: Colors.green[300], fontSize: 14),
              ),
              const SizedBox(height: 4),
              SelectableText(
                _capturedPosition!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ] else
              Text(
                S.of(context).puzzleNoPositionCaptured,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            const SizedBox(height: 12),
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
            Text(
              S.of(context).puzzleRecordSolution,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (_solutionMoves.isNotEmpty) ...<Widget>[
              Text(
                S.of(context).puzzleSolutionMoves(_solutionMoves.length),
                style: TextStyle(color: Colors.green[300], fontSize: 14),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _solutionMoves.asMap().entries.map((MapEntry<int, String> entry) {
                  return Chip(
                    label: Text(
                      '${entry.key + 1}. ${entry.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.blue[700],
                  );
                }).toList(),
              ),
            ] else
              Text(
                S.of(context).puzzleNoSolutionRecorded,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            const SizedBox(height: 12),
            if (_isRecordingSolution)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(FluentIcons.record_24_regular, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).puzzleRecording,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _stopRecordingSolution,
                    icon: const Icon(FluentIcons.stop_24_regular),
                    label: Text(S.of(context).puzzleStopRecording),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
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

  Widget _buildMetadataSection() {
    return Card(
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
                prefixIcon: const Icon(FluentIcons.text_24_regular),
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
              value: _selectedCategory,
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
              value: _selectedDifficulty,
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
                labelText: '${S.of(context).puzzleHint} (${S.of(context).optional})',
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
                labelText: '${S.of(context).puzzleTags} (${S.of(context).optional})',
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
                labelText: '${S.of(context).puzzleAuthor} (${S.of(context).optional})',
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
