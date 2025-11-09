// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_streak_page.dart
//
// Puzzle streak mode - solve as many puzzles as possible without a single mistake

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';
import 'puzzle_page.dart';

/// Puzzle Streak mode - solve puzzles consecutively without errors
class PuzzleStreakPage extends StatefulWidget {
  const PuzzleStreakPage({super.key});

  @override
  State<PuzzleStreakPage> createState() => _PuzzleStreakPageState();
}

class _PuzzleStreakPageState extends State<PuzzleStreakPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();

  // Streak state
  bool _isActive = false;
  int _currentStreak = 0;
  int _bestStreak = 0; // Personal best
  int _currentPuzzleIndex = 0;
  final List<PuzzleInfo> _streakPuzzles = <PuzzleInfo>[];
  bool _failed = false;

  // Stopwatch for tracking time

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    if (!_isActive) {
      return _buildSetupScreen(s);
    } else if (_failed) {
      return _buildResultsScreen(s);
    } else {
      return _buildStreakScreen(s);
    }
  }

  /// Build setup/intro screen
  Widget _buildSetupScreen(S s) {
    return Scaffold(
      appBar: AppBar(title: Text(s.puzzleStreak)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header card
            Card(
              elevation: 4,
              color: Colors.purple.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.flash_24_filled,
                      size: 64,
                      color: Colors.purple,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.puzzleStreak,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.puzzleStreakTagline,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Rules card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.puzzleStreakRules,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRuleItem(
                      s.puzzleStreakRule1,
                      FluentIcons.target_24_regular,
                    ),
                    _buildRuleItem(
                      s.puzzleStreakRule2,
                      FluentIcons.dismiss_circle_24_regular,
                    ),
                    _buildRuleItem(
                      s.puzzleStreakRule3,
                      FluentIcons.trophy_24_regular,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Best streak card
            if (_bestStreak > 0)
              Card(
                color: Colors.amber.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(
                        FluentIcons.trophy_24_filled,
                        color: Colors.amber,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            s.puzzleStreakBest,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '$_bestStreak',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // Start button
            ElevatedButton.icon(
              onPressed: _startStreak,
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(
                s.puzzleStreakStart,
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build active streak screen
  Widget _buildStreakScreen(S s) {
    if (_currentPuzzleIndex >= _streakPuzzles.length) {
      // Need to load more puzzles
      _loadMorePuzzles();
    }

    final PuzzleInfo currentPuzzle = _streakPuzzles[_currentPuzzleIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.puzzleStreak),
        leading: IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed: _confirmQuit,
        ),
      ),
      body: Column(
        children: <Widget>[
          // Stats bar
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.purple.withValues(alpha: 0.2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                // Current streak
                Column(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.flash_24_filled,
                      color: Colors.purple,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_currentStreak',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    Text(
                      s.puzzleStreakCurrent,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                // Divider
                Container(height: 60, width: 1, color: Colors.grey[700]),
                // Best streak
                Column(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.trophy_24_regular,
                      color: Colors.amber,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_bestStreak',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    Text(
                      s.puzzleStreakBest,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Puzzle
          Expanded(
            child: PuzzlePage(
              puzzle: currentPuzzle,
              onSolved: _onPuzzleSolved,
              onFailed: _onPuzzleFailed,
            ),
          ),
        ],
      ),
    );
  }

  /// Build results screen
  Widget _buildResultsScreen(S s) {
    final bool newRecord = _currentStreak > _bestStreak;

    return Scaffold(
      appBar: AppBar(title: Text(s.puzzleStreakResults)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                newRecord
                    ? FluentIcons.trophy_24_filled
                    : FluentIcons.emoji_sad_24_regular,
                size: 80,
                color: newRecord ? Colors.amber : Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                newRecord ? s.puzzleStreakNewRecord : s.puzzleStreakEnded,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            FluentIcons.flash_24_filled,
                            color: Colors.purple,
                            size: 48,
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                s.puzzleStreakFinalScore,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Text(
                                '$_currentStreak',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (newRecord) ...<Widget>[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                FluentIcons.trophy_24_filled,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                s.puzzleStreakNewRecord,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    label: Text(s.close),
                  ),
                  ElevatedButton.icon(
                    onPressed: _resetAndStart,
                    icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
                    label: Text(s.puzzleStreakTryAgain),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleItem(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: Colors.purple),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  void _startStreak() {
    // Get all puzzles and shuffle
    final List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles();
    puzzles.shuffle();

    setState(() {
      _streakPuzzles.clear();
      _streakPuzzles.addAll(puzzles);
      _isActive = true;
      _currentPuzzleIndex = 0;
      _currentStreak = 0;
      _failed = false;
    });
  }

  void _loadMorePuzzles() {
    // If we're running out of puzzles, shuffle and add more
    final List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles();
    puzzles.shuffle();
    setState(() {
      _streakPuzzles.addAll(puzzles);
    });
  }

  void _onPuzzleSolved() {
    // Don't process if already failed
    if (_failed) {
      return;
    }

    setState(() {
      _currentStreak++;
      if (_currentStreak > _bestStreak) {
        _bestStreak = _currentStreak;
      }
      _currentPuzzleIndex++;
    });
  }

  void _onPuzzleFailed() {
    // Don't process if already failed
    if (_failed) {
      return;
    }

    setState(() {
      _failed = true;
    });

    // TODO: Save streak result to database
  }

  void _confirmQuit() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final S s = S.of(context);
        return AlertDialog(
          title: Text(s.confirm),
          content: Text(s.puzzleStreakQuitConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: Text(s.quit),
            ),
          ],
        );
      },
    );
  }

  void _resetAndStart() {
    setState(() {
      _isActive = false;
      _failed = false;
    });
    _startStreak();
  }
}
