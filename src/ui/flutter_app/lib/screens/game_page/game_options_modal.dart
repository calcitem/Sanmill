/*
  This file is part of Sanmill.
  Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)

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
  static const _tag = "[GameOptionsModal]";

  const _GameOptionsModal({Key? key}) : super(key: key);

  onStartNewGameButtonPressed(BuildContext context) async {}

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
            await showRestartGameAlertDialog(context);
          },
          child: Text(S.of(context).newGame),
        ),
        const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController.save(context),
          child: Text(S.of(context).saveGame),
        ),
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
        const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController.export(context),
          child: Text(S.of(context).exportGame),
        ),
        const CustomSpacer(),
        if (DB().generalSettings.screenReaderSupport)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).close),
          ),
      ],
    );
  }

  showRestartGameAlertDialog(BuildContext context) async {
    Widget noButton = TextButton(
      child: Text(S.of(context).no),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        Navigator.of(context).pop();
      },
    );
    Widget yesButton = TextButton(
        child: Text(S.of(context).yes),
        onPressed: () {
          MillController().isActive == false;

          if (MillController().isEngineGoing == false) {
            MillController().reset();

            MillController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted, snackBar: true);
            MillController().headerIconsNotifier.showIcons();

            if (MillController().gameInstance.isAiToMove) {
              logger.i("$_tag New game, AI to move.");

              MillController().engineToGo(context, isMoveNow: false);

              MillController()
                  .headerTipNotifier
                  .showTip(S.of(context).tipPlace, snackBar: true);
            }

            MillController().headerIconsNotifier.showIcons();
          }

          Navigator.of(context, rootNavigator: true).pop(true);
          Navigator.of(context).pop();
        });

    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).restart),
      content: Text(S.of(context).restartGame),
      actions: [
        noButton,
        yesButton,
      ],
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}
