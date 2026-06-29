// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_options_modal.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../experience_recording/models/recording_models.dart';
import '../../../experience_recording/services/recording_service.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../shared/config/constants.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/widgets/custom_spacer.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../services/gif_share/gif_share.dart';
import '../../services/mill.dart';
import '../game_page.dart';
import '../saved_games_page.dart';

class GameOptionsModal extends StatelessWidget {
  const GameOptionsModal({super.key, required this.onTriggerScreenshot});

  final VoidCallback onTriggerScreenshot;

  static const String _logTag = "[GameOptionsModal]";

  static String _sideToMoveName(BuildContext context) {
    return GameController().activeBoardView.sideToMove.playerName(context);
  }

  static void startNewGame(BuildContext context) {
    GameController().reset(force: true);

    GameController().headerTipNotifier.showTip(S.of(context).gameStarted);
    GameController().headerIconsNotifier.showIcons();

    logger.i(
      "$_logTag after reset: isAiSideToMove="
      "${GameController().gameInstance.isAiSideToMove}",
    );

    if (GameController().gameInstance.isAiSideToMove) {
      logger.i("$_logTag New game, AI to move; calling engineToGo");

      GameController().engineToGo(context, isMoveNow: false);

      if (GameController().gameInstance.gameMode == GameMode.aiVsAi) {
        GameController().headerTipNotifier.showTip(
          millScoreString,
          snackBar: false,
        );
      } else {
        final String side = _sideToMoveName(context);

        if (DB().ruleSettings.mayMoveInPlacingPhase) {
          GameController().headerTipNotifier.showTip(
            S.of(context).tipToMove(side),
            snackBar: false,
          );
        } else {
          GameController().headerTipNotifier.showTip(
            S.of(context).tipPlace,
            snackBar: false,
          );
        }
      }
    }

    GameController().headerIconsNotifier.showIcons();
  }

  static bool canStartNewGame() {
    if (GameController().activeSessionSnapshot != null) {
      return true;
    }
    // Fallback for the very-early-init window before the native
    // session has been bound; reaches the same conclusion via the
    // legacy phase / recorder state.
    final Phase phase = GameController().activeBoardView.phase;
    return phase == Phase.ready ||
        (phase == Phase.placing &&
            GameController().gameRecorder.mainlineMoves.length <= 3) ||
        phase == Phase.gameOver;
  }

  static Future<void> requestNewGame(
    BuildContext context, {
    bool closeCurrentRoute = false,
  }) async {
    GameController().loadedGameFilenamePrefix = null;

    logger.i(
      "$_logTag New Game pressed: "
      "gameMode=${GameController().gameInstance.gameMode}, "
      "canStart=${canStartNewGame()}, "
      "isEngineRunning=${GameController().isEngineRunning}, "
      "snapshot=${GameController().activeSessionSnapshot != null}",
    );

    if (canStartNewGame()) {
      startNewGame(context);
      if (closeCurrentRoute) {
        Navigator.of(context).pop();
      }
      return;
    }

    await showRestartGameAlertDialog(
      context,
      closeCurrentRoute: closeCurrentRoute,
    );
  }

