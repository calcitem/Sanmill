// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// info_dialog.dart

part of '../game_page.dart';

class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key});

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
      case PieceColor.marked:
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

    final String? n1 = controller.gameRecorder.activeNode?.data?.notation;

    // Last Move information
    if (n1 != null) {
      final String formattedNotation = DB().generalSettings.screenReaderSupport
          ? n1.toUpperCase()
          : n1.toLowerCase();

      // $them is only shown with the screen reader. It is convenient for
      // the disabled to recognize whether the opponent has finished the moving.
      buffer.write(
        S.of(context).lastMove(
              DB().generalSettings.screenReaderSupport ? "$them, " : "",
            ),
      );

      if (n1.startsWith("x")) {
        String moveNotation = "";
        if (controller.gameRecorder.mainlineMoves.length == 1) {
          // TODO: Right? (Issue #686)
          moveNotation = controller
              .gameRecorder
              .mainlineMoves[controller.gameRecorder.mainlineMoves.length - 1]
              .notation;
        } else if (controller.gameRecorder.mainlineMoves.length >= 2) {
          moveNotation = controller
              .gameRecorder
              .mainlineMoves[controller.gameRecorder.mainlineMoves.length - 2]
              .notation;
        }
        // Apply correct case based on screen reader setting
        moveNotation = DB().generalSettings.screenReaderSupport
            ? moveNotation.toUpperCase()
            : moveNotation.toLowerCase();
        buffer.writeln(moveNotation);
      }

      buffer.writeComma(formattedNotation);
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
      key: const Key('info_dialog_game_page_action_sheet'),
      child: AlertDialog(
        key: const Key('info_dialog_alert_dialog'),
        backgroundColor: UIColors.semiTransparentBlack,
        content: SingleChildScrollView(
          key: const Key('info_dialog_single_child_scroll_view'),
          child: Text(
            key: const Key('info_dialog_content_text'),
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
              key: const Key('info_dialog_more_button'),
              child: Text(
                S.of(context).more,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: AppTheme.gamePageActionSheetTextColor,
                      fontSize:
                          AppTheme.textScaler.scale(AppTheme.largeFontSize),
                    ),
              ),
              onPressed: () async {
                final String copy = S.of(context).copy;
                final String ok = S.of(context).ok;

                final String content = generateOptionsContent();

                final Widget copyButton = TextButton(
                  key: const Key('info_dialog_copy_button'),
                  child: Text(
                    copy,
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
                    key: const Key('info_dialog_ok_button_more'),
                    child: Text(
                      ok,
                      style: TextStyle(
                          fontSize: AppTheme.textScaler
                              .scale(AppTheme.largeFontSize)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    });

                final AlertDialog alert = AlertDialog(
                  key: const Key('info_dialog_more_alert_dialog'),
                  title: Text(
                    S.of(context).more,
                    key: const Key('info_dialog_more_alert_dialog_title'),
                    style: TextStyle(
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.largeFontSize)),
                  ),
                  content: Text(
                    content,
                    key: const Key('info_dialog_more_alert_dialog_content'),
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
            key: const Key('info_dialog_ok_button'),
            child: Text(
              S.of(context).ok,
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
