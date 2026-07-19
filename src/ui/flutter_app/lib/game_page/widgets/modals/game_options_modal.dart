// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_options_modal.dart

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../experience_recording/models/recording_models.dart';
import '../../../experience_recording/services/recording_service.dart';
import '../../../games/mill/mill_variant_localization.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../puzzle/models/rule_variant.dart';
import '../../../shared/config/constants.dart';
import '../../../shared/database/database.dart';
import '../../../shared/services/accessibility_status.dart';
import '../../../shared/services/logger.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/themes/app_theme.dart';
import '../../../shared/utils/screen_insets.dart';
import '../../../shared/widgets/custom_spacer.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../services/gif_share/gif_share.dart';
import '../../services/mill.dart';
import '../game_page.dart';
import '../saved_games_page.dart';

double _skillLevelSliderProgress(int level) {
  assert(
    level >= 1 && level <= Constants.highestSkillLevel,
    'Computer level must be within the supported range.',
  );
  return level / Constants.highestSkillLevel;
}

int _skillLevelFromSliderProgress(double progress) {
  assert(
    progress >= 0 && progress <= 1,
    'Computer level slider progress must be between zero and one.',
  );
  return math.max(
    1,
    math.min(
      Constants.highestSkillLevel,
      (progress * Constants.highestSkillLevel).round(),
    ),
  );
}

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

  static Future<bool> prepareHumanAiNewGame(BuildContext context) {
    return showHumanAiNewGameSheet(context, startGameOnConfirm: false);
  }

  static Future<bool> showHumanAiNewGameSheet(
    BuildContext context, {
    bool startGameOnConfirm = true,
  }) async {
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          _HumanAiNewGameSheet(startGameOnConfirm: startGameOnConfirm),
    );
    return confirmed ?? false;
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
                S.of(context).boardEditor,
                snackBar: false,
              );
              Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).boardEditor),
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
              child: Text(S.of(context).importGameFromClipboard),
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
              child: Text(S.of(context).copyGameToClipboard),
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
        if (AccessibilityStatus.isScreenReaderActive) const CustomSpacer(),
        if (AccessibilityStatus.isScreenReaderActive)
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
  const _HumanAiNewGameSheet({required this.startGameOnConfirm});

  final bool startGameOnConfirm;

  @override
  State<_HumanAiNewGameSheet> createState() => _HumanAiNewGameSheetState();
}

enum _HumanAiSideChoice { white, random, black }

class _HumanAiNewGameSheetState extends State<_HumanAiNewGameSheet> {
  late int _skillLevel;
  late int _moveTime;
  late _HumanAiSideChoice _sideChoice;
  late bool _showGameTips;
  late String? _variantId;

  @override
  void initState() {
    super.initState();
    final GeneralSettings settings = DB().generalSettings;
    _skillLevel = settings.skillLevel.clamp(1, Constants.highestSkillLevel);
    _moveTime = settings.moveTime.clamp(0, 60);
    _sideChoice = settings.aiMovesFirst
        ? _HumanAiSideChoice.black
        : _HumanAiSideChoice.white;
    _showGameTips = settings.showGameTips;
    _variantId = RuleVariant.exactCanonicalIdFor(DB().ruleSettings);
  }

