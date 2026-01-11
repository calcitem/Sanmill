// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// algorithm_suggestion_dialog.dart

part of '../game_page.dart';

/// Dialog that suggests switching to a different algorithm based on performance
class AlgorithmSuggestionDialog extends StatelessWidget {
  const AlgorithmSuggestionDialog({required this.suggestionType, super.key});

  final AlgorithmSuggestionType suggestionType;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String content;
    final SearchAlgorithm targetAlgorithm;

    switch (suggestionType) {
      case AlgorithmSuggestionType.switchToMcts:
        // Suggest switching to MCTS for easier difficulty
        title = S.of(context).algorithmSuggestionTitle;
        content = S.of(context).switchToMctsSuggestion;
        targetAlgorithm = SearchAlgorithm.mcts;
        break;
      case AlgorithmSuggestionType.switchToMtdf:
        // Suggest switching to MTD(f) for harder challenge
        title = S.of(context).algorithmSuggestionTitle;
        content = S.of(context).switchToMtdfSuggestion;
        targetAlgorithm = SearchAlgorithm.mtdf;
        break;
    }

    return AlertDialog(
      key: const Key('algorithm_suggestion_dialog'),
      title: Text(
        title,
        key: const Key('algorithm_suggestion_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        content,
        key: const Key('algorithm_suggestion_dialog_content'),
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('algorithm_suggestion_dialog_yes_button'),
          child: Text(
            S.of(context).yes,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            // Switch to the suggested algorithm
            final GeneralSettings settings = DB().generalSettings;

            // When switching to MTD(f), also set skill level to 2
            // to provide a reasonable starting difficulty
            if (suggestionType == AlgorithmSuggestionType.switchToMtdf) {
              DB().generalSettings = settings.copyWith(
                searchAlgorithm: targetAlgorithm,
                skillLevel: 2,
              );
              logger.t(
                "[AlgorithmSuggestion] Switched to algorithm: $targetAlgorithm with skill level 2",
              );
            } else {
              DB().generalSettings = settings.copyWith(
                searchAlgorithm: targetAlgorithm,
              );
              logger.t(
                "[AlgorithmSuggestion] Switched to algorithm: $targetAlgorithm",
              );
            }

            // Update engine settings
            GameController().engine.setGeneralOptions();

            // Reset the suggestion flag
            final StatsSettings statsSettings = DB().statsSettings;
            DB().statsSettings = statsSettings.copyWith(
              shouldSuggestMctsSwitch:
                  suggestionType != AlgorithmSuggestionType.switchToMcts &&
                  statsSettings.shouldSuggestMctsSwitch,
              shouldSuggestMtdfSwitch:
                  suggestionType != AlgorithmSuggestionType.switchToMtdf &&
                  statsSettings.shouldSuggestMtdfSwitch,
            );

            // Close the dialog
            Navigator.pop(context);

            // Restart the game
            GameController().reset(force: true);
            GameController().headerTipNotifier.showTip(
              S.of(context).gameStarted,
            );
            GameController().headerIconsNotifier.showIcons();
          },
        ),
        TextButton(
          key: const Key('algorithm_suggestion_dialog_no_button'),
          child: Text(
            S.of(context).no,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            // Reset the suggestion flag
            final StatsSettings statsSettings = DB().statsSettings;
            DB().statsSettings = statsSettings.copyWith(
              shouldSuggestMctsSwitch:
                  suggestionType != AlgorithmSuggestionType.switchToMcts &&
                  statsSettings.shouldSuggestMctsSwitch,
              shouldSuggestMtdfSwitch:
                  suggestionType != AlgorithmSuggestionType.switchToMtdf &&
                  statsSettings.shouldSuggestMtdfSwitch,
            );

            // Close the dialog
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

/// Type of algorithm suggestion to show
enum AlgorithmSuggestionType {
  /// Suggest switching to MCTS for easier difficulty
  switchToMcts,

  /// Suggest switching to MTD(f) for harder challenge
  switchToMtdf,
}
