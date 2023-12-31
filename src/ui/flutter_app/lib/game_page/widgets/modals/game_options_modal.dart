/*
  This file is part of Sanmill.
  Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)

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

part of '../game_page.dart';

class _GameOptionsModal extends StatelessWidget {
  const _GameOptionsModal();

  static const String _logTag = "[GameOptionsModal]";

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).game,
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () async {
            //Navigator.pop(context);

            // TODO: If no dialog showing, When the AI is thinking,
            //  restarting the game may cause two or three pieces to appear on the board,
            //  sometimes it will keep displaying Thinking...

            GameController().engine.stopSearching();

            if (GameController().position.phase == Phase.ready ||
                (GameController().position.phase == Phase.placing &&
                    (GameController().gameRecorder.index != null &&
                        GameController().gameRecorder.index! <= 3)) ||
                GameController().position.phase == Phase.gameOver) {
              // TODO: This part of the code is repetitive.
              // ignore: unnecessary_statements
              GameController().isControllerActive == false;

              // TODO: Called stopSearching(); so isEngineGoing is always false?
              if (GameController().isEngineRunning == false) {
                GameController().reset(force: true);

                GameController()
                    .headerTipNotifier
                    .showTip(S.of(context).gameStarted);
                GameController().headerIconsNotifier.showIcons();

                if (GameController().gameInstance.isAiToMove) {
                  logger.i("$_logTag New game, AI to move.");

                  GameController().engineToGo(context, isMoveNow: false);

                  GameController()
                      .headerTipNotifier
                      .showTip(S.of(context).tipPlace, snackBar: false);
                }

                GameController().headerIconsNotifier.showIcons();
              }

              Navigator.of(context).pop();
            } else {
              await showRestartGameAlertDialog(context);
            }
          },
          child: Text(S.of(context).newGame),
        ),
        const CustomSpacer(),
        if (!kIsWeb &&
            (GameController().gameRecorder.hasPrevious == true ||
                GameController().isPositionSetup == true))
          SimpleDialogOption(
            onPressed: () => GameController.save(context),
            child: Text(S.of(context).saveGame),
          ),
        if (!kIsWeb &&
            (GameController().gameRecorder.hasPrevious == true ||
                GameController().isPositionSetup == true))
          const CustomSpacer(),
        if (!kIsWeb)
          SimpleDialogOption(
            onPressed: () => GameController.load(context),
            child: Text(S.of(context).loadGame),
          ),
        const CustomSpacer(),
        if (!kIsWeb)
          SimpleDialogOption(
            onPressed: () => GameController.import(context),
            child: Text(S.of(context).importGame),
          ),
        if (!kIsWeb &&
            (GameController().gameRecorder.hasPrevious == true ||
                GameController().isPositionSetup == true))
          const CustomSpacer(),
        if (!kIsWeb &&
            (GameController().gameRecorder.hasPrevious == true ||
                GameController().isPositionSetup == true))
          SimpleDialogOption(
            onPressed: () => GameController.export(context),
            child: Text(S.of(context).exportGame),
          ),
        // TODO: Fix iOS bug
        if (DB().generalSettings.gameScreenRecorderSupport && !Platform.isIOS)
          const CustomSpacer(),
        if (DB().generalSettings.gameScreenRecorderSupport && !Platform.isIOS)
          SimpleDialogOption(
            onPressed: () {
              GameController().gifShare(context);
              Navigator.pop(context);
            },
            child: Text(S.of(context).shareGIF),
          ),
        if (DB().generalSettings.screenReaderSupport) const CustomSpacer(),
        if (DB().generalSettings.screenReaderSupport)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).close),
          ),
      ],
    );
  }

  Future<Widget?> showRestartGameAlertDialog(BuildContext context) async {
    final Widget yesButton = TextButton(
        child: Text(
          S.of(context).yes,
          style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
        ),
        onPressed: () {
          // ignore: unnecessary_statements
          GameController().isControllerActive == false;

          // TODO: Called stopSearching(); so isEngineGoing is always false?
          if (GameController().isEngineRunning == false) {
            GameController().reset(force: true);

            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();

            if (GameController().gameInstance.isAiToMove) {
              logger.i("$_logTag New game, AI to move.");

              GameController().engineToGo(context, isMoveNow: false);

              GameController()
                  .headerTipNotifier
                  .showTip(S.of(context).tipPlace, snackBar: false);
            }

            GameController().headerIconsNotifier.showIcons();
          }

          Navigator.of(context, rootNavigator: true).pop(true);
          Navigator.of(context).pop();
        });

    final Widget noButton = TextButton(
      child: Text(
        S.of(context).no,
        style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
      ),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        Navigator.of(context).pop();
      },
    );

    final AlertDialog alert = AlertDialog(
      title: Text(
        S.of(context).restart,
        style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
      ),
      content: Text(
        S.of(context).restartGame,
        style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
      ),
      actions: <Widget>[
        yesButton,
        noButton,
      ],
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );

    return null;
  }
}
