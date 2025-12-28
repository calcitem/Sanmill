// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_rush_page.dart
//
// Timed puzzle rush mode - solve as many puzzles as possible

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
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
  // Use ValueNotifiers to avoid rebuilding the entire widget tree
  final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(300);
  int _currentPuzzleIndex = 0;
  final List<PuzzleInfo> _rushPuzzles = <PuzzleInfo>[];
  final ValueNotifier<int> _solvedCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _failedCountNotifier = ValueNotifier<int>(0);
  final int _maxLives = 3;
  final ValueNotifier<int> _livesRemainingNotifier = ValueNotifier<int>(3);

  // Difficulty selection
  PuzzleDifficulty? _selectedDifficulty;

  // Getters for convenience
  int get _remainingSeconds => _remainingSecondsNotifier.value;
  int get _solvedCount => _solvedCountNotifier.value;
  int get _failedCount => _failedCountNotifier.value;
  int get _livesRemaining => _livesRemainingNotifier.value;

  @override
  void dispose() {
    _timer?.cancel();
    _remainingSecondsNotifier.dispose();
    _solvedCountNotifier.dispose();
    _failedCountNotifier.dispose();
    _livesRemainingNotifier.dispose();
    super.dispose();
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

        // Use Builder to ensure the context has the correct theme
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              if (!_isActive) {
                return _buildSetupScreen(context, s, useDarkSettingsUi, settingsTheme);
              } else {
                return _buildRushScreen(context, s, useDarkSettingsUi, settingsTheme);
              }
            },
          ),
        );
      },
    );
  }

  /// Build setup/intro screen
  Widget _buildSetupScreen(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
    ThemeData settingsTheme,
  ) {
    return Scaffold(
      backgroundColor: useDarkSettingsUi
          ? settingsTheme.scaffoldBackgroundColor
          : AppTheme.lightBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.puzzleRush,
          style: useDarkSettingsUi ? null : AppTheme.appBarTheme.titleTextStyle,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header card - use white background for better readability
            Card(
              elevation: 4,
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

            // Start button - use darker red for better text contrast
            ElevatedButton.icon(
              onPressed: _startRush,
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(
                s.puzzleRushStart,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build active rush screen
  Widget _buildRushScreen(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
    ThemeData settingsTheme,
  ) {
    // Check if rush should end (time up, out of lives, or no puzzles)
    if (_remainingSeconds <= 0 ||
        _livesRemaining <= 0 ||
        _currentPuzzleIndex >= _rushPuzzles.length) {
      return _buildResultsScreen(context, s, useDarkSettingsUi, settingsTheme);
    }

    final PuzzleInfo currentPuzzle = _rushPuzzles[_currentPuzzleIndex];

    return Scaffold(
      backgroundColor: useDarkSettingsUi
          ? settingsTheme.scaffoldBackgroundColor
          : AppTheme.lightBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.puzzleRush,
          style: useDarkSettingsUi ? null : AppTheme.appBarTheme.titleTextStyle,
        ),
        leading: IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed: _confirmQuit,
        ),
      ),
      body: Column(
        children: <Widget>[
          // Stats bar - only this part rebuilds when notifiers change
          _RushStatsBar(
            remainingSecondsNotifier: _remainingSecondsNotifier,
            solvedCountNotifier: _solvedCountNotifier,
            livesRemainingNotifier: _livesRemainingNotifier,
            maxLives: _maxLives,
            useDarkSettingsUi: useDarkSettingsUi,
          ),

          // Puzzle - this won't rebuild when timer ticks
          Expanded(
            child: PuzzlePage(
              // Use key to preserve state when puzzle changes
              key: ValueKey<String>(currentPuzzle.id),
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
  Widget _buildResultsScreen(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
    ThemeData settingsTheme,
  ) {
    final bool timeUp = _remainingSeconds <= 0;
    final bool outOfLives = _livesRemaining <= 0;

    return Scaffold(
      backgroundColor: useDarkSettingsUi
          ? settingsTheme.scaffoldBackgroundColor
          : AppTheme.lightBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.puzzleRushResults,
          style: useDarkSettingsUi ? null : AppTheme.appBarTheme.titleTextStyle,
        ),
      ),
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
                    onPressed: () {
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
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

  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        // Wrap label in Expanded to prevent overflow
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
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

  int _calculateAccuracy() {
    final int total = _solvedCount + _failedCount;
    if (total == 0) {
      return 0;
    }
    return ((_solvedCount / total) * 100).round();
  }

  void _startRush() {
    if (!mounted) {
      return;
    }
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
    });

    // Reset notifiers without triggering full page rebuild
    _solvedCountNotifier.value = 0;
    _failedCountNotifier.value = 0;
    _livesRemainingNotifier.value = _maxLives;
    _remainingSecondsNotifier.value = 300;

    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_remainingSecondsNotifier.value <= 0) {
        timer.cancel();
        // Trigger rebuild to show results screen
        if (mounted) {
          setState(() {});
        }
        return;
      }

      // Update only the timer notifier - this won't rebuild the entire page
      _remainingSecondsNotifier.value--;
    });
  }

  void _onPuzzleSolved() {
    // Don't process if time is up or widget unmounted
    if (_remainingSeconds <= 0 || !mounted) {
      return;
    }

    setState(() {
      _currentPuzzleIndex++;
    });
    // Update notifiers separately to avoid unnecessary rebuilds
    _solvedCountNotifier.value++;
  }

  void _onPuzzleFailed() {
    // Don't process if time is up, already out of lives, or widget unmounted
    if (_remainingSeconds <= 0 || _livesRemaining <= 0 || !mounted) {
      return;
    }

    // Update notifiers first
    _failedCountNotifier.value++;
    _livesRemainingNotifier.value--;

    // Then update state if needed to show next puzzle
    if (_livesRemaining > 0) {
      setState(() {
        _currentPuzzleIndex++;
      });
    } else {
      // Trigger rebuild to show results screen
      setState(() {});
    }
  }

  void _confirmQuit() {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final S s = S.of(dialogContext);
        return AlertDialog(
          title: Text(s.confirm),
          content: Text(s.puzzleRushQuitConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(s.quit),
            ),
          ],
        );
      },
    );
  }

  void _resetAndStart() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isActive = false;
    });
    _startRush();
  }
}

