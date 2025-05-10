// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// statistics_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../statistics/model/stats_settings.dart';
import '../services/stats_service.dart';

/// A widget to display game statistics and ratings
class StatisticsPage extends StatelessWidget {
  /// Creates a statistics page
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      key: const Key('statistics_page_block_semantics'),
      child: Scaffold(
        key: const Key('statistics_page_scaffold'),
        appBar: AppBar(
          key: const Key('statistics_page_app_bar'),
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).statistics,
            key: const Key('statistics_page_app_bar_title'),
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        backgroundColor: AppTheme.lightBackgroundColor,
        body: ValueListenableBuilder<dynamic>(
          key: const Key('statistics_page_value_listenable_builder'),
          valueListenable: DB().listenStatsSettings,
          builder: (BuildContext context, _, __) {
            final StatsSettings settings = DB().statsSettings;
            return SettingsList(
              key: const Key('statistics_page_settings_list'),
              children: <Widget>[
                _buildHumanStatsCard(context, settings.humanStats),
                _buildAiDifficultyStatsCard(context, settings),
                _buildStatsSettingsCard(context, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsSettingsCard(BuildContext context, StatsSettings settings) {
    final S l10n = S.of(context);

    return SettingsCard(
      key: const Key('statistics_page_settings_card'),
      title: Text(
        l10n.settings,
        key: const Key('statistics_page_settings_card_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key('statistics_page_enable_statistics_switch'),
          value: settings.isStatsEnabled,
          onChanged: (bool value) {
            DB().statsSettings = settings.copyWith(
              isStatsEnabled: value,
            );
          },
          titleString: 'Enable statistics', // TODO: Add localization string
          subtitleString:
              'When enabled, game results will be recorded in statistics. However, games involving take-backs or those not played continuously from start to finish will not be recorded. When disabled, statistics collection is paused.',
          // TODO: Add localization string
        ),

        // Reset statistics button
        ListTile(
          key: const Key('statistics_page_reset_statistics'),
          title: Text(
            'Reset statistics', // TODO: Add localization string
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          trailing: Icon(
            Icons.refresh,
            color: Theme.of(context).colorScheme.error,
          ),
          onTap: () => _showResetStatsConfirmationDialog(context),
        ),
      ],
    );
  }

  // Show confirmation dialog before resetting statistics
  void _showResetStatsConfirmationDialog(BuildContext context) {
    final S l10n = S.of(context);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title:
              const Text('Reset statistics'), // TODO: Add localization string
          content: const Text(
            'This will reset all game statistics (wins, losses, draws) but preserve ratings. This action cannot be undone.',
            // TODO: Add localization string
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                _resetStats();
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Reset'), // TODO: Add localization string
            ),
          ],
        );
      },
    );
  }

  // Reset all game statistics while preserving ratings
  void _resetStats() {
    final StatsSettings statsSettings = DB().statsSettings;

    // Reset human player statistics
    final PlayerStats resetHumanStats = PlayerStats(
      lastUpdated: DateTime.now(),
      // All statistics are reset to 0
    );

    // Create new settings with reset human rating
    final StatsSettings newStatsSettings = statsSettings.copyWith(
      humanStats: resetHumanStats,
      // Create a new empty map for AI ratings
      aiDifficultyStatsMap: <int, PlayerStats>{},
    );

    // Update the database
    DB().statsSettings = newStatsSettings;

    // Show success message
    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      'Statistics have been reset successfully',
    );
  }

  Widget _buildHumanStatsCard(BuildContext context, PlayerStats humanStats) {
    final S l10n = S.of(context);
    final DateFormat dateFormat = DateFormat.yMd().add_Hm();
    final ThemeData theme = Theme.of(context);

    return SettingsCard(
      key: const Key('statistics_page_human_rating_card'),
      title: Text(
        l10n.yourRating,
        key: const Key('statistics_page_human_rating_card_title'),
      ),
      children: <Widget>[
        // Central large rating display
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Center(
            child: Text(
              '${humanStats.rating}',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: _getRatingColor(context, humanStats.rating),
                  ),
            ),
          ),
        ),

        // Wins/Draws/Losses in table format with large text
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              // Header row
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                children: <Widget>[
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          l10n.wins,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          l10n.draws,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          l10n.losses,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Values row with large text
              TableRow(
                children: <Widget>[
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          '${humanStats.wins}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          '${humanStats.draws}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          '${humanStats.losses}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Percentage table showing win/draw/loss rates
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              // Header row
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                children: <Widget>[
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Win rate', // Win rate
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Draw rate', // Draw rate
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Loss rate', // Loss rate
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Values row with percentage
              TableRow(
                children: <Widget>[
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          humanStats.gamesPlayed > 0
                              ? '${(humanStats.wins / humanStats.gamesPlayed * 100).toStringAsFixed(1)}%'
                              : '0.0%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          humanStats.gamesPlayed > 0
                              ? '${(humanStats.draws / humanStats.gamesPlayed * 100).toStringAsFixed(1)}%'
                              : '0.0%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Center(
                        child: Text(
                          humanStats.gamesPlayed > 0
                              ? '${(humanStats.losses / humanStats.gamesPlayed * 100).toStringAsFixed(1)}%'
                              : '0.0%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Games Played and Last Updated as separate items
        Column(
          children: <Widget>[
            ListTile(
              title: Text(l10n.gamesPlayed),
              trailing: Text(
                humanStats.gamesPlayed.toString(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              title: Text(l10n.lastUpdated),
              trailing: Text(
                humanStats.lastUpdated != null
                    ? dateFormat.format(humanStats.lastUpdated!)
                    : l10n.never,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiDifficultyStatsCard(
      BuildContext context, StatsSettings settings) {
    final S l10n = S.of(context);
    final ThemeData theme = Theme.of(context);

    // Define monospace text style for statistics
    const TextStyle monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    return SettingsCard(
      key: const Key('statistics_page_ai_statistics_card'),
      title: const Text(
        'AI Statistics', // TODO: Add localization string for AI Statistics
        key: Key('statistics_page_ai_statistics_card_title'),
      ),
      children: <Widget>[
        // DataTable for AI statistics
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: const <DataColumn>[
              DataColumn(
                label: Center(child: Text('🎚️')), // Difficulty Level
                numeric: true,
              ),
              DataColumn(
                label: Center(child: Text('⭐')), // Rating
                numeric: true,
              ),
              DataColumn(label: Center(child: Text('🔢'))), // Total
              DataColumn(label: Center(child: Text('⚪'))), // White
              DataColumn(label: Center(child: Text('⚫'))), // Black
            ],
            rows: List<DataRow>.generate(
              30, // Display levels 1-30
              (int index) {
                final int level = index + 1; // Levels start from 1
                // Get the Statistics object for statistics (games played, wins, losses, draws, etc.)
                final PlayerStats aiLvlStats =
                    settings.getAiDifficultyStats(level);

                // Get the actual fixed ELO rating for this AI level for display
                final int fixedAiEloRating =
                    EloRatingService.getFixedAiEloRating(level);

                // Format: W/D/L (Wins/Draws/Losses)
                final String totalStats =
                    '${aiLvlStats.wins}/${aiLvlStats.draws}/${aiLvlStats.losses}';

                // White stats: W/D/L format
                final String whiteStats = aiLvlStats.whiteGamesPlayed > 0
                    ? '${aiLvlStats.whiteWins}/${aiLvlStats.whiteDraws}/${aiLvlStats.whiteLosses}'
                    : '0/0/0';

                // Black stats: W/D/L format
                final String blackStats = aiLvlStats.blackGamesPlayed > 0
                    ? '${aiLvlStats.blackWins}/${aiLvlStats.blackDraws}/${aiLvlStats.blackLosses}'
                    : '0/0/0';

                return DataRow(
                  cells: <DataCell>[
                    // Level
                    DataCell(Text(
                      '$level',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )),
                    // ELO rating - Use the fixed ELO for display
                    DataCell(Text(
                      '$fixedAiEloRating', // Display the fixed ELO rating
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getRatingColor(context,
                            fixedAiEloRating), // Color based on fixed ELO
                      ),
                    )),
                    // Total stats with monospace font - from persisted stats
                    DataCell(Text(
                      totalStats,
                      style: monoStyle,
                    )),
                    // White stats with monospace font - from persisted stats
                    DataCell(Text(
                      whiteStats,
                      style: monoStyle,
                    )),
                    // Black stats with monospace font - from persisted stats
                    DataCell(Text(
                      blackStats,
                      style: monoStyle,
                    )),
                  ],
                );
              },
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '* Format: W/D/L (${l10n.wins}/${l10n.draws}/${l10n.losses})',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Color _getRatingColor(BuildContext context, int rating) {
    if (rating >= 2000) {
      return Colors.purple; // Master
    } else if (rating >= 1800) {
      return Colors.blue; // Expert
    } else if (rating >= 1600) {
      return Colors.green; // Advanced
    } else if (rating >= 1400) {
      return Colors.amber; // Intermediate
    } else if (rating >= 1200) {
      return Colors.orange; // Average
    } else {
      return Colors.red; // Beginner
    }
  }
}
