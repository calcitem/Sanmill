/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of 'package:sanmill/screens/game_page/game_page.dart';

class _GameResultAlert extends StatelessWidget {
  _GameResultAlert({
    required this.winner,
    required this.onRestart,
    Key? key,
  }) : super(key: key);

  final EngineType engineType = controller.gameInstance.engineType;
  final PieceColor winner;
  final VoidCallback onRestart;

  static const _tag = "[Game Over Alert]";

  GameResult get _gameResult {
    if (engineType == EngineType.aiVsAi) return GameResult.none;

    switch (winner) {
      case PieceColor.white:
        if (controller.gameInstance.isAi[PieceColor.white]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.black:
        if (controller.gameInstance.isAi[PieceColor.black]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.draw:
        return GameResult.draw;
      default:
        return GameResult.none;
    }
  }

  @override
  Widget build(BuildContext context) {
    controller.position.result = _gameResult;

    late final String dialogTitle;
    switch (_gameResult) {
      case GameResult.win:
        dialogTitle = engineType == EngineType.humanVsAi
            ? S.of(context).youWin
            : S.of(context).gameOver;
        break;
      case GameResult.lose:
        dialogTitle = S.of(context).gameOver;
        break;
      case GameResult.draw:
        dialogTitle = S.of(context).isDraw;
        break;
      default:
        assert(false);
    }

    final bool isTopLevel =
        LocalDatabaseService.preferences.skillLevel == 30; // TODO: 30

    final content = StringBuffer(
      controller.position.gameOverReason
          .getName(context, controller.position.winner),
    );

    debugPrint("$_tag Game over reason string: $content");

    final List<Widget> actions;
    if (_gameResult == GameResult.win &&
        !isTopLevel &&
        engineType == EngineType.humanVsAi) {
      content.writeln();
      content.writeln();
      content.writeln(
        S.of(context).challengeHarderLevel(
              LocalDatabaseService.preferences.skillLevel + 1,
            ),
      );

      actions = [
        TextButton(
          child: Text(
            S.of(context).yes,
          ),
          onPressed: () async {
            final _pref = LocalDatabaseService.preferences;
            LocalDatabaseService.preferences =
                _pref.copyWith(skillLevel: _pref.skillLevel + 1);
            debugPrint(
              "[config] skillLevel: ${LocalDatabaseService.preferences.skillLevel}",
            );

            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(S.of(context).no),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    } else {
      actions = [
        TextButton(
          child: Text(S.of(context).restart),
          onPressed: () {
            Navigator.pop(context);
            onRestart.call();
          },
        ),
        TextButton(
          child: Text(S.of(context).cancel),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    }

    return AlertDialog(
      title: Text(
        dialogTitle,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: Text(content.toString()),
      actions: actions,
    );
  }
}