/// Separate widget for stats bar that rebuilds independently
/// This prevents the entire page (including the game board) from rebuilding every second
class _RushStatsBar extends StatelessWidget {
  const _RushStatsBar({
    required this.remainingSecondsNotifier,
    required this.solvedCountNotifier,
    required this.livesRemainingNotifier,
    required this.maxLives,
    required this.useDarkSettingsUi,
  });

  final ValueNotifier<int> remainingSecondsNotifier;
  final ValueNotifier<int> solvedCountNotifier;
  final ValueNotifier<int> livesRemainingNotifier;
  final int maxLives;
  final bool useDarkSettingsUi;

  @override
  Widget build(BuildContext context) {
    // Use Card instead of Container for better contrast in both light and dark modes
    return Card(
      margin: EdgeInsets.zero,
      elevation: useDarkSettingsUi ? 0 : 2,
      color: useDarkSettingsUi
          ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          // Timer - rebuilds only when timer notifier changes
          ValueListenableBuilder<int>(
            valueListenable: remainingSecondsNotifier,
            builder:
                (BuildContext context, int remainingSeconds, Widget? child) {
                  return _buildStatItem(
                    _formatTime(remainingSeconds),
                    FluentIcons.timer_24_regular,
                    Colors.red,
                  );
                },
          ),
          // Solved count - rebuilds only when solved count changes
          ValueListenableBuilder<int>(
            valueListenable: solvedCountNotifier,
            builder: (BuildContext context, int solvedCount, Widget? child) {
              return _buildStatItem(
                '$solvedCount',
                FluentIcons.checkmark_circle_24_regular,
                Colors.green,
              );
            },
          ),
          // Lives - rebuilds only when lives change
          ValueListenableBuilder<int>(
            valueListenable: livesRemainingNotifier,
            builder: (BuildContext context, int livesRemaining, Widget? child) {
              return Row(
                children: List<Widget>.generate(
                  maxLives,
                  (int index) => Icon(
                    index < livesRemaining
                        ? FluentIcons.heart_24_filled
                        : FluentIcons.heart_24_regular,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        // Add flexible text to prevent overflow
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
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
}
