// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_rush_page.dart
//
// Timed puzzle rush mode - solve as many puzzles as possible

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';
import 'puzzle_page.dart';

/// Puzzle Rush mode - solve puzzles against the clock
class PuzzleRushPage extends StatefulWidget {
  const PuzzleRushPage({super.key});

  @override
  State<PuzzleRushPage> createState() => _PuzzleRushPageState();
}

class _PuzzleRushPageState extends State<PuzzleRushPage> {
  final PuzzleManager _puzzleManager = PuzzleManager();

  // Rush state
  bool _isActive = false;
  Timer? _timer;
  int _remainingSeconds = 300; // 5 minutes
  int _currentPuzzleIndex = 0;
  final List<PuzzleInfo> _rushPuzzles = <PuzzleInfo>[];
  int _solvedCount = 0;
  int _failedCount = 0;
  final int _maxLives = 3;
  int _livesRemaining = 3;

  // Difficulty selection
  PuzzleDifficulty? _selectedDifficulty;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    if (!_isActive) {
      return _buildSetupScreen(s);
    } else {
      return _buildRushScreen(s);
    }
  }

  /// Build setup/intro screen
  Widget _buildSetupScreen(S s) {
    return Scaffold(
      appBar: AppBar(title: Text(s.puzzleRush)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header card
            Card(
              elevation: 4,
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      FluentIcons.flash_24_regular,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.puzzleRush,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.puzzleRushTagline,
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
                      s.puzzleRushRules,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRuleItem(
                      s.puzzleRushRule1,
                      FluentIcons.timer_24_regular,
                    ),
                    _buildRuleItem(
                      s.puzzleRushRule2,
                      FluentIcons.heart_24_regular,
                    ),
                    _buildRuleItem(
                      s.puzzleRushRule3,
                      FluentIcons.trophy_24_regular,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Difficulty selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.puzzleDifficulty,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _buildDifficultyChip(null, s.all),
                        ...PuzzleDifficulty.values.map(
                          (PuzzleDifficulty diff) => _buildDifficultyChip(
                            diff,
                            diff.displayName(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Start button
            ElevatedButton.icon(
              onPressed: _startRush,
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(
                s.puzzleRushStart,
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build active rush screen
  Widget _buildRushScreen(S s) {
    // Check if rush should end (time up, out of lives, or no puzzles)
    if (_remainingSeconds <= 0 ||
        _livesRemaining <= 0 ||
        _currentPuzzleIndex >= _rushPuzzles.length) {
      return _buildResultsScreen(s);
    }

    final PuzzleInfo currentPuzzle = _rushPuzzles[_currentPuzzleIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.puzzleRush),
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
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                // Timer
                _buildStatItem(
                  _formatTime(_remainingSeconds),
                  FluentIcons.timer_24_regular,
                  Colors.red,
                ),
                // Solved count
                _buildStatItem(
                  '$_solvedCount',
                  FluentIcons.checkmark_circle_24_regular,
                  Colors.green,
                ),
                // Lives
                Row(
                  children: List<Widget>.generate(
                    _maxLives,
                    (int index) => Icon(
                      index < _livesRemaining
                          ? FluentIcons.heart_24_filled
                          : FluentIcons.heart_24_regular,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
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
    final bool timeUp = _remainingSeconds <= 0;
    final bool outOfLives = _livesRemaining <= 0;

    return Scaffold(
      appBar: AppBar(title: Text(s.puzzleRushResults)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                outOfLives
                    ? FluentIcons.emoji_sad_24_regular
                    : FluentIcons.trophy_24_regular,
                size: 80,
                color: outOfLives ? Colors.red : Colors.amber,
              ),
              const SizedBox(height: 24),
              Text(
                timeUp
                    ? s.puzzleRushTimeUp
                    : outOfLives
                    ? s.puzzleRushOutOfLives
                    : s.puzzleRushComplete,
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
                      _buildResultRow(
                        s.puzzleRushSolved,
                        _solvedCount.toString(),
                        Colors.green,
                      ),
                      const Divider(height: 24),
                      _buildResultRow(
                        s.puzzleRushFailed,
                        _failedCount.toString(),
                        Colors.red,
                      ),
                      const Divider(height: 24),
                      _buildResultRow(
                        s.puzzleRushAccuracy,
                        '${_calculateAccuracy()}%',
                        Colors.blue,
                      ),
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
                    label: Text(s.puzzleRushPlayAgain),
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
          Icon(icon, size: 20, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildDifficultyChip(PuzzleDifficulty? difficulty, String label) {
    final bool isSelected = _selectedDifficulty == difficulty;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _selectedDifficulty = difficulty;
        });
      },
    );
  }

  Widget _buildStatItem(String value, IconData icon, Color color) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatTime(int seconds) {
    final int minutes = seconds ~/ 60;
    final int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  int _calculateAccuracy() {
    final int total = _solvedCount + _failedCount;
    if (total == 0) {
      return 0;
    }
    return ((_solvedCount / total) * 100).round();
  }

  void _startRush() {
    // Get puzzles based on difficulty
    List<PuzzleInfo> puzzles;
    if (_selectedDifficulty == null) {
      puzzles = _puzzleManager.getAllPuzzles();
    } else {
      puzzles = _puzzleManager.getPuzzlesByDifficulty(_selectedDifficulty!);
    }

    if (puzzles.isEmpty) {
      return;
    }

    // Shuffle and prepare
    puzzles.shuffle();

    setState(() {
      _rushPuzzles.clear();
      _rushPuzzles.addAll(puzzles);
      _isActive = true;
      _currentPuzzleIndex = 0;
      _solvedCount = 0;
      _failedCount = 0;
      _livesRemaining = _maxLives;
      _remainingSeconds = 300;
    });

    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        // Trigger rebuild to show results screen
        if (mounted) {
          setState(() {});
        }
        return;
      }

      setState(() {
        _remainingSeconds--;
      });
    });
  }

  void _onPuzzleSolved() {
    // Don't process if time is up
    if (_remainingSeconds <= 0) {
      return;
    }

    setState(() {
      _solvedCount++;
      _currentPuzzleIndex++;
    });
  }

  void _onPuzzleFailed() {
    // Don't process if time is up or already out of lives
    if (_remainingSeconds <= 0 || _livesRemaining <= 0) {
      return;
    }

    setState(() {
      _failedCount++;
      _livesRemaining--;
      if (_livesRemaining > 0) {
        _currentPuzzleIndex++;
      }
    });
  }

  void _confirmQuit() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final S s = S.of(context);
        return AlertDialog(
          title: Text(s.confirm),
          content: Text(s.puzzleRushQuitConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () {
                _timer?.cancel();
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
    });
    _startRush();
  }
}
