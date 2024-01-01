// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

    logger.v("$_logTag Game over reason string: $content");

    final List<Widget> actions;
    if (_gameResult == GameResult.win &&
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

            logger.v(
              "[config] skillLevel: ${DB().generalSettings.skillLevel}",
            );

            GameController().reset(force: true);
            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(
            S.of(context).no,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
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
          child: Text(
            S.of(context).restart,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
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
      title: Text(
        dialogTitle,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(
        content.toString(),
        style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
      ),
      actions: actions,
    );
  }
}