  void _startNewGame(BuildContext context) {
    if (widget.startGameOnConfirm) {
      assert(
        GameController().gameInstance.gameMode == GameMode.humanVsAi,
        'Human vs AI settings cannot start a different game mode.',
      );
    }
    final bool aiMovesFirst = switch (_sideChoice) {
      _HumanAiSideChoice.white => false,
      _HumanAiSideChoice.black => true,
      _HumanAiSideChoice.random => math.Random().nextBool(),
    };
    DB().generalSettings = DB().generalSettings.copyWith(
      skillLevel: _skillLevel,
      moveTime: _moveTime,
      aiMovesFirst: aiMovesFirst,
      showGameTips: _showGameTips,
    );
    final String? variantId = _variantId;
    if (variantId != null) {
      DB().ruleSettings = RuleVariant.canonicalSettings[variantId]!;
    }
    if (_skillLevel > 15 && _moveTime < 10) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).noteActualDifficultyLevelMayBeLimited,
      );
    }
    if (widget.startGameOnConfirm) {
      GameOptionsModal.startNewGame(context);
    }
    Navigator.of(context).pop(true);
  }

  String _sideChoiceLabel(BuildContext context, _HumanAiSideChoice choice) {
    return switch (choice) {
      _HumanAiSideChoice.white => S.of(context).white,
      _HumanAiSideChoice.random => S.of(context).randomColor,
      _HumanAiSideChoice.black => S.of(context).black,
    };
  }

  IconData _sideChoiceIcon(_HumanAiSideChoice choice) {
    return switch (choice) {
      _HumanAiSideChoice.white => Icons.person_outline_rounded,
      _HumanAiSideChoice.random => Icons.shuffle_rounded,
      _HumanAiSideChoice.black => Icons.smart_toy_outlined,
    };
  }

  Future<void> _showSidePicker(BuildContext context) async {
    final _HumanAiSideChoice?
    selected = await showModalBottomSheet<_HumanAiSideChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final ColorScheme colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: EdgeInsets.only(
            bottom: ScreenInsets.modalBottomSheetPadding(
              context,
              extra: AppStyles.bodyPadding,
            ),
          ),
          child: LichessListSection(
            header: Text(S.of(context).side),
            children: <Widget>[
              for (final _HumanAiSideChoice choice in _HumanAiSideChoice.values)
                ListTile(
                  key: Key('human_ai_new_game_sheet_side_${choice.name}'),
                  leading: Icon(_sideChoiceIcon(choice)),
                  title: Text(_sideChoiceLabel(context, choice)),
                  trailing: choice == _sideChoice
                      ? Icon(Icons.check_rounded, color: colorScheme.primary)
                      : null,
                  selected: choice == _sideChoice,
                  selectedColor: colorScheme.primary,
                  onTap: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _sideChoice = selected;
    });
  }

  Future<void> _showVariantPicker(BuildContext context) async {
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Text(
                  S.of(context).chooseRulePreset,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final String id in RuleVariant.canonicalSettings.keys)
                RadioListTile<String>(
                  key: Key('human_ai_new_game_sheet_variant_$id'),
                  title: Text(localizedMillVariantNameById(S.of(context), id)),
                  value: id,
                  groupValue: _variantId,
                  onChanged: (String? value) =>
                      Navigator.of(context).pop(value),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _variantId = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String moveTimeLabel = S.of(context).aiThinkingTimeValue(_moveTime);
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
          ScreenInsets.modalBottomSheetPadding(
            context,
            extra: AppStyles.bodyPadding,
          ),
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
                    title: S.of(context).humanAiRobotLevel(_skillLevel),
                    valueStyle: valueStyle,
                  ),
                ),
                Slider(
                  key: const Key('human_ai_new_game_sheet_skill_slider'),
                  divisions: Constants.highestSkillLevel,
                  value: _skillLevelSliderProgress(_skillLevel),
                  label: _skillLevel.toString(),
                  semanticFormatterCallback: (double progress) => S
                      .of(context)
                      .humanAiRobotLevel(
                        _skillLevelFromSliderProgress(progress),
                      ),
                  onChanged: (double progress) {
                    setState(() {
                      _skillLevel = _skillLevelFromSliderProgress(progress);
                    });
                  },
                ),
                _SheetOptionTile(
                  key: const Key('human_ai_new_game_sheet_variant_picker'),
                  title: S.of(context).ruleSet,
                  value: _variantId == null
                      ? S.of(context).custom
                      : localizedMillVariantNameById(
                          S.of(context),
                          _variantId!,
                        ),
                  leadingIcon: Icons.category_outlined,
                  onTap: () => _showVariantPicker(context),
                ),
                _SheetOptionTile(
                  key: const Key('human_ai_new_game_sheet_side_picker'),
                  title: S.of(context).side,
                  value: _sideChoiceLabel(context, _sideChoice),
                  leadingIcon: _sideChoiceIcon(_sideChoice),
                  onTap: () => _showSidePicker(context),
                ),
                SwitchListTile.adaptive(
                  key: const Key('human_ai_new_game_sheet_game_tips'),
                  secondary: const Icon(Icons.chat_bubble_outline_rounded),
                  title: Text(S.of(context).showGameTips),
                  subtitle: Text(S.of(context).showGameTips_Detail),
                  value: _showGameTips,
                  onChanged: (bool value) {
                    setState(() {
                      _showGameTips = value;
                    });
                  },
                ),
              ],
            ),
            LichessListSection(
              header: Text(S.of(context).advanced),
              hasLeading: false,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _SheetValueHeader(
                    title: S.of(context).moveTime,
                    value: moveTimeLabel,
                    valueStyle: valueStyle,
                  ),
                ),
                Slider(
                  key: const Key('human_ai_new_game_sheet_move_time_slider'),
                  max: 60,
                  divisions: 60,
                  value: _moveTime.toDouble(),
                  label: moveTimeLabel,
                  semanticFormatterCallback: (double value) =>
                      S.of(context).aiThinkingTimeValue(value.round()),
                  onChanged: (double value) {
                    setState(() {
                      _moveTime = value.round();
                    });
                  },
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
                child: Text(S.of(context).play),
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
    required this.valueStyle,
    this.value,
  });

  final String title;
  final String? value;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        ),
        if (value != null) Text(value!, style: valueStyle),
      ],
    );
  }
}

class _SheetOptionTile extends StatelessWidget {
  const _SheetOptionTile({
    super.key,
    required this.title,
    required this.value,
    required this.leadingIcon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData leadingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(leadingIcon),
      title: Text(title, style: theme.textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.32,
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: AppStyles.subtitleOpacity,
                ),
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant.withValues(
              alpha: AppStyles.subtitleOpacity,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
