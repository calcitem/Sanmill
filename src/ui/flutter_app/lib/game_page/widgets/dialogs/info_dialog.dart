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

class _InfoDialog extends StatelessWidget {
  const _InfoDialog();

  String _infoText(BuildContext context) {
    final GameController controller = GameController();
    final StringBuffer buffer = StringBuffer();
    final Position pos = controller.position;

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
      case PieceColor.ban:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        break;
    }

    buffer.write(pos.phase.getName(context));

    if (DB().generalSettings.screenReaderSupport) {
      buffer.writeln(":");
    } else {
      buffer.writeln();
    }

    final String? n1 = controller.gameRecorder.current?.notation;
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
        if (controller.gameRecorder.length == 1) {
          // TODO: Right? (Issue #686)
          buffer.writeln(
            controller
                .gameRecorder[controller.gameRecorder.length - 1].notation,
          );
        } else if (controller.gameRecorder.length >= 2) {
          buffer.writeln(
            controller
                .gameRecorder[controller.gameRecorder.length - 2].notation,
          );
        }
      }
      buffer.writeComma(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    final String msg = GameController().headerTipNotifier.message;

    // the tip
    if (DB().generalSettings.screenReaderSupport &&
        msg.endsWith(".") &&
        msg.endsWith("!")) {
      buffer.writePeriod(msg);
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
    buffer.writeComma(
      "${S.of(context).player1}: ${Position.score[PieceColor.white]}",
    );
    buffer.writeComma(
      "${S.of(context).player2}: ${Position.score[PieceColor.black]}",
    );
    buffer.writePeriod(
      "${S.of(context).draw}: ${Position.score[PieceColor.draw]}",
    );

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return GamePageActionSheet(
      child: AlertDialog(
        backgroundColor: UIColors.semiTransparentBlack,
        content: SingleChildScrollView(
          child: Text(
            _infoText(context),
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: AppTheme.gamePageActionSheetTextColor,
                  fontWeight: FontWeight.normal,
                  fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
                ),
          ),
        ),
        actions: <Widget>[
          if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS)
            TextButton(
              child: Text(
                S.of(context).more,
                key: const Key('infoDialogMoreButton'),
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: AppTheme.gamePageActionSheetTextColor,
                      fontSize:
                          AppTheme.textScaler.scale(AppTheme.largeFontSize),
                    ),
              ),
              onPressed: () async {
                String content = "";

                if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
                  final CatcherOptions options = catcher.getCurrentConfig()!;
                  for (final dynamic value in options.customParameters.values) {
                    final String str = value
                        .toString()
                        .replaceAll("setoption name ", "")
                        .replaceAll("value", "=");
                    content += "$str\n";
                  }
                }

                final Widget copyButton = TextButton(
                  child: Text(
                    S.of(context).copy,
                    style: TextStyle(
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.largeFontSize)),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: content),
                    );

                    rootScaffoldMessengerKey.currentState!
                        .showSnackBarClear(S.of(context).done);

                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                );

                final Widget okButton = TextButton(
                    child: Text(
                      S.of(context).ok,
                      style: TextStyle(
                          fontSize: AppTheme.textScaler
                              .scale(AppTheme.largeFontSize)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    });

                final AlertDialog alert = AlertDialog(
                  title: Text(
                    S.of(context).more,
                    style: TextStyle(
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.largeFontSize)),
                  ),
                  content: Text(
                    content,
                    textDirection: TextDirection.ltr,
                  ),
                  actions: <Widget>[copyButton, okButton],
                  scrollable: true,
                );

                await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return alert;
                  },
                );
              },
            ),
          TextButton(
            child: Text(
              S.of(context).ok,
              key: const Key('infoDialogOkButton'),
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: AppTheme.gamePageActionSheetTextColor,
                    fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
                  ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
