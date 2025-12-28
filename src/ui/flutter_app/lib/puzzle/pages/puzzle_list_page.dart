// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_list_page.dart
//
// Page displaying the list of available puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_export_service.dart';
import '../services/puzzle_manager.dart';
import '../widgets/puzzle_card.dart';
import 'puzzle_creation_page.dart';
import 'puzzle_page.dart';

/// Page showing the list of puzzles
class PuzzleListPage extends StatefulWidget {
  const PuzzleListPage({super.key});

  @override
  State<PuzzleListPage> createState() => _PuzzleListPageState();
}

class _PuzzleListPageState extends State<PuzzleListPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();
  // Multi-select filters
  final Set<PuzzleDifficulty> _selectedDifficulties = <PuzzleDifficulty>{};
  final Set<PuzzleCategory> _selectedCategories = <PuzzleCategory>{};

  // Multi-select mode
  bool _isMultiSelectMode = false;
  final Set<String> _selectedPuzzleIds = <String>{};

  @override
  void initState() {
    super.initState();
    _puzzleManager.init();
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

  List<PuzzleInfo> get _filteredPuzzles {
    List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles();

    // Filter by difficulty (multiple selection)
    if (_selectedDifficulties.isNotEmpty) {
      puzzles = puzzles
          .where((PuzzleInfo p) => _selectedDifficulties.contains(p.difficulty))
          .toList();
    }

    // Filter by category (multiple selection)
    if (_selectedCategories.isNotEmpty) {
      puzzles = puzzles
          .where((PuzzleInfo p) => _selectedCategories.contains(p.category))
          .toList();
    }

    return puzzles;
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

        // Use Builder to ensure the context has the correct theme.
        // This prevents computing text styles from a context outside the Theme wrapper.
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                backgroundColor: useDarkSettingsUi
                    ? settingsTheme.scaffoldBackgroundColor
                    : AppTheme.lightBackgroundColor,
                appBar: AppBar(
                  title: _isMultiSelectMode
                      ? Text(
                          s.puzzleSelectedCount(_selectedPuzzleIds.length),
                          style: useDarkSettingsUi
                              ? null
                              : AppTheme.appBarTheme.titleTextStyle,
                        )
                      : Text(
                          s.puzzles,
                          style: useDarkSettingsUi
                              ? null
                              : AppTheme.appBarTheme.titleTextStyle,
                        ),
                  leading: _isMultiSelectMode
                      ? IconButton(
                          icon: const Icon(Icons.close),
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
                      // Delete selected (only custom puzzles)
                      if (_canDeleteSelected)
                        IconButton(
                          icon: const Icon(FluentIcons.delete_24_regular),
                          onPressed: () => _deleteSelectedPuzzles(
                            context,
                            settingsTheme,
                          ),
                          tooltip: s.delete,
                        ),
                    ] else ...<Widget>[
                      // Import button (open file to import puzzles)
                      IconButton(
                        icon: const Icon(FluentIcons.folder_open_24_regular),
                        onPressed: _importPuzzles,
                        tooltip: s.puzzleImport,
                      ),
                      // Multi-select button
                      IconButton(
                        icon: const Icon(FluentIcons.checkbox_checked_24_regular),
                        onPressed: _toggleMultiSelectMode,
                        tooltip: s.puzzleSelect,
                      ),
                      // Filter button
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: () => _showFilterDialog(
                          context,
                          settingsTheme,
                        ),
                      ),
                      // Stats button
                      IconButton(
                        icon: const Icon(Icons.bar_chart),
                        onPressed: () => _showStatsDialog(
                          context,
                          settingsTheme,
                        ),
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
                  builder: (BuildContext context, PuzzleSettings settings, _) {
                    final List<PuzzleInfo> puzzles = _filteredPuzzles;

                    if (puzzles.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              FluentIcons.puzzle_piece_24_regular,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              s.noPuzzlesAvailable,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: <Widget>[
                        // Filter chips
                        if (_selectedDifficulties.isNotEmpty ||
                            _selectedCategories.isNotEmpty)
                          _buildFilterChips(context, s),

                        // Puzzle list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8.0),
                            itemCount: puzzles.length,
                            itemBuilder: (BuildContext context, int index) {
                              final PuzzleInfo puzzle = puzzles[index];
                              final PuzzleProgress? progress =
                                  settings.getProgress(puzzle.id);
                              final bool isSelected =
                                  _selectedPuzzleIds.contains(puzzle.id);

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
                                isSelected: _isMultiSelectMode
                                    ? isSelected
                                    : null,
                                showCustomBadge: puzzle.isCustom,
                                onEdit: puzzle.isCustom && !_isMultiSelectMode
                                    ? () => _editPuzzle(puzzle)
                                    : null,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFilterChips(BuildContext context, S s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        children: <Widget>[
          // Difficulty filter chips
          ..._selectedDifficulties.map(
            (PuzzleDifficulty d) => Chip(
              label: Text(d.getDisplayName(S.of, context)),
              onDeleted: () => setState(() => _selectedDifficulties.remove(d)),
              deleteIcon: const Icon(Icons.close, size: 18),
            ),
          ),
          // Category filter chips
          ..._selectedCategories.map(
            (PuzzleCategory c) => Chip(
              label: Text(c.getDisplayName(S.of, context)),
              onDeleted: () => setState(() => _selectedCategories.remove(c)),
              deleteIcon: const Icon(Icons.close, size: 18),
            ),
          ),
          // Clear all filters chip
          if (_selectedDifficulties.isNotEmpty ||
              _selectedCategories.isNotEmpty)
            ActionChip(
              label: Text(s.clearFilter),
              avatar: const Icon(Icons.clear_all, size: 18),
              onPressed: () {
                setState(() {
                  _selectedDifficulties.clear();
                  _selectedCategories.clear();
                });
              },
            ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context, ThemeData settingsTheme) {
    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: settingsTheme,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return AlertDialog(
                title: Text(s.filter),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.difficulty,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...PuzzleDifficulty.values.map(
                        (PuzzleDifficulty d) => CheckboxListTile(
                          title: Text(d.getDisplayName(S.of, context)),
                          value: _selectedDifficulties.contains(d),
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked ?? false) {
                                _selectedDifficulties.add(d);
                              } else {
                                _selectedDifficulties.remove(d);
                              }
                            });
                            setDialogState(() {}); // Update dialog state
                          },
                        ),
                      ),
                      const Divider(),
                      Text(
                        s.category,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...PuzzleCategory.values.map(
                        (PuzzleCategory c) => CheckboxListTile(
                          title: Text(c.getDisplayName(S.of, context)),
                          value: _selectedCategories.contains(c),
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked ?? false) {
                                _selectedCategories.add(c);
                              } else {
                                _selectedCategories.remove(c);
                              }
                            });
                            setDialogState(() {}); // Update dialog state
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedDifficulties.clear();
                        _selectedCategories.clear();
                      });
                      setDialogState(() {}); // Update dialog state
                    },
                    child: Text(s.clearFilter),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(s.close),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showStatsDialog(BuildContext context, ThemeData settingsTheme) {
    final S s = S.of(context);
    final Map<String, dynamic> stats = _puzzleManager.getStatistics();

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: settingsTheme,
          child: AlertDialog(
            title: Text(s.puzzleStatistics),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildStatRow(
                  s.totalPuzzles,
                  (stats['totalPuzzles'] as int? ?? 0).toString(),
                ),
                _buildStatRow(
                  s.completed,
                  (stats['completedPuzzles'] as int? ?? 0).toString(),
                ),
                _buildStatRow(
                  s.totalStars,
                  (stats['totalStars'] as int? ?? 0).toString(),
                ),
                _buildStatRow(
                  s.completionPercentage,
                  '${(stats['completionPercentage'] as num? ?? 0.0).toStringAsFixed(1)}%',
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(s.close),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _openPuzzle(PuzzleInfo puzzle) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PuzzlePage(puzzle: puzzle),
      ),
    );
  }

  /// Check if any selected puzzle can be deleted
  bool get _canDeleteSelected {
    return _selectedPuzzleIds.any((String id) {
      final PuzzleInfo? puzzle = _puzzleManager.getPuzzleById(id);
      return puzzle != null && puzzle.isCustom;
    });
  }

  /// Select all visible puzzles
  void _selectAllPuzzles() {
    setState(() {
      _selectedPuzzleIds.clear();
      _selectedPuzzleIds.addAll(_filteredPuzzles.map((PuzzleInfo p) => p.id));
    });
  }

  /// Export selected puzzles
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

  /// Delete selected puzzles
  Future<void> _deleteSelectedPuzzles(
    BuildContext context,
    ThemeData settingsTheme,
  ) async {
    if (_selectedPuzzleIds.isEmpty) {
      return;
    }

    // Filter to only custom puzzles
    final List<String> customPuzzleIds = _selectedPuzzleIds.where((String id) {
      final PuzzleInfo? puzzle = _puzzleManager.getPuzzleById(id);
      return puzzle != null && puzzle.isCustom;
    }).toList();

    if (customPuzzleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).puzzleCannotDeleteBuiltIn),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Confirm deletion
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: settingsTheme,
          child: AlertDialog(
            title: Text(S.of(dialogContext).confirm),
            content: Text(
              S.of(dialogContext).puzzleDeleteConfirm(customPuzzleIds.length),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(S.of(dialogContext).cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(S.of(dialogContext).delete),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final int deletedCount = _puzzleManager.deletePuzzles(customPuzzleIds);

    if (!mounted || !context.mounted) {
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

  /// Import puzzles from file
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

  /// Create a new puzzle
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

  /// Edit an existing custom puzzle
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
}
