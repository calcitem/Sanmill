// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_streak_page.dart
//
// Puzzle streak mode - solve as many puzzles as possible without a single mistake

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
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
  int _bestStreak = 0; // Personal best (persisted across sessions)
  int _currentPuzzleIndex = 0;
  final List<PuzzleInfo> _streakPuzzles = <PuzzleInfo>[];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadBestStreak();
  }

  @override
  void dispose() {
    // Persist any active streak so it is not lost when the page is popped
    // without going through the normal quit / failure flow (e.g. system back).
    if (_isActive && _currentStreak > 0 && !_failed) {
      _saveStreakResult();
    }
    super.dispose();
  }

  /// Load the all-time best streak from persisted history.
  void _loadBestStreak() {
    try {
      final dynamic data = DB().puzzleAnalyticsBox.get('puzzleStreakHistory');
      if (data == null) {
        return;
      }
      final List<dynamic> history = data as List<dynamic>;
      int best = 0;
      for (final dynamic entry in history) {
        final int streak =
            (entry as Map<dynamic, dynamic>)['streak'] as int? ?? 0;
        if (streak > best) {
          best = streak;
        }
      }
      setState(() {
        _bestStreak = best;
      });
    } catch (e) {
      logger.e('[PuzzleStreakPage] Failed to load best streak: $e');
    }
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
                return _buildSetupScreen(
                  context,
                  s,
                  useDarkSettingsUi,
                  settingsTheme,
                );
              } else if (_failed) {
                return _buildResultsScreen(
                  context,
                  s,
                  useDarkSettingsUi,
                  settingsTheme,
                );
              } else {
                return _buildStreakScreen(
                  context,
                  s,
                  useDarkSettingsUi,
                  settingsTheme,
                );
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
          s.puzzleStreak,
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

            // Best streak card - use white background for better text readability
            if (_bestStreak > 0)
              Card(
                elevation: 2,
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

            // Start button - use darker purple for better text contrast
            ElevatedButton.icon(
              onPressed: _startStreak,
              icon: const Icon(FluentIcons.play_24_regular),
              label: Text(
                s.puzzleStreakStart,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build active streak screen
  Widget _buildStreakScreen(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
    ThemeData settingsTheme,
  ) {
    if (_streakPuzzles.isEmpty) {
      return _buildSetupScreen(context, s, useDarkSettingsUi, settingsTheme);
    }
    if (_currentPuzzleIndex >= _streakPuzzles.length) {
      // Need to load more puzzles
      _loadMorePuzzles();
    }
    if (_currentPuzzleIndex >= _streakPuzzles.length) {
      return _buildSetupScreen(context, s, useDarkSettingsUi, settingsTheme);
    }

    final PuzzleInfo currentPuzzle = _streakPuzzles[_currentPuzzleIndex];

    return Scaffold(
      backgroundColor: useDarkSettingsUi
          ? settingsTheme.scaffoldBackgroundColor
          : AppTheme.lightBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.puzzleStreak,
          style: useDarkSettingsUi ? null : AppTheme.appBarTheme.titleTextStyle,
        ),
        leading: IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular),
          onPressed: _confirmQuit,
        ),
      ),
      body: Column(
        children: <Widget>[
          // Stats bar - use Card for better contrast in light mode
          Card(
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
                  // Divider - use theme color for better contrast in both modes
                  Container(
                    height: 60,
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
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
  Widget _buildResultsScreen(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
    ThemeData settingsTheme,
  ) {
    final bool newRecord = _currentStreak > _bestStreak;

    return Scaffold(
      backgroundColor: useDarkSettingsUi
          ? settingsTheme.scaffoldBackgroundColor
          : AppTheme.lightBackgroundColor,
      appBar: AppBar(
        title: Text(
          s.puzzleStreakResults,
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
                    icon: const Icon(
                      FluentIcons.arrow_clockwise_24_regular,
                      color: Colors.white,
                    ),
                    label: Text(
                      s.puzzleStreakTryAgain,
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
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
    if (!mounted) {
      return;
    }
    // Get all puzzles and shuffle
    final List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles().toList();
    if (puzzles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).noPuzzlesAvailable)));
      return;
    }
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
    if (!mounted) {
      return;
    }
    // If we're running out of puzzles, shuffle and add more
    final List<PuzzleInfo> puzzles = _puzzleManager.getAllPuzzles().toList();
    if (puzzles.isEmpty) {
      return;
    }
    puzzles.shuffle();
    setState(() {
      _streakPuzzles.addAll(puzzles);
    });
  }

  void _onPuzzleSolved() {
    // Don't process if already failed or widget unmounted
    if (_failed || !mounted) {
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
    // Don't process if already failed or widget unmounted
    if (_failed || !mounted) {
      return;
    }

    setState(() {
      _failed = true;
    });

    // Save streak result to database
    _saveStreakResult();
  }

  Future<void> _saveStreakResult() async {
    if (_currentStreak == 0) {
      return; // No streak to save
    }

    try {
      // Load existing streak history
      final dynamic data = DB().puzzleAnalyticsBox.get('puzzleStreakHistory');
      final List<Map<String, dynamic>> history = data != null
          ? List<Map<String, dynamic>>.from(
              (data as List<dynamic>).map(
                (dynamic e) =>
                    Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
          : <Map<String, dynamic>>[];

      // Add current streak result
      history.add(<String, dynamic>{
        'streak': _currentStreak,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Keep only the last 100 streak results
      if (history.length > 100) {
        history.removeRange(0, history.length - 100);
      }

      // Save to database
      await DB().puzzleAnalyticsBox.put('puzzleStreakHistory', history);

      logger.i('[PuzzleStreakPage] Saved streak result: $_currentStreak');
    } catch (e) {
      logger.e('[PuzzleStreakPage] Failed to save streak result: $e');
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
          content: Text(s.puzzleStreakQuitConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.cancel),
            ),
            TextButton(
              onPressed: () {
                // Persist the streak before leaving so it is not lost.
                _saveStreakResult();
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
      _failed = false;
    });
    _startStreak();
  }
}
