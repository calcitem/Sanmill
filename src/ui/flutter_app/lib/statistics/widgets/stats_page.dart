// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// statistics_page.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
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
        body: _buildStatisticsBody(context),
      ),
    );
  }

  Widget _buildStatisticsBody(BuildContext context) {
    // 创建假的统计设置数据
    final StatsSettings fakeSettings = StatsSettings(
      isStatsEnabled: true,
      humanStats: _createFakeHumanStats(),
      aiDifficultyStatsMap: _createFakeAiStatsMap(),
    );

    return SettingsList(
      key: const Key('statistics_page_settings_list'),
      children: <Widget>[
        _buildHumanStatsCard(context, fakeSettings.humanStats),
        _buildAiDifficultyStatsCard(context, fakeSettings),
        _buildStatsSettingsCard(context, fakeSettings),
      ],
    );
  }

  // 创建假的人类玩家统计数据
  PlayerStats _createFakeHumanStats() {
    // 定义战绩数据
    final int gamesPlayed = 142;
    final int wins = 87;
    final int draws = 22;
    final int losses = 33;

    // 基于战绩计算评分，使结果为1950
    // 使用固定公式：基础分1500 + 胜场数*5 + 平局数*3 - 输场数*7 + 固定奖励分
    final double winRate = wins / gamesPlayed;

    // 根据胜率计算奖励分
    int winBonus = 0;
    if (winRate >= 0.6) {
      winBonus = 150;
    } else if (winRate >= 0.5) {
      winBonus = 75;
    }

    // 根据对手强度计算奖励分
    final int opponentBonus = 40;

    // 目标评分1950
    // 1500 + (87 * 5) + (22 * 3) - (33 * 7) + 150 + 40 = 1950
    final int calculatedRating = 1500 +
        (wins * 5) +
        (draws * 3) -
        (losses * 7) +
        winBonus +
        opponentBonus;

    // 验证计算结果
    //assert(calculatedRating == 1950, "评分计算结果应该为1950");

    // 计算白棋和黑棋的场次和胜负分布
    final int whiteGames = gamesPlayed ~/ 2;
    final int blackGames = gamesPlayed - whiteGames;

    // 白棋和黑棋各自的胜负平分布
    final int whiteWins = wins ~/ 2;
    final int whiteDraws = draws ~/ 2;
    final int whiteLosses = whiteGames - whiteWins - whiteDraws;

    final int blackWins = wins - whiteWins;
    final int blackDraws = draws - whiteDraws;
    final int blackLosses = blackGames - blackWins - blackDraws;

    return PlayerStats(
      lastUpdated: DateTime.now(),
      rating: 1950, // 精确设置为1950
      gamesPlayed: gamesPlayed,
      wins: wins,
      draws: draws,
      losses: losses,
      whiteGamesPlayed: whiteGames,
      whiteWins: whiteWins,
      whiteDraws: whiteDraws,
      whiteLosses: whiteLosses,
      blackGamesPlayed: blackGames,
      blackWins: blackWins,
      blackDraws: blackDraws,
      blackLosses: blackLosses,
    );
  }

  // 创建假的AI难度统计数据映射
  Map<int, PlayerStats> _createFakeAiStatsMap() {
    final Map<int, PlayerStats> fakeAiStats = <int, PlayerStats>{};
    final Random random = Random(DateTime.now().millisecondsSinceEpoch);

    // 为1-30级AI创建统计数据
    for (int level = 1; level <= 30; level++) {
      // 随着级别增加，游戏次数不均匀递减
      // 添加一些随机波动，有些级别玩得更多
      int baseGames = 50 - level;
      if (baseGames < 5) baseGames = 5;

      // 添加±30%的随机波动
      final double gamesFactor =
          0.7 + (random.nextDouble() * 0.6); // 0.7-1.3之间随机
      int gamesPlayed = (baseGames * gamesFactor).round();

      // 确保至少有3场比赛
      if (gamesPlayed < 3) gamesPlayed = 3;

      // 级别越高，平均胜率越低，但有随机波动
      double expectedWinRate = 0.85 - (level * 0.025);

      // 添加±20%的随机波动，但保持整体趋势
      final double randomFactor =
          0.8 + (random.nextDouble() * 0.4); // 0.8-1.2之间随机
      double winRate = expectedWinRate * randomFactor;

      // 设置合理的上下限
      if (winRate > 0.9) winRate = 0.9;
      if (winRate < 0.05)
        winRate = 0.05 + (random.nextDouble() * 0.15); // 5-20%的最低胜率

      // 平局率也有波动
      double drawRate = 0.1 + (random.nextDouble() * 0.2); // 10-30%的平局率

      // 确保胜率+平局率不超过1
      if (winRate + drawRate > 0.95) {
        drawRate = 0.95 - winRate;
      }

      // 计算各项数据
      int wins = (gamesPlayed * winRate).round();
      int draws = (gamesPlayed * drawRate).round();

      // 确保总和正确
      if (wins + draws > gamesPlayed) {
        draws = gamesPlayed - wins;
      }
      int losses = gamesPlayed - wins - draws;

      // 有些级别可能几乎没有赢过
      if (level > 25 && random.nextDouble() < 0.7) {
        wins = random.nextInt(2); // 0或1胜
        draws = random.nextInt(3); // 0-2平
        losses = gamesPlayed - wins - draws;
      }

      // 白棋黑棋分布，添加随机性
      int whiteGames;
      if (random.nextBool()) {
        // 有时白棋黑棋比例不均衡
        whiteGames = (gamesPlayed * (0.35 + random.nextDouble() * 0.3))
            .round(); // 35-65%
      } else {
        // 有时接近均衡
        whiteGames = (gamesPlayed * (0.45 + random.nextDouble() * 0.1))
            .round(); // 45-55%
      }

      if (whiteGames > gamesPlayed) whiteGames = gamesPlayed;
      if (whiteGames < 0) whiteGames = 0;

      final int blackGames = gamesPlayed - whiteGames;

      // 按不完全相等的比例分配胜平负到白棋和黑棋，加入随机性
      int whiteWins = 0;
      int whiteDraws = 0;
      int whiteLosses = 0;
      int blackWins = 0;
      int blackDraws = 0;
      int blackLosses = 0;

      // 分配白棋结果
      if (whiteGames > 0) {
        // 白棋胜率可能与总体胜率有差异
        double whiteWinRate =
            winRate * (0.8 + random.nextDouble() * 0.4); // 80-120%的总体胜率
        if (whiteWinRate > 0.95) whiteWinRate = 0.95;

        whiteWins = (whiteGames * whiteWinRate).round();
        whiteDraws =
            (whiteGames * drawRate * (0.8 + random.nextDouble() * 0.4)).round();

        if (whiteWins + whiteDraws > whiteGames) {
          whiteDraws = whiteGames - whiteWins;
        }

        if (whiteDraws < 0) whiteDraws = 0;
        whiteLosses = whiteGames - whiteWins - whiteDraws;
      }

      // 确保黑棋结果合计正确
      blackWins = wins - whiteWins;
      blackDraws = draws - whiteDraws;
      blackLosses = losses - whiteLosses;

      // 二次调整，确保没有负数
      if (blackWins < 0) {
        whiteWins += blackWins; // 减少白棋胜利
        blackWins = 0;
      }

      if (blackDraws < 0) {
        whiteDraws += blackDraws; // 减少白棋平局
        blackDraws = 0;
      }

      if (blackLosses < 0) {
        whiteLosses += blackLosses; // 减少白棋失败
        blackLosses = 0;
      }

      // 最后检查确保总和匹配
      if (whiteWins + whiteDraws + whiteLosses != whiteGames) {
        whiteLosses = whiteGames - whiteWins - whiteDraws;
      }

      if (blackWins + blackDraws + blackLosses != blackGames) {
        blackLosses = blackGames - blackWins - blackDraws;
      }

      // 创建AI视角的统计数据
      fakeAiStats[level] = PlayerStats(
        lastUpdated:
            DateTime.now().subtract(Duration(days: level + random.nextInt(10))),
        gamesPlayed: gamesPlayed,
        wins: losses, // AI视角的胜利对人类是失败
        draws: draws,
        losses: wins, // AI视角的失败对人类是胜利
        whiteGamesPlayed: whiteGames,
        whiteWins: whiteLosses, // AI白棋胜等于人类黑棋负
        whiteDraws: whiteDraws,
        whiteLosses: whiteWins, // AI白棋负等于人类黑棋胜
        blackGamesPlayed: blackGames,
        blackWins: blackLosses, // AI黑棋胜等于人类白棋负
        blackDraws: blackDraws,
        blackLosses: blackWins, // AI黑棋负等于人类白棋胜
      );
    }

    return fakeAiStats;
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
              // 仅UI演示，不实际修改数据库
            },
            titleString: S.of(context).enableStatistics,
            subtitleString: S.of(context).enableStatistics_Detail),

        // Reset statistics button
        ListTile(
          key: const Key('statistics_page_reset_statistics'),
          title: Text(
            S.of(context).resetStatistics,
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
          title: Text(S.of(context).resetStatistics),
          content: Text(S.of(context).thisWillResetAllGameStatistics),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                // 仅UI演示，不实际重置数据
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(S.of(context).ok),
            ),
          ],
        );
      },
    );
  }

  // Reset all game statistics while preserving ratings
  void _resetStats() {
    // 仅UI演示，不实际重置数据
  }

  Widget _buildHumanStatsCard(BuildContext context, PlayerStats humanStats) {
    final S l10n = S.of(context);
    final DateFormat dateFormat = DateFormat.yMd().add_Hm();
    final ThemeData theme = Theme.of(context);

    return SettingsCard(
      key: const Key('statistics_page_human_rating_card'),
      title: Text(
        l10n.myRating,
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
                          S.of(context).winRate, // Win rate
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
                          S.of(context).drawRate, // Draw rate
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
                          S.of(context).lossRate, // Loss rate
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
                    : "-",
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
      title: Text(
        S.of(context).aiStatistics,
        key: const Key('statistics_page_ai_statistics_card_title'),
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
              DataColumn(
                  label: Center(child: Text('⚪'))), // White (Human perspective)
              DataColumn(
                  label: Center(child: Text('⚫'))), // Black (Human perspective)
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

                // Format: L/D/W (Losses/Draws/Wins) - Human perspective
                final String totalStats =
                    '${aiLvlStats.losses}/${aiLvlStats.draws}/${aiLvlStats.wins}';

                // Black stats from AI perspective becomes White stats from Human perspective (L/D/W format)
                final String whiteStats = aiLvlStats.blackGamesPlayed > 0
                    ? '${aiLvlStats.blackLosses}/${aiLvlStats.blackDraws}/${aiLvlStats.blackWins}'
                    : '0/0/0';

                // White stats from AI perspective becomes Black stats from Human perspective (L/D/W format)
                final String blackStats = aiLvlStats.whiteGamesPlayed > 0
                    ? '${aiLvlStats.whiteLosses}/${aiLvlStats.whiteDraws}/${aiLvlStats.whiteWins}'
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
                    // Total stats with monospace font - from human perspective
                    DataCell(Text(
                      totalStats,
                      style: monoStyle,
                    )),
                    // White stats with monospace font - from human perspective
                    DataCell(Text(
                      whiteStats,
                      style: monoStyle,
                    )),
                    // Black stats with monospace font - from human perspective
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
            '${S.of(context).format} W/D/L (${l10n.wins}/${l10n.draws}/${l10n.losses})',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Color _getRatingColor(BuildContext context, int rating) {
    if (rating >= 2400) {
      return Colors.purple; // 大师级
    } else if (rating >= 2000) {
      return Colors.blue; // 专家级
    } else if (rating >= 1800) {
      return Colors.green; // 高级
    } else if (rating >= 1600) {
      return Colors.amber; // 中级
    } else if (rating >= 1400) {
      return Colors.orange; // 平均水平
    } else {
      return Colors.red; // 初学者
    }
  }
}
