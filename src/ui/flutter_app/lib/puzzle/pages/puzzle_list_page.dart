// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_list_page.dart
//
// Page displaying the list of available puzzles

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';
import '../widgets/puzzle_card.dart';
import 'puzzle_page.dart';

/// Page showing the list of puzzles
class PuzzleListPage extends StatefulWidget {
  const PuzzleListPage({super.key});

  @override
  State<PuzzleListPage> createState() => _PuzzleListPageState();
}

class _PuzzleListPageState extends State<PuzzleListPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();
  PuzzleDifficulty? _selectedDifficulty;
  PuzzleCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _puzzleManager.init();
  }

  List<PuzzleInfo> get _filteredPuzzles {
    List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles();

    if (_selectedDifficulty != null) {
      puzzles = puzzles
          .where((PuzzleInfo p) => p.difficulty == _selectedDifficulty)
          .toList();
    }

    if (_selectedCategory != null) {
      puzzles = puzzles
          .where((PuzzleInfo p) => p.category == _selectedCategory)
          .toList();
    }

    return puzzles;
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.puzzles),
        actions: <Widget>[
          // Filter button
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          // Stats button
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: _showStatsDialog,
          ),
        ],
      ),
      body: ValueListenableBuilder<PuzzleSettings>(
        valueListenable: _puzzleManager.settingsNotifier,
        builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
          final List<PuzzleInfo> puzzles = _filteredPuzzles;

          if (puzzles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.puzzle, size: 64, color: Colors.grey),
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
              if (_selectedDifficulty != null || _selectedCategory != null)
                _buildFilterChips(s),

              // Puzzle list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: puzzles.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PuzzleInfo puzzle = puzzles[index];
                    final PuzzleProgress? progress =
                        settings.getProgress(puzzle.id);

                    return PuzzleCard(
                      puzzle: puzzle,
                      progress: progress,
                      onTap: () => _openPuzzle(puzzle),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChips(S s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Wrap(
        spacing: 8.0,
        children: <Widget>[
          if (_selectedDifficulty != null)
            Chip(
              label: Text(_selectedDifficulty!.getDisplayName(S.of, context)),
              onDeleted: () => setState(() => _selectedDifficulty = null),
            ),
          if (_selectedCategory != null)
            Chip(
              label: Text(_selectedCategory!.getDisplayName(S.of, context)),
              onDeleted: () => setState(() => _selectedCategory = null),
            ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(s.filter),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.difficulty, style: Theme.of(context).textTheme.titleSmall),
                ...PuzzleDifficulty.values.map(
                  (PuzzleDifficulty d) => RadioListTile<PuzzleDifficulty>(
                    title: Text(d.getDisplayName(S.of, context)),
                    value: d,
                    groupValue: _selectedDifficulty,
                    onChanged: (PuzzleDifficulty? value) {
                      setState(() => _selectedDifficulty = value);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const Divider(),
                Text(s.category, style: Theme.of(context).textTheme.titleSmall),
                ...PuzzleCategory.values.map(
                  (PuzzleCategory c) => RadioListTile<PuzzleCategory>(
                    title: Text(c.getDisplayName(S.of, context)),
                    value: c,
                    groupValue: _selectedCategory,
                    onChanged: (PuzzleCategory? value) {
                      setState(() => _selectedCategory = value);
                      Navigator.of(context).pop();
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
                  _selectedDifficulty = null;
                  _selectedCategory = null;
                });
                Navigator.of(context).pop();
              },
              child: Text(s.clearFilter),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.close),
            ),
          ],
        );
      },
    );
  }

  void _showStatsDialog() {
    final S s = S.of(context);
    final Map<String, dynamic> stats = _puzzleManager.getStatistics();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(s.puzzleStatistics),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildStatRow(
                s.totalPuzzles,
                stats['totalPuzzles'].toString(),
              ),
              _buildStatRow(
                s.completed,
                stats['completedPuzzles'].toString(),
              ),
              _buildStatRow(
                s.totalStars,
                stats['totalStars'].toString(),
              ),
              _buildStatRow(
                s.completionPercentage,
                '${stats['completionPercentage'].toStringAsFixed(1)}%',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.close),
            ),
          ],
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
}
