// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../../games/mill/mill_variant_localization.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../puzzle/models/rule_variant.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/utils/screen_insets.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../services/mill.dart';
import '../../services/offline_board_clock.dart';
import 'game_options_modal.dart';

Future<bool> prepareOfflineBoardNewGame(BuildContext context) async {
  final bool? confirmed = await Navigator.of(context, rootNavigator: true)
      .push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) => const _OfflineBoardNewGamePage(),
        ),
      );
  return confirmed ?? false;
}

Future<bool> showOfflineBoardNewGameSheet(
  BuildContext context, {
  bool isDismissible = true,
}) async {
  assert(
    GameController().gameInstance.gameMode == GameMode.humanVsHuman,
    'Offline Board setup is only valid for same-device games.',
  );
  final double screenHeight = MediaQuery.heightOf(context);
  final bool? confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
    builder: (BuildContext context) =>
        const _OfflineBoardNewGameSetup(startGameOnConfirm: true),
  );
  return confirmed ?? false;
}

Future<void> showOfflineBoardDisplaySettings(BuildContext context) {
  assert(
    GameController().gameInstance.gameMode == GameMode.humanVsHuman,
    'Offline Board display settings require a same-device game.',
  );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final bool flipAfterMove =
              DB().generalSettings.offlineBoardFlipAfterMove;
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: ScreenInsets.modalBottomSheetPadding(
                  context,
                  extra: AppStyles.bodyPadding,
                ),
              ),
              child: LichessListSection(
                children: <Widget>[
                  SwitchListTile.adaptive(
                    key: const Key('offline_board_display_flip_after_move'),
                    secondary: const Icon(Icons.flip_camera_android_outlined),
                    title: Text(S.of(context).flipBoardAfterMove),
                    value: flipAfterMove,
                    onChanged: (bool value) {
                      DB().generalSettings = DB().generalSettings.copyWith(
                        offlineBoardFlipAfterMove: value,
                      );
                      setModalState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _OfflineBoardNewGamePage extends StatelessWidget {
  const _OfflineBoardNewGamePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('offline_board_new_game_page'),
      appBar: AppBar(title: Text(S.of(context).offlineBoard)),
      body: const _OfflineBoardNewGameSetup(startGameOnConfirm: false),
    );
  }
}

class _OfflineBoardNewGameSetup extends StatefulWidget {
  const _OfflineBoardNewGameSetup({required this.startGameOnConfirm});

  final bool startGameOnConfirm;

  @override
  State<_OfflineBoardNewGameSetup> createState() =>
      _OfflineBoardNewGameSetupState();
}

class _OfflineBoardNewGameSetupState extends State<_OfflineBoardNewGameSetup> {
  late String? _variantId;

  @override
  void initState() {
    super.initState();
    _variantId = RuleVariant.exactCanonicalIdFor(DB().ruleSettings);
  }

  Future<void> _showVariantPicker() async {
    final String? variantId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final String id in RuleVariant.canonicalSettings.keys)
                RadioListTile<String>(
                  key: Key('offline_board_variant_$id'),
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
    if (mounted && variantId != null) {
      setState(() => _variantId = variantId);
    }
  }

  void _startGame() {
    final String? variantId = _variantId;
    if (variantId != null) {
      final RuleSettings rules = RuleVariant.canonicalSettings[variantId]!;
      DB().ruleSettings = rules;
    }
    if (widget.startGameOnConfirm) {
      assert(
        GameController().gameInstance.gameMode == GameMode.humanVsHuman,
        'Offline Board settings cannot start a different game mode.',
      );
      GameOptionsModal.startNewGame(context);
      OfflineBoardClock().reset();
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle valueStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w600,
    );

    return SingleChildScrollView(
      key: const Key('offline_board_new_game_sheet'),
      padding: EdgeInsets.only(
        bottom: ScreenInsets.modalBottomSheetPadding(
          context,
          extra: AppStyles.bodyPadding,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LichessListSection(
            children: <Widget>[
              ListTile(
                key: const Key('offline_board_variant_picker'),
                title: Row(
                  children: <Widget>[
                    Text(S.of(context).variant),
                    const SizedBox(width: AppStyles.bodyPadding),
                    Expanded(
                      child: Text(
                        key: const Key('offline_board_variant_value'),
                        _variantId == null
                            ? S.of(context).custom
                            : localizedMillVariantNameById(
                                S.of(context),
                                _variantId!,
                              ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                        textAlign: TextAlign.end,
                        style: valueStyle,
                      ),
                    ),
                  ],
                ),
                onTap: _showVariantPicker,
              ),
              SwitchListTile.adaptive(
                key: const Key('offline_board_new_game_flip_after_move'),
                secondary: const Icon(Icons.flip_camera_android_outlined),
                title: Text(S.of(context).flipBoardAfterMove),
                value: DB().generalSettings.offlineBoardFlipAfterMove,
                onChanged: (bool value) {
                  DB().generalSettings = DB().generalSettings.copyWith(
                    offlineBoardFlipAfterMove: value,
                  );
                  setState(() {});
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppStyles.bodyPadding,
            ),
            child: FilledButton(
              key: const Key('offline_board_start_button'),
              onPressed: _startGame,
              child: Text(S.of(context).offlineBoardPlay),
            ),
          ),
        ],
      ),
    );
  }
}
