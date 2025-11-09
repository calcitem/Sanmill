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
            // Contribute selected
            if (_selectedPuzzleIds.isNotEmpty)
              IconButton(
                icon: const Icon(FluentIcons.arrow_upload_24_regular),
                onPressed: _contributeSelectedPuzzles,
                tooltip: 'Contribute to Sanmill',
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
            // Contribution info button
            IconButton(
              icon: const Icon(FluentIcons.info_24_regular),
              onPressed: _showContributionInfo,
              tooltip: 'How to Contribute',
            ),
            // Multi-select button
            IconButton(
              icon: const Icon(FluentIcons.checkbox_checked_24_regular),
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
        builder:
            (BuildContext context, PuzzleSettings settings, Widget? child) {
              final List<PuzzleInfo> customPuzzles = _puzzleManager
                  .getCustomPuzzles();

              if (customPuzzles.isEmpty) {
                return _buildEmptyState(s);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: customPuzzles.length,
                itemBuilder: (BuildContext context, int index) {
                  final PuzzleInfo puzzle = customPuzzles[index];
                  final PuzzleProgress? progress = settings.getProgress(
                    puzzle.id,
                  );
                  final bool isSelected = _selectedPuzzleIds.contains(
                    puzzle.id,
                  );

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
                    onEdit: !_isMultiSelectMode
                        ? () => _editPuzzle(puzzle)
                        : null,
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
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    final List<PuzzleInfo> puzzlesToExport = _selectedPuzzleIds
        .map((String id) => _puzzleManager.getPuzzleById(id))
        .whereType<PuzzleInfo>()
        .toList();

    if (puzzlesToExport.isEmpty) {
      return;
    }

    final bool success = await _puzzleManager.exportAndSharePuzzles(
      puzzlesToExport,
    );

    if (!mounted) {
      return;
    }

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
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    // Confirm deletion
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final S s = S.of(context);
        return AlertDialog(
          title: Text(s.confirm),
          content: Text(s.puzzleDeleteConfirm(_selectedPuzzleIds.length)),
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

    if (confirmed != true) {
      return;
    }

    final int deletedCount = _puzzleManager.deletePuzzles(
      _selectedPuzzleIds.toList(),
    );

    if (!mounted) {
      return;
    }

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

    if (!mounted) {
      return;
    }

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

    if (created ?? false) {
      setState(() {});
    }
  }

  Future<void> _editPuzzle(PuzzleInfo puzzle) async {
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            PuzzleCreationPage(puzzleToEdit: puzzle),
      ),
    );

    if (updated ?? false) {
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

  Future<void> _contributeSelectedPuzzles() async {
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    final List<PuzzleInfo> puzzlesToContribute = _selectedPuzzleIds
        .map((String id) => _puzzleManager.getPuzzleById(id))
        .whereType<PuzzleInfo>()
        .toList();

    if (puzzlesToContribute.isEmpty) {
      return;
    }

    // Validate puzzles before contribution
    final List<String> invalidPuzzles = <String>[];
    for (final PuzzleInfo puzzle in puzzlesToContribute) {
      final String? error = PuzzleExportService.validateForContribution(puzzle);
      if (error != null) {
        invalidPuzzles.add('${puzzle.title}: $error');
      }
    }

    // If there are validation errors, show them
    if (invalidPuzzles.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Validation Errors'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'The following puzzles need to be fixed before contributing:',
                  ),
                  const SizedBox(height: 12),
                  ...invalidPuzzles.map(
                    (String error) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(error),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Show contribution info dialog before exporting
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Contribute Puzzles to Sanmill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'You are about to export ${puzzlesToContribute.length} puzzle(s) for contribution.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('What happens next:'),
                const SizedBox(height: 8),
                const Text('1. Your puzzles will be exported to a JSON file'),
                const Text('2. You can share this file via the share dialog'),
                const Text(
                  '3. Submit via GitHub, email, or GitHub issue (see guide)',
                ),
                const Text('4. Puzzles will be reviewed by maintainers'),
                const Text('5. Once approved, they become built-in puzzles!'),
                const SizedBox(height: 16),
                const Text(
                  'By contributing, you agree to license your puzzles under GPL-3.0-or-later.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(FluentIcons.arrow_upload_24_regular),
              label: const Text('Export for Contribution'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    // Export puzzles in contribution format
    final bool success = puzzlesToContribute.length == 1
        ? await PuzzleExportService.shareForContribution(
            puzzlesToContribute.first,
          )
        : await PuzzleExportService.shareMultipleForContribution(
            puzzlesToContribute,
          );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Exported ${puzzlesToContribute.length} puzzle(s) for contribution!'
              : 'Failed to export puzzles',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        action: success
            ? SnackBarAction(
                label: 'View Guide',
                textColor: Colors.white,
                onPressed: _showContributionInfo,
              )
            : null,
      ),
    );

    if (success) {
      setState(() {
        _isMultiSelectMode = false;
        _selectedPuzzleIds.clear();
      });
    }
  }

  void _showContributionInfo() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(FluentIcons.info_24_regular, color: Colors.blue),
              SizedBox(width: 12),
              Text('How to Contribute Puzzles'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Help make Sanmill better by contributing your puzzles!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Quick Start:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _buildInfoStep(
                  '1',
                  'Create Quality Puzzles',
                  'Ensure your puzzle has a clear solution, good metadata, and teaches something valuable.',
                ),
                const SizedBox(height: 8),
                _buildInfoStep(
                  '2',
                  'Add Your Name',
                  'Edit your puzzle and add your name as the author to get credit.',
                ),
                const SizedBox(height: 8),
                _buildInfoStep(
                  '3',
                  'Export for Contribution',
                  'Select your puzzles and tap the upload icon to export in the correct format.',
                ),
                const SizedBox(height: 8),
                _buildInfoStep(
                  '4',
                  'Submit',
                  'Share the exported file via GitHub Pull Request, Issue, or email.',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            FluentIcons.document_24_regular,
                            size: 16,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Full Documentation',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        'See PUZZLE_CONTRIBUTION_GUIDE.md in the repository for complete instructions, quality guidelines, and submission options.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Quality Requirements:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '✓ Clear, unique solution',
                  style: TextStyle(fontSize: 13),
                ),
                const Text(
                  '✓ Complete metadata (title, description, etc.)',
                  style: TextStyle(fontSize: 13),
                ),
                const Text(
                  '✓ Author attribution',
                  style: TextStyle(fontSize: 13),
                ),
                const Text(
                  '✓ Accurate difficulty rating',
                  style: TextStyle(fontSize: 13),
                ),
                const Text(
                  '✓ Instructive or entertaining',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _toggleMultiSelectMode();
              },
              child: const Text('Start Contributing'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12),
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
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
