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

    // Special handling for AI vs AI mode
    if (gameMode == GameMode.aiVsAi) {
      return _buildAiVsAiDialog(context, position);
    }

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

    final bool canChallenge = canChallengeNextLevel(_gameResult!) == true &&
        DB().generalSettings.searchAlgorithm != SearchAlgorithm.random &&
        !isTopLevel &&
        gameMode == GameMode.humanVsAi;

    final List<Widget> actions;
    if (canChallenge) {
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
      content: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                content.toString(),
                key: const Key('game_result_alert_dialog_content'),
                style: TextStyle(
                    fontSize:
                        AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
              ),
              if (canChallenge)
                const SizedBox(
                  height: 200,
                  width: double.infinity,
                  // Reserve space for confetti animation
                ),
            ],
          ),
          if (canChallenge)
            const Positioned(
              left: -50,
              right: -50,
              top: 30,
              bottom: 0,
              // Use updated ChallengeFireworks widget with confetti
              child: ChallengeConfetti(),
            ),
        ],
      ),
      actions: actions,
    );
  }

  Widget _buildAiVsAiDialog(BuildContext context, Position position) {
    // Get game duration in seconds
    final int gameDurationSeconds =
        GameController().calculateGameDurationSeconds();

    // Format duration as minutes and seconds
    final int minutes = gameDurationSeconds ~/ 60;
    final int seconds = gameDurationSeconds % 60;
    final String durationText = "${minutes}m ${seconds}s";

    // Determine winner text
    final String winnerText;
    if (position.winner == PieceColor.white) {
      winnerText = "White AI wins";
    } else if (position.winner == PieceColor.black) {
      winnerText = "Black AI wins";
    } else {
      winnerText = "Draw";
    }

    // Get game over reason
    final String reason =
        position.gameOverReason?.getName(context, position.winner) ??
            S.of(context).gameOverUnknownReason;

    // Build content with game duration
    final StringBuffer content = StringBuffer();
    content.writeln(reason);
    content.writeln();
    content.writeln("Game Duration: $durationText");

    return AlertDialog(
      key: const Key('ai_vs_ai_game_result_dialog'),
      title: Text(
        winnerText,
        key: const Key('ai_vs_ai_game_result_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        content.toString(),
        key: const Key('ai_vs_ai_game_result_dialog_content'),
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('ai_vs_ai_game_result_dialog_restart_button'),
          child: Text(
            S.of(context).restart,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () {
            GameController().reset(force: true);
            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();
            Navigator.pop(context);
          },
        ),
        TextButton(
          key: const Key('ai_vs_ai_game_result_dialog_close_button'),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
