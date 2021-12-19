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

part of './game_page.dart';

class _GameOptionsModal extends StatelessWidget {
  const _GameOptionsModal({Key? key}) : super(key: key);
  static const String _tag = "[game_options]";

  Future<void> _startNew(BuildContext context) async {
    Navigator.pop(context);

    MillController().gameInstance.newGame();

    MillController().tip.showTip(S.of(context).gameStarted, snackBar: true);

    if (MillController().gameInstance.isAiToMove) {
      logger.v("$_tag New game, AI to move.");
      // extracted.engineToGo(isMoveNow: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      semanticLabel: S.of(context).game,
      backgroundColor: Colors.transparent,
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () => _startNew(context),
          child: Text(
            S.of(context).newGame,
            style: AppTheme.simpleDialogOptionTextStyle,
            textAlign: TextAlign.center,
          ),
        ),
        const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController().recorder.import(context),
          child: Text(
            S.of(context).importGame,
            style: AppTheme.simpleDialogOptionTextStyle,
            textAlign: TextAlign.center,
          ),
        ),
        const CustomSpacer(),
        SimpleDialogOption(
          onPressed: () => MillController().recorder.export(context),
          child: Text(
            S.of(context).exportGame,
            style: AppTheme.simpleDialogOptionTextStyle,
            textAlign: TextAlign.center,
          ),
        ),
        const CustomSpacer(),
        if (LocalDatabaseService.preferences.screenReaderSupport)
          SimpleDialogOption(
            child: Text(
              S.of(context).close,
              style: AppTheme.simpleDialogOptionTextStyle,
              textAlign: TextAlign.center,
            ),
            onPressed: () => Navigator.pop(context),
          ),
      ],
    );
  }
}
