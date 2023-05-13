// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

    final String dialogTitle = _gameResult!.winString(context);

    final bool isTopLevel =
        DB().generalSettings.skillLevel == Constants.highestSkillLevel;

    final String reason =
        position.gameOverReason?.getName(context, position.winner) ??
            S.of(context).gameOverUnknownReason;

    final StringBuffer content = StringBuffer(reason);

    logger.v("$_logTag Game over reason string: $content");

    final S localizations = S.of(context);
    final List<Widget> actions;

    if (_gameResult == GameResult.win &&
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
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () async {
            final GeneralSettings settings = DB().generalSettings;
            DB().generalSettings =
                settings.copyWith(skillLevel: settings.skillLevel + 1);

            GameController().engine.setGeneralOptions();

            logger.v(
              "[config] skillLevel: ${DB().generalSettings.skillLevel}",
            );

            Navigator.pop(context);

            GameController().reset(force: true);
            GameController()
                .headerTipNotifier
                .showTip(localizations.gameStarted);
            GameController().headerIconsNotifier.showIcons();
          },
        ),
        TextButton(
          child: Text(
            localizations.no,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () {
            Navigator.pop(context);
            GameController().reset(force: true);
            GameController()
                .headerTipNotifier
                .showTip(localizations.gameStarted);
            GameController().headerIconsNotifier.showIcons();
          },
        ),
        TextButton(
          child: Text(
            localizations.cancel,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    } else {
      actions = <Widget>[
        TextButton(
          child: Text(
            localizations.restart,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () {
            Navigator.pop(context);
            GameController().reset(force: true);
            GameController()
                .headerTipNotifier
                .showTip(localizations.gameStarted);
            GameController().headerIconsNotifier.showIcons();
          },
        ),
        TextButton(
          child: Text(
            localizations.cancel,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    }

    return AlertDialog(
      title: Text(
        dialogTitle,
        style: AppTheme.dialogTitleTextStyle,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: Text(
        content.toString(),
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      actions: actions,
    );
  }
}
