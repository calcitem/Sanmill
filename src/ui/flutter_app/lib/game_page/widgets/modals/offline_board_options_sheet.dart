// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

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

Future<void> showOfflineBoardNewGameSheet(
  BuildContext context, {
  bool isDismissible = true,
}) {
  assert(
    GameController().gameInstance.gameMode == GameMode.humanVsHuman,
    'Offline Board setup is only valid for same-device games.',
  );
  final double screenHeight = MediaQuery.heightOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
    builder: (BuildContext context) => const _OfflineBoardNewGameSheet(),
  );
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

class _OfflineBoardNewGameSheet extends StatefulWidget {
  const _OfflineBoardNewGameSheet();

  @override
  State<_OfflineBoardNewGameSheet> createState() =>
      _OfflineBoardNewGameSheetState();
}

class _OfflineBoardNewGameSheetState extends State<_OfflineBoardNewGameSheet> {
  late String _variantId;

  @override
  void initState() {
    super.initState();
    final String currentId = RuleVariant.fromRuleSettings(DB().ruleSettings).id;
    _variantId = RuleVariant.canonicalSettings.containsKey(currentId)
        ? currentId
        : 'standard_9mm';
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
    final RuleSettings rules = RuleVariant.canonicalSettings[_variantId]!;

    DB().ruleSettings = rules;
    GameOptionsModal.startNewGame(context);
    OfflineBoardClock().reset();
    Navigator.of(context).pop();
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
                title: Text(S.of(context).variant),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(
                      160,
                      MediaQuery.sizeOf(context).width * 0.4,
                    ),
                  ),
                  child: Text(
                    localizedMillVariantNameById(S.of(context), _variantId),
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
                onTap: _showVariantPicker,
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
