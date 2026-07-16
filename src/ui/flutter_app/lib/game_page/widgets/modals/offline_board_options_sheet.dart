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

const List<int> _offlineBoardTimesInSeconds = <int>[
  0,
  15,
  30,
  45,
  60,
  90,
  120,
  180,
  240,
  300,
  360,
  420,
  480,
  540,
  600,
  660,
  720,
  780,
  840,
  900,
  960,
  1020,
  1080,
  1140,
  1200,
  1500,
  1800,
  2100,
  2400,
  2700,
  3600,
  4500,
  5400,
  6300,
  7200,
  8100,
  9000,
  9900,
  10800,
];

const List<int> _offlineBoardIncrementsInSeconds = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  25,
  30,
  35,
  40,
  45,
  60,
  90,
  120,
  150,
  180,
];

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
  late bool _hasClock;
  late int _timeIndex;
  late int _incrementIndex;
  late String _variantId;

  int get _timeSeconds => _offlineBoardTimesInSeconds[_timeIndex];
  int get _incrementSeconds =>
      _offlineBoardIncrementsInSeconds[_incrementIndex];

  @override
  void initState() {
    super.initState();
    final GeneralSettings general = DB().generalSettings;
    _hasClock =
        general.offlineBoardTimeSeconds > 0 ||
        general.offlineBoardIncrementSeconds > 0;
    _timeIndex = _nearestIndex(
      _offlineBoardTimesInSeconds,
      general.offlineBoardTimeSeconds,
    );
    _incrementIndex = _nearestIndex(
      _offlineBoardIncrementsInSeconds,
      general.offlineBoardIncrementSeconds,
    );
    final String currentId = RuleVariant.fromRuleSettings(DB().ruleSettings).id;
    _variantId = RuleVariant.canonicalSettings.containsKey(currentId)
        ? currentId
        : 'standard_9mm';
  }

  int _nearestIndex(List<int> values, int target) {
    int nearest = 0;
    int distance = (values.first - target).abs();
    for (int i = 1; i < values.length; i++) {
      final int candidateDistance = (values[i] - target).abs();
      if (candidateDistance < distance) {
        nearest = i;
        distance = candidateDistance;
      }
    }
    return nearest;
  }

  void _setHasClock(bool value) {
    setState(() {
      _hasClock = value;
      if (value && _timeSeconds == 0 && _incrementSeconds == 0) {
        _timeIndex = _offlineBoardTimesInSeconds.indexOf(300);
        _incrementIndex = _offlineBoardIncrementsInSeconds.indexOf(3);
      }
    });
  }

  Future<void> _showTimeControlPicker() async {
    final bool? hasClock = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          top: false,
          child: LichessListSection(
            header: Text(S.of(context).timeControl),
            children: <Widget>[
              RadioListTile<bool>(
                key: const Key('offline_board_time_control_clock'),
                secondary: const Icon(Icons.timer_outlined),
                title: Text(S.of(context).clock),
                value: true,
                groupValue: _hasClock,
                onChanged: (bool? value) => Navigator.of(context).pop(value),
              ),
              RadioListTile<bool>(
                key: const Key('offline_board_time_control_unlimited'),
                secondary: const Icon(Icons.all_inclusive),
                title: Text(S.of(context).unlimited),
                value: false,
                groupValue: _hasClock,
                onChanged: (bool? value) => Navigator.of(context).pop(value),
              ),
            ],
          ),
        );
      },
    );
    if (mounted && hasClock != null) {
      _setHasClock(hasClock);
    }
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
    final int timeSeconds = _hasClock ? _timeSeconds : 0;
    final int incrementSeconds = _hasClock ? _incrementSeconds : 0;
    final RuleSettings rules = RuleVariant.canonicalSettings[_variantId]!;

    DB().generalSettings = DB().generalSettings.copyWith(
      offlineBoardTimeSeconds: timeSeconds,
      offlineBoardIncrementSeconds: incrementSeconds,
    );
    DB().ruleSettings = rules;
    GameOptionsModal.startNewGame(context);
    OfflineBoardClock().setup(
      initialTime: Duration(seconds: timeSeconds),
      increment: Duration(seconds: incrementSeconds),
      activeSide: GameController().activeBoardView.sideToMove,
    );
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
                key: const Key('offline_board_time_control_picker'),
                title: Text(S.of(context).timeControl),
                trailing: Text(
                  _hasClock ? S.of(context).clock : S.of(context).unlimited,
                  style: valueStyle,
                ),
                onTap: _showTimeControlPicker,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.topCenter,
                child: !_hasClock
                    ? const SizedBox.shrink()
                    : Column(
                        children: <Widget>[
                          ListTile(
                            title: Text.rich(
                              TextSpan(
                                text: '${S.of(context).minutesPerSide}: ',
                                children: <InlineSpan>[
                                  TextSpan(
                                    text: _clockLabelInMinutes(_timeSeconds),
                                    style: valueStyle,
                                  ),
                                ],
                              ),
                            ),
                            subtitle: Slider(
                              key: const Key(
                                'offline_board_minutes_per_side_slider',
                              ),
                              min: 0,
                              max: (_offlineBoardTimesInSeconds.length - 1)
                                  .toDouble(),
                              divisions: _offlineBoardTimesInSeconds.length - 1,
                              value: _timeIndex.toDouble(),
                              label: _clockLabelInMinutes(_timeSeconds),
                              onChanged: (double value) =>
                                  setState(() => _timeIndex = value.round()),
                            ),
                          ),
                          ListTile(
                            title: Text.rich(
                              TextSpan(
                                text: '${S.of(context).incrementInSeconds}: ',
                                children: <InlineSpan>[
                                  TextSpan(
                                    text: _incrementSeconds.toString(),
                                    style: valueStyle,
                                  ),
                                ],
                              ),
                            ),
                            subtitle: Slider(
                              key: const Key('offline_board_increment_slider'),
                              min: 0,
                              max: (_offlineBoardIncrementsInSeconds.length - 1)
                                  .toDouble(),
                              divisions:
                                  _offlineBoardIncrementsInSeconds.length - 1,
                              value: _incrementIndex.toDouble(),
                              label: _incrementSeconds.toString(),
                              onChanged: (double value) => setState(
                                () => _incrementIndex = value.round(),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
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

String _clockLabelInMinutes(int seconds) {
  return switch (seconds) {
    0 => '0',
    15 => '¼',
    30 => '½',
    45 => '¾',
    _ => (seconds / 60).toString().replaceAll('.0', ''),
  };
}
