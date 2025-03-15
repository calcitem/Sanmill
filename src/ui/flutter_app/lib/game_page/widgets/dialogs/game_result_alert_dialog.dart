// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_result_alert_dialog.dart

part of '../game_page.dart';

class GameResultAlertDialog extends StatelessWidget {
  GameResultAlertDialog({
    required this.winner,
    super.key,
  });

  final GameMode gameMode = GameController().gameInstance.gameMode;
  final PieceColor winner;

  static const String _logTag = "[Game Over Alert]";

  GameResult? get _gameResult {
    if (gameMode == GameMode.aiVsAi || gameMode == GameMode.setupPosition) {
      return null;
    }
    return winner.result;
  }

  bool canChallengeNextLevel(GameResult gameResult) {
    final RuleSettings settings = DB().ruleSettings;
    final bool isWin = gameResult == GameResult.win;
    final bool isDraw = gameResult == GameResult.draw;

    if (settings.isLikelyNineMensMorris()) {
      return isWin || isDraw;
    } else if (settings.isLikelyTwelveMensMorris()) {
      if (DB().generalSettings.aiMovesFirst) {
        return isWin || isDraw;
      } else {
        return isWin;
      }
    } else {
      return isWin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Position position = GameController().position;
    // TODO: Why sometimes _gameResult is null?
    position.result = _gameResult;

    switch (position.result) {
      case GameResult.win:
        SoundManager().playTone(Sound.win);
        break;
      case GameResult.draw:
        SoundManager().playTone(Sound.draw);
        break;
      case GameResult.lose:
        SoundManager().playTone(Sound.lose);
        break;
      case null:
        break;
    }

    final String dialogTitle = _gameResult!.winString(context);

    final bool isTopLevel =
        DB().generalSettings.skillLevel == Constants.highestSkillLevel;

    final String reason =
        position.gameOverReason?.getName(context, position.winner) ??
            S.of(context).gameOverUnknownReason;

    final StringBuffer content = StringBuffer(reason);

    logger.t("$_logTag Game over reason string: $content");

    final List<Widget> actions;
    if (canChallengeNextLevel(_gameResult!) == true &&
        DB().generalSettings.searchAlgorithm != SearchAlgorithm.random &&
        !isTopLevel &&
        gameMode == GameMode.humanVsAi) {
      content.writeln();
      content.writeln();
      content.writeln(
        S.of(context).challengeHarderLevel(
              DB().generalSettings.skillLevel + 1,
            ),
      );

      actions = <Widget>[
        TextButton(
          key: const Key('game_result_alert_dialog_yes_button'),
          child: Text(
            S.of(context).yes,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () async {
            final GeneralSettings settings = DB().generalSettings;
            DB().generalSettings =
                settings.copyWith(skillLevel: settings.skillLevel + 1);

            GameController().engine.setGeneralOptions();

            logger.t(
              "[config] skillLevel: ${DB().generalSettings.skillLevel}",
            );

            // If game mode is LAN, call reset with lanRestart:true to preserve LAN settings
            if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
              GameController().reset(lanRestart: true);
            } else {
              GameController().reset(force: true);
            }

            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('game_result_alert_dialog_no_button'),
          child: Text(
            S.of(context).no,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () {
            // If game mode is LAN, call reset with lanRestart:true to preserve LAN settings
            if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
              GameController().reset(lanRestart: true);
            } else {
              GameController().reset(force: true);
            }
            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('game_result_alert_dialog_cancel_button_challenge'),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    } else {
      actions = <Widget>[
        TextButton(
          key: const Key('game_result_alert_dialog_restart_button'),
          child: Text(
            S.of(context).restart,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () {
            // If game mode is LAN, call reset with lanRestart:true to preserve LAN settings
            if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
              GameController().reset(lanRestart: true);
            } else {
              GameController().reset(force: true);
            }
            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('game_result_alert_dialog_cancel_button'),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    }

    return AlertDialog(
      key: const Key('game_result_alert_dialog'),
      title: Text(
        dialogTitle,
        key: const Key('game_result_alert_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        content.toString(),
        key: const Key('game_result_alert_dialog_content'),
        style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
      ),
      actions: actions,
    );
  }
}
