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
  const _GameOptionsModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).game,
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () async {
            Navigator.pop(context);
            MillController().reset();
            MillController()
                .tip
                .showTip(S.of(context).gameStarted, snackBar: true);

            // TODO: Why not suitable for GameMode.aiVsAi?
            if (MillController().gameInstance.gameMode == GameMode.humanVsAi &&
                DB().generalSettings.aiMovesFirst) {
              //MillController().tip.showTip(S.of(context).thinking);
              final extMove = await MillController().engine.search();

              if (await MillController().gameInstance.doMove(extMove)) {
                MillController().recorder.add(extMove);

                // TODO: Unhandled Exception: Looking up a deactivated widget's ancestor is unsafe.
                //MillController().tip.showTip(S.of(context).tipPlace);

                //if (DB().generalSettings.screenReaderSupport) {
                //  ScaffoldMessenger.of(context).showSnackBar(
                //    CustomSnackBar("${S.of(context).ai}: ${extMove.notation}"),
                //  );
                // }
              }
            }
          },
          child: Text(S.of(context).newGame),
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
}
