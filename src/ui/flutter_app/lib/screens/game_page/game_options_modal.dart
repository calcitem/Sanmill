/*
  This file is part of Sanmill.
  Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)

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

part of 'game_page.dart';

class _GameOptionsModal extends StatelessWidget {
  const _GameOptionsModal();

  static const String _tag = "[GameOptionsModal]";

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

            MillController().engine.stopSearching();

            if (MillController().position.phase == Phase.ready ||
                (MillController().position.phase == Phase.placing &&
                    (MillController().recorder.index != null &&
                        MillController().recorder.index! <= 3)) ||
                MillController().position.phase == Phase.gameOver) {
              // TODO: This part of the code is repetitive.
              // ignore: unnecessary_statements
              MillController().isActive == false;

              // TODO: Called stopSearching(); so isEngineGoing is always false?
              if (MillController().isEngineGoing == false) {
                MillController().reset(force: true);

                MillController()
                    .headerTipNotifier
                    .showTip(S.of(context).gameStarted);
                MillController().headerIconsNotifier.showIcons();

                if (MillController().gameInstance.isAiToMove) {
                  logger.i("$_tag New game, AI to move.");

                  MillController().engineToGo(context, isMoveNow: false);

                  MillController()
                      .headerTipNotifier
                      .showTip(S.of(context).tipPlace, snackBar: false);
                }

                MillController().headerIconsNotifier.showIcons();
              }

              Navigator.of(context).pop();
            } else {
              await showRestartGameAlertDialog(context);
            }
          },
          child: Text(S.of(context).newGame),
        ),
        const CustomSpacer(),
        if (MillController().recorder.hasPrevious == true ||
            MillController().isPositionSetup == true)
          SimpleDialogOption(
            onPressed: () => MillController.save(context),
            child: Text(S.of(context).saveGame),
          ),
        if (MillController().recorder.hasPrevious == true ||
            MillController().isPositionSetup == true)
          const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController.load(context),
          child: Text(S.of(context).loadGame),
        ),
        const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController.import(context),
          child: Text(S.of(context).importGame),
        ),
        if (MillController().recorder.hasPrevious == true ||
            MillController().isPositionSetup == true)
          const CustomSpacer(),
        if (MillController().recorder.hasPrevious == true ||
            MillController().isPositionSetup == true)
          SimpleDialogOption(
            onPressed: () => MillController.export(context),
            child: Text(S.of(context).exportGame),
          ),
        if (DB().generalSettings.gameScreenRecorderSupport)
          const CustomSpacer(),
        if (DB().generalSettings.gameScreenRecorderSupport)
          SimpleDialogOption(
            onPressed: () {
              MillController().gifShare(context);
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
          textScaleFactor: DB().displaySettings.fontScale,
        ),
        onPressed: () {
          // ignore: unnecessary_statements
          MillController().isActive == false;

          // TODO: Called stopSearching(); so isEngineGoing is always false?
          if (MillController().isEngineGoing == false) {
            MillController().reset(force: true);

            MillController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            MillController().headerIconsNotifier.showIcons();

            if (MillController().gameInstance.isAiToMove) {
              logger.i("$_tag New game, AI to move.");

              MillController().engineToGo(context, isMoveNow: false);

              MillController()
                  .headerTipNotifier
                  .showTip(S.of(context).tipPlace, snackBar: false);
            }

            MillController().headerIconsNotifier.showIcons();
          }

          Navigator.of(context, rootNavigator: true).pop(true);
          Navigator.of(context).pop();
        });

    final Widget noButton = TextButton(
      child: Text(
        S.of(context).no,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        Navigator.of(context).pop();
      },
    );

    final AlertDialog alert = AlertDialog(
      title: Text(
        S.of(context).restart,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: Text(
        S.of(context).restartGame,
        textScaleFactor: DB().displaySettings.fontScale,
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
