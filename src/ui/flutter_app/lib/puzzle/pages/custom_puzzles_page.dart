// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_puzzles_page.dart
//
// Page for managing user-created custom puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_export_service.dart';
import '../services/puzzle_manager.dart';
import '../widgets/puzzle_card.dart';
import 'puzzle_creation_page.dart';
import 'puzzle_page.dart';

/// Page for managing custom puzzles
class CustomPuzzlesPage extends StatefulWidget {
  const CustomPuzzlesPage({super.key});

  @override
  State<CustomPuzzlesPage> createState() => _CustomPuzzlesPageState();
}

class _CustomPuzzlesPageState extends State<CustomPuzzlesPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();

  // Multi-select mode
  bool _isMultiSelectMode = false;
  final Set<String> _selectedPuzzleIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelectMode
            ? Text(s.puzzleSelectedCount(_selectedPuzzleIds.length))
            : Text(s.customPuzzles),
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: _toggleMultiSelectMode,
              )
            : null,
        actions: <Widget>[
          if (_isMultiSelectMode) ...<Widget>[
            // Select all
            IconButton(
              icon: const Icon(FluentIcons.select_all_on_24_regular),
              onPressed: _selectAllPuzzles,
              tooltip: s.puzzleSelectAll,
            ),
            // Export selected
            if (_selectedPuzzleIds.isNotEmpty)
              IconButton(
                icon: const Icon(FluentIcons.share_24_regular),
                onPressed: _exportSelectedPuzzles,
                tooltip: s.puzzleExport,
              ),
            // Delete selected
            if (_selectedPuzzleIds.isNotEmpty)
              IconButton(
                icon: const Icon(FluentIcons.delete_24_regular),
                onPressed: _deleteSelectedPuzzles,
                tooltip: s.delete,
              ),
          ] else ...<Widget>[
            // Import button
            IconButton(
              icon: const Icon(FluentIcons.arrow_download_24_regular),
              onPressed: _importPuzzles,
              tooltip: s.puzzleImport,
            ),
            // Multi-select button
            IconButton(
              icon: const Icon(FluentIcons.multiselect_24_regular),
              onPressed: _toggleMultiSelectMode,
              tooltip: s.puzzleSelect,
            ),
          ],
        ],
      ),
      floatingActionButton: _isMultiSelectMode
          ? null
          : FloatingActionButton(
              onPressed: _createNewPuzzle,
              tooltip: s.puzzleCreateNew,
              child: const Icon(FluentIcons.add_24_regular),
            ),
      body: ValueListenableBuilder<PuzzleSettings>(
        valueListenable: _puzzleManager.settingsNotifier,
        builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
          final List<PuzzleInfo> customPuzzles = _puzzleManager.getCustomPuzzles();

          if (customPuzzles.isEmpty) {
            return _buildEmptyState(s);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: customPuzzles.length,
            itemBuilder: (BuildContext context, int index) {
              final PuzzleInfo puzzle = customPuzzles[index];
              final PuzzleProgress? progress = settings.getProgress(puzzle.id);
              final bool isSelected = _selectedPuzzleIds.contains(puzzle.id);

              return PuzzleCard(
                puzzle: puzzle,
                progress: progress,
                onTap: _isMultiSelectMode
                    ? () => _togglePuzzleSelection(puzzle.id)
                    : () => _openPuzzle(puzzle),
                onLongPress: _isMultiSelectMode
                    ? null
                    : () {
                        _toggleMultiSelectMode();
                        _togglePuzzleSelection(puzzle.id);
                      },
                isSelected: _isMultiSelectMode ? isSelected : null,
                showCustomBadge: true,
                onEdit: !_isMultiSelectMode ? () => _editPuzzle(puzzle) : null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              FluentIcons.puzzle_piece_24_regular,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              s.noCustomPuzzles,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              s.noCustomPuzzlesHint,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton.icon(
                  onPressed: _createNewPuzzle,
                  icon: const Icon(FluentIcons.add_24_regular),
                  label: Text(s.puzzleCreateNew),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _importPuzzles,
                  icon: const Icon(FluentIcons.arrow_download_24_regular),
                  label: Text(s.puzzleImport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedPuzzleIds.clear();
      }
    });
  }

  void _togglePuzzleSelection(String puzzleId) {
    setState(() {
      if (_selectedPuzzleIds.contains(puzzleId)) {
        _selectedPuzzleIds.remove(puzzleId);
      } else {
        _selectedPuzzleIds.add(puzzleId);
      }
    });
  }

  void _selectAllPuzzles() {
    setState(() {
      _selectedPuzzleIds.clear();
      _selectedPuzzleIds.addAll(
        _puzzleManager.getCustomPuzzles().map((PuzzleInfo p) => p.id),
      );
    });
  }

  Future<void> _exportSelectedPuzzles() async {
    if (_selectedPuzzleIds.isEmpty) return;

    final List<PuzzleInfo> puzzlesToExport = _selectedPuzzleIds
        .map((String id) => _puzzleManager.getPuzzleById(id))
        .whereType<PuzzleInfo>()
        .toList();

    if (puzzlesToExport.isEmpty) return;

    final bool success = await _puzzleManager.exportAndSharePuzzles(
      puzzlesToExport,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? S.of(context).puzzleExportSuccess(puzzlesToExport.length)
              : S.of(context).puzzleExportFailed,
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    if (success) {
      setState(() {
        _isMultiSelectMode = false;
        _selectedPuzzleIds.clear();
      });
    }
  }

  Future<void> _deleteSelectedPuzzles() async {
    if (_selectedPuzzleIds.isEmpty) return;

    // Confirm deletion
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final S s = S.of(context);
        return AlertDialog(
          title: Text(s.confirm),
          content: Text(
            s.puzzleDeleteConfirm(_selectedPuzzleIds.length),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(s.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final int deletedCount = _puzzleManager.deletePuzzles(
      _selectedPuzzleIds.toList(),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).puzzleDeleted(deletedCount)),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _isMultiSelectMode = false;
      _selectedPuzzleIds.clear();
    });
  }

  Future<void> _importPuzzles() async {
    final ImportResult result = await _puzzleManager.importPuzzles();

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.of(context).puzzleImportSuccess(result.puzzles.length),
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? S.of(context).puzzleImportFailed,
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createNewPuzzle() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => const PuzzleCreationPage(),
      ),
    );

    if (created == true) {
      setState(() {});
    }
  }

  Future<void> _editPuzzle(PuzzleInfo puzzle) async {
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => PuzzleCreationPage(
          puzzleToEdit: puzzle,
        ),
      ),
    );

    if (updated == true) {
      setState(() {});
    }
  }

  void _openPuzzle(PuzzleInfo puzzle) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PuzzlePage(puzzle: puzzle),
      ),
    );
  }
}
