// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_options_modal.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../shared/config/constants.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/widgets/custom_spacer.dart';
import '../../services/mill.dart';
import '../game_page.dart';

// ignore: unused_element
class GameOptionsModal extends StatelessWidget {
  const GameOptionsModal({super.key, required this.onTriggerScreenshot});

  final VoidCallback onTriggerScreenshot;

  static const String _logTag = "[GameOptionsModal]";

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).game,
      children: <Widget>[
        SimpleDialogOption(
          key: const Key('new_game_option'),
          onPressed: () async {
            //Navigator.pop(context);

            // TODO: If no dialog showing, When the AI is thinking,
            //  restarting the game may cause two or three pieces to appear on the board,
            //  sometimes it will keep displaying Thinking...

            GameController().loadedGameFilenamePrefix = null;

            GameController().engine.stopSearching();

            if (GameController().position.phase == Phase.ready ||
                (GameController().position.phase == Phase.placing &&
                    (GameController().gameRecorder.mainlineMoves.length <=
                        3)) ||
                GameController().position.phase == Phase.gameOver) {
              // TODO: Called stopSearching(); so isEngineGoing is always false?
              if (GameController().isEngineRunning == false) {
                GameController().reset(force: true);

                GameController()
                    .headerTipNotifier
                    .showTip(S.of(context).gameStarted);
                GameController().headerIconsNotifier.showIcons();

                if (GameController().gameInstance.isAiSideToMove) {
                  logger.i("$_logTag New game, AI to move.");

                  GameController().engineToGo(context, isMoveNow: false);

                  final String side =
                      GameController().position.sideToMove.playerName(context);

                  if (DB().ruleSettings.mayMoveInPlacingPhase) {
                    GameController().headerTipNotifier.showTip(
                        S.of(context).tipToMove(side),
                        snackBar: false);
                  } else {
                    GameController()
                        .headerTipNotifier
                        .showTip(S.of(context).tipPlace, snackBar: false);
                  }
                }

                GameController().headerIconsNotifier.showIcons();
              }

              Navigator.of(context).pop();
            } else {
              await showRestartGameAlertDialog(context);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(S.of(context).newGame),
          ),
        ),
        const CustomSpacer(),
        if (!kIsWeb &&
            (GameController().gameRecorder.mainlineMoves.isNotEmpty ||
                GameController().isPositionSetup == true))
          SimpleDialogOption(
            key: const Key('save_game_option'),
            onPressed: () => GameController.save(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).saveGame),
            ),
          ),
        if (!kIsWeb &&
            (GameController().gameRecorder.mainlineMoves.isNotEmpty ||
                GameController().isPositionSetup == true))
          const CustomSpacer(),
        if (!kIsWeb)
          SimpleDialogOption(
            key: const Key('load_game_option'),
            onPressed: () {
              GameController().loadedGameFilenamePrefix = null;
              GameController.load(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).loadGame),
            ),
          ),
        const CustomSpacer(),
        if (!kIsWeb)
          SimpleDialogOption(
            key: const Key('import_game_option'),
            onPressed: () {
              GameController().loadedGameFilenamePrefix = null;
              GameController.import(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).importGame),
            ),
          ),
        if (!kIsWeb &&
            (GameController().gameRecorder.mainlineMoves.isNotEmpty ||
                GameController().isPositionSetup == true))
          const CustomSpacer(),
        if (!kIsWeb &&
            (GameController().gameRecorder.mainlineMoves.isNotEmpty ||
                GameController().isPositionSetup == true))
          SimpleDialogOption(
            key: const Key('export_game_option'),
            onPressed: () => GameController.export(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).exportGame),
            ),
          ),
        // TODO: Fix iOS bug
        if (DB().generalSettings.gameScreenRecorderSupport && !Platform.isIOS)
          const CustomSpacer(),
        if (DB().generalSettings.gameScreenRecorderSupport && !Platform.isIOS)
          SimpleDialogOption(
            key: const Key('share_gif_option'),
            onPressed: () {
              GameController().gifShare(context);
              Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).shareGIF),
            ),
          ),
        // TODO: Support other platforms (Depend on native_screenshot package)
        if (Constants.isAndroid10Plus == true) const CustomSpacer(),
        if (Constants.isAndroid10Plus == true)
          SimpleDialogOption(
            key: const Key('save_image_option'),
            onPressed: () async {
              Navigator.pop(context);

              // Adding a short delay to ensure the modal has time to close before capturing the screenshot
              await Future<void>.delayed(const Duration(milliseconds: 500));

              onTriggerScreenshot();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).saveImage),
            ),
          ),
        if (DB().generalSettings.screenReaderSupport) const CustomSpacer(),
        if (DB().generalSettings.screenReaderSupport)
          SimpleDialogOption(
            key: const Key('game_options_modal_close_option'),
            onPressed: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).close),
            ),
          ),
      ],
    );
  }

  Future<Widget?> showRestartGameAlertDialog(BuildContext context) async {
    final Widget yesButton = TextButton(
        key: const Key('restart_game_yes_button'),
        child: Text(
          S.of(context).yes,
          style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
        ),
        onPressed: () {
          // TODO: Called stopSearching(); so isEngineGoing is always false?
          if (GameController().isEngineRunning == false) {
            GameController().reset(force: true);

            GameController()
                .headerTipNotifier
                .showTip(S.of(context).gameStarted);
            GameController().headerIconsNotifier.showIcons();

            if (GameController().gameInstance.isAiSideToMove) {
              logger.i("$_logTag New game, AI to move.");

              GameController().engineToGo(context, isMoveNow: false);

              final String side =
                  GameController().position.sideToMove.playerName(context);

              if (DB().ruleSettings.mayMoveInPlacingPhase) {
                GameController()
                    .headerTipNotifier
                    .showTip(S.of(context).tipToMove(side), snackBar: false);
              } else {
                GameController()
                    .headerTipNotifier
                    .showTip(S.of(context).tipPlace, snackBar: false);
              }
            }

            GameController().headerIconsNotifier.showIcons();
          }

          Navigator.of(context, rootNavigator: true).pop(true);
          Navigator.of(context).pop();
        });

    final Widget noButton = TextButton(
      key: const Key('restart_game_no_button'),
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