  static Future<void> showHumanAiNewGameSheet(BuildContext context) async {
    assert(
      GameController().gameInstance.gameMode == GameMode.humanVsAi,
      'The Lichess-style new game sheet is only used for Human vs AI.',
    );
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => const _HumanAiNewGameSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).game,
      children: <Widget>[
        SimpleDialogOption(
          key: const Key('new_game_option'),
          onPressed: () async {
            RecordingService().recordEvent(
              RecordingEventType.dialogAction,
              <String, dynamic>{
                'dialog': 'gameOptions',
                'action': 'select',
                'selection': 'newGame',
              },
            );
            //Navigator.pop(context);

            await requestNewGame(context, closeCurrentRoute: true);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(S.of(context).newGame),
          ),
        ),
        const CustomSpacer(),
        if (GameController().activeNativeMillSession != null)
          SimpleDialogOption(
            key: const Key('setup_position_option'),
            onPressed: () {
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'setupPosition',
                },
              );
              GameController().loadedGameFilenamePrefix = null;
              GameController().enterSetupPosition();
              GameController().headerTipNotifier.showTip(
                S.of(context).setupPosition,
                snackBar: false,
              );
              Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).setupPosition),
            ),
          ),
        if (GameController().activeNativeMillSession != null)
          const CustomSpacer(),
        if (!kIsWeb &&
            (GameController().gameRecorder.mainlineMoves.isNotEmpty ||
                GameController().isPositionSetup == true))
          SimpleDialogOption(
            key: const Key('save_game_option'),
            onPressed: () {
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'save',
                },
              );
              GameController.save(context);
            },
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
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'load',
                },
              );
              GameController().loadedGameFilenamePrefix = null;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/savedGames'),
                  builder: (BuildContext context) => const SavedGamesPage(),
                ),
              );
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
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'import',
                },
              );
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
            onPressed: () {
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'export',
                },
              );
              GameController.export(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).exportGame),
            ),
          ),
        if (supportsGameScreenRecorder &&
            DB().generalSettings.gameScreenRecorderSupport)
          const CustomSpacer(),
        if (supportsGameScreenRecorder &&
            DB().generalSettings.gameScreenRecorderSupport)
          SimpleDialogOption(
            key: const Key('share_gif_option'),
            onPressed: () {
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'shareGif',
                },
              );
              GameController().gifShare(context);
              Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).shareGIF),
            ),
          ),
        // native_screenshot_widget only supports mobile capture; keep this
        // gallery screenshot action limited to Android 10+.
        if (Constants.isAndroid10Plus == true) const CustomSpacer(),
        if (Constants.isAndroid10Plus == true)
          SimpleDialogOption(
            key: const Key('save_image_option'),
            onPressed: () async {
              RecordingService().recordEvent(
                RecordingEventType.dialogAction,
                <String, dynamic>{
                  'dialog': 'gameOptions',
                  'action': 'select',
                  'selection': 'saveImage',
                },
              );
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

  static Future<void> showRestartGameAlertDialog(
    BuildContext context, {
    bool closeCurrentRoute = false,
  }) async {
    final Widget yesButton = TextButton(
      key: const Key('restart_game_yes_button'),
      child: Text(
        S.of(context).yes,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      onPressed: () {
        startNewGame(context);
        Navigator.of(context, rootNavigator: true).pop(true);
        if (closeCurrentRoute) {
          Navigator.of(context).pop();
        }
      },
    );

    final Widget noButton = TextButton(
      key: const Key('restart_game_no_button'),
      child: Text(
        S.of(context).no,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).pop(false);
        if (closeCurrentRoute) {
          Navigator.of(context).pop();
        }
      },
    );

    final AlertDialog alert = AlertDialog(
      title: Text(
        S.of(context).restart,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      content: Text(
        S.of(context).restartGame,
        style: TextStyle(
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        ),
      ),
      actions: <Widget>[yesButton, noButton],
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}

class _HumanAiNewGameSheet extends StatefulWidget {
  const _HumanAiNewGameSheet();

  @override
  State<_HumanAiNewGameSheet> createState() => _HumanAiNewGameSheetState();
}

class _HumanAiNewGameSheetState extends State<_HumanAiNewGameSheet> {
  late int _skillLevel;
  late int _moveTime;
  late bool _aiMovesFirst;

  @override
  void initState() {
    super.initState();
    final GeneralSettings settings = DB().generalSettings;
    _skillLevel = settings.skillLevel.clamp(1, Constants.highestSkillLevel);
    _moveTime = settings.moveTime.clamp(0, 60);
    _aiMovesFirst = settings.aiMovesFirst;
  }

  void _startNewGame(BuildContext context) {
    assert(
      GameController().gameInstance.gameMode == GameMode.humanVsAi,
      'Human vs AI settings cannot start a different game mode.',
    );
    DB().generalSettings = DB().generalSettings.copyWith(
      skillLevel: _skillLevel,
      moveTime: _moveTime,
      aiMovesFirst: _aiMovesFirst,
    );
    if (_skillLevel > 15 && _moveTime < 10) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).noteActualDifficultyLevelMayBeLimited,
      );
    }
    GameOptionsModal.startNewGame(context);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle valueStyle =
        theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ) ??
        AppStyles.sectionTitle.copyWith(color: colorScheme.onSurface);

    return Semantics(
      key: const Key('human_ai_new_game_sheet'),
      namesRoute: true,
      label: S.of(context).newGame,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          MediaQuery.viewInsetsOf(context).bottom + AppStyles.bodyPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppStyles.bodyPadding,
                0,
                AppStyles.bodyPadding,
                AppStyles.bodyPadding,
              ),
              child: Text(
                S.of(context).newGame,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            LichessListSection(
              header: Text(S.of(context).humanVsAi),
              hasLeading: false,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _SheetValueHeader(
                    title: S.of(context).skillLevel,
                    value: _skillLevel.toString(),
                    valueStyle: valueStyle,
                  ),
                ),
                Slider(
                  key: const Key('human_ai_new_game_sheet_skill_slider'),
                  min: 1,
                  max: Constants.highestSkillLevel.toDouble(),
                  divisions: Constants.highestSkillLevel - 1,
                  value: _skillLevel.toDouble(),
                  label: _skillLevel.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _skillLevel = value.round();
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _SheetValueHeader(
                    title: S.of(context).moveTime,
                    value: _moveTime.toString(),
                    valueStyle: valueStyle,
                  ),
                ),
                Slider(
                  key: const Key('human_ai_new_game_sheet_move_time_slider'),
                  max: 60,
                  divisions: 60,
                  value: _moveTime.toDouble(),
                  label: _moveTime.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _moveTime = value.round();
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        S.of(context).human,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                              return ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: SegmentedButton<bool>(
                                    key: const Key(
                                      'human_ai_new_game_sheet_side_picker',
                                    ),
                                    segments: <ButtonSegment<bool>>[
                                      ButtonSegment<bool>(
                                        value: false,
                                        icon: const Icon(Icons.person_outline),
                                        label: Text(S.of(context).player1),
                                      ),
                                      ButtonSegment<bool>(
                                        value: true,
                                        icon: const Icon(Icons.person_outline),
                                        label: Text(S.of(context).player2),
                                      ),
                                    ],
                                    selected: <bool>{_aiMovesFirst},
                                    showSelectedIcon: false,
                                    onSelectionChanged: (Set<bool> selection) {
                                      assert(
                                        selection.length == 1,
                                        'Human side picker must have exactly one value.',
                                      );
                                      setState(() {
                                        _aiMovesFirst = selection.single;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppStyles.bodyPadding,
              ),
              child: FilledButton(
                key: const Key('human_ai_new_game_sheet_start'),
                onPressed: () => _startNewGame(context),
                child: Text(S.of(context).newGame),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetValueHeader extends StatelessWidget {
  const _SheetValueHeader({
    required this.title,
    required this.value,
    required this.valueStyle,
  });

  final String title;
  final String value;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        ),
        Text(value, style: valueStyle),
      ],
    );
  }
}
