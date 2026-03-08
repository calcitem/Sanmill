// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// strategy_suggestion_dialog.dart

part of '../game_page.dart';

/// Dialog that suggests visiting the Nine Men's Morris strategy guide
/// when the player is struggling under NMM rules.
class StrategySuggestionDialog extends StatelessWidget {
  const StrategySuggestionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('strategy_suggestion_dialog'),
      title: Text(
        S.of(context).strategySuggestionTitle,
        key: const Key('strategy_suggestion_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        S.of(context).nmmStrategySuggestion(S.of(context).nineMensMorris),
        key: const Key('strategy_suggestion_dialog_content'),
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('strategy_suggestion_dialog_learn_more_button'),
          child: Text(
            S.of(context).learnMore,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
            launchURL(context, Constants.nmmStrategyUrl);
          },
        ),
        TextButton(
          key: const Key('strategy_suggestion_dialog_not_now_button'),
          child: Text(
            S.of(context).notNow,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            final StatsSettings statsSettings = DB().statsSettings;
            DB().statsSettings = statsSettings.copyWith(
              shouldSuggestNmmStrategy: false,
            );
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('strategy_suggestion_dialog_dismiss_button'),
          child: Text(
            S.of(context).dontShowAgain,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            final StatsSettings statsSettings = DB().statsSettings;
            DB().statsSettings = statsSettings.copyWith(
              shouldSuggestNmmStrategy: false,
              nmmStrategySuggestionDismissed: true,
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
