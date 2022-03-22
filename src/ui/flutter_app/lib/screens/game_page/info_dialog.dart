// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of './game_page.dart';

class _InfoDialog extends StatelessWidget {
  const _InfoDialog({Key? key}) : super(key: key);

  String _infoText(BuildContext context) {
    final controller = MillController();
    final buffer = StringBuffer();
    final pos = controller.position;

    late final String us;
    late final String them;
    switch (pos.sideToMove) {
      case PieceColor.white:
        us = S.of(context).player1;
        them = S.of(context).player2;
        break;
      case PieceColor.black:
        us = S.of(context).player2;
        them = S.of(context).player1;
        break;
      default:
    }

    buffer.write(pos.phase.getName(context));

    if (DB().generalSettings.screenReaderSupport) {
      buffer.writeln(":");
    } else {
      buffer.writeln();
    }

    final String? n1 = controller.recorder.current?.notation;
    // Last Move information
    if (n1 != null) {
      // $them is only shown with the screen reader. It is convenient for
      // the disabled to recognize whether the opponent has finished the moving.
      buffer.write(
        S.of(context).lastMove(
              DB().generalSettings.screenReaderSupport ? "$them, " : "",
            ),
      );

      if (n1.startsWith("x")) {
        buffer.writeln(
          controller.recorder[controller.recorder.length - 2].notation,
        );
      }
      buffer.writePeriod(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    final String tip = MillController().tip.message ?? S.of(context).welcome;

    // the tip
    if (DB().generalSettings.screenReaderSupport &&
        tip.endsWith(".") &&
        tip.endsWith("!")) {
      buffer.writePeriod(tip);
    }

    buffer.writeln();
    buffer.writeln(S.of(context).pieceCount);
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player1,
            pos.pieceInHandCount[PieceColor.white]!,
          ),
    );
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player2,
            pos.pieceInHandCount[PieceColor.black]!,
          ),
    );
    buffer.writeComma(
      S.of(context).onBoard(
            S.of(context).player1,
            pos.pieceOnBoardCount[PieceColor.white]!,
          ),
    );
    buffer.writePeriod(
      S.of(context).onBoard(
            S.of(context).player2,
            pos.pieceOnBoardCount[PieceColor.black]!,
          ),
    );
    buffer.writeln();
    buffer.writeln(S.of(context).score);
    buffer
        .writeComma("${S.of(context).player1}: ${pos.score[PieceColor.white]}");
    buffer
        .writeComma("${S.of(context).player2}: ${pos.score[PieceColor.black]}");
    buffer.writePeriod("${S.of(context).draw}: ${pos.score[PieceColor.draw]}");

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return GamePageActionSheet(
      child: AlertDialog(
        content: SingleChildScrollView(
          child: Text(
            _infoText(context),
            style: Theme.of(context).textTheme.headline6!.copyWith(
                  color: AppTheme.gamePageActionSheetTextColor,
                  fontWeight: FontWeight.normal,
                ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              S.of(context).ok,
              key: const Key('infoDialogOkButton'),
              style: Theme.of(context).textTheme.headline6!.copyWith(
                    color: AppTheme.gamePageActionSheetTextColor,
                  ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
