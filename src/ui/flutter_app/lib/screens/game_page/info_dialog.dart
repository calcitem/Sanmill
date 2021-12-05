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

class _InfoDialog extends StatelessWidget {
  const _InfoDialog({
    required this.tip,
    Key? key,
  }) : super(key: key);

  final String tip;

  String _infoText(BuildContext context) {
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

    if (LocalDatabaseService.preferences.screenReaderSupport) {
      buffer.writeln(":");
    } else {
      buffer.writeln();
    }

    final String? n1 = controller.position.recorder.lastMove?.notation;
    // Last Move information
    if (n1 != null) {
      // $them is only shown with the screen reader. It is convenient for
      // the disabled to recognize whether the opponent has finished the moving.
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        buffer.write(S.of(context).lastMove("$them, "));
      } else {
        buffer.write(S.of(context).lastMove(""));
      }

      if (n1.startsWith("x")) {
        buffer.writeln(
          controller.position.recorder
              .moves[controller.position.recorder.moveCount - 2].notation,
        );
      }
      buffer.writePeriod(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    // the tip
    if (LocalDatabaseService.preferences.screenReaderSupport &&
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
    return AlertDialog(
      backgroundColor: AppTheme.infoDialogBackgroundColor,
      content: SingleChildScrollView(
        child: Text(
          _infoText(context),
          style: AppTheme.moveHistoryTextStyle,
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('infoDialogOkButton'),
          child: Text(
            S.of(context).ok,
            style: AppTheme.moveHistoryTextStyle,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
