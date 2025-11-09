// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_battle_page.dart
//
// Competitive puzzle battle mode

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';

/// Puzzle Battle mode - compete against others
class PuzzleBattlePage extends StatelessWidget {
  const PuzzleBattlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.puzzleBattle,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                FluentIcons.people_24_regular,
                size: 80,
                color: Colors.purple.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 24),
              Text(
                s.comingSoon,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.puzzleBattleComingSoon,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Card(
                color: Colors.purple.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.plannedFeatures,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureItem(s.puzzleBattleFeature1),
                      _buildFeatureItem(s.puzzleBattleFeature2),
                      _buildFeatureItem(s.puzzleBattleFeature3),
                      _buildFeatureItem(s.puzzleBattleFeature4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: <Widget>[
          const Icon(
            FluentIcons.checkmark_24_regular,
            size: 16,
            color: Colors.purple,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
