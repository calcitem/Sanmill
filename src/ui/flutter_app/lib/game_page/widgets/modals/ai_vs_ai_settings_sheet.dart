// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../../appearance_settings/models/display_settings.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../shared/config/constants.dart';
import '../../../shared/database/database.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/utils/screen_insets.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../services/mill.dart';

/// Shows computer self-play's focused settings surface.
///
/// Returns true when the caller should open the full computer settings page.
Future<bool> showAiVsAiSettingsSheet(BuildContext context) async {
  final bool? openMoreSettings = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _AiVsAiSettingsSheet(),
  );
  return openMoreSettings ?? false;
}

class _AiVsAiSettingsSheet extends StatefulWidget {
  const _AiVsAiSettingsSheet();

  @override
  State<_AiVsAiSettingsSheet> createState() => _AiVsAiSettingsSheetState();
}

class _AiVsAiSettingsSheetState extends State<_AiVsAiSettingsSheet> {
  late int _skillLevel;
  late int _moveTime;
  late double _animationDuration;
  late bool _autoRestart;

  @override
  void initState() {
    super.initState();
    _skillLevel = DB().generalSettings.skillLevel.clamp(
      1,
      Constants.highestSkillLevel,
    );
    _moveTime = DB().generalSettings.moveTime.clamp(0, 60);
    _animationDuration = DB().displaySettings.animationDuration.clamp(0, 5);
    _autoRestart = DB().generalSettings.isAutoRestart;
  }

  void _setSkillLevel(double value) {
    final int level = value.round().clamp(1, Constants.highestSkillLevel);
    setState(() => _skillLevel = level);
    DB().generalSettings = DB().generalSettings.copyWith(skillLevel: level);
  }

  void _setMoveTime(double value) {
    final int seconds = value.round().clamp(0, 60);
    setState(() => _moveTime = seconds);
    DB().generalSettings = DB().generalSettings.copyWith(moveTime: seconds);
  }

  void _setAnimationDuration(double value) {
    final double seconds = (value * 10).round() / 10;
    setState(() => _animationDuration = seconds);
    DB().displaySettings = DB().displaySettings.copyWith(
      animationDuration: seconds,
    );
  }

  void _setAutoRestart(bool value) {
    setState(() => _autoRestart = value);
    DB().generalSettings = DB().generalSettings.copyWith(isAutoRestart: value);
    if (!value) {
      GameController().cancelPendingAiVsAiAutoRestart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle valueStyle =
        theme.textTheme.titleSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );

    return Semantics(
      key: const Key('ai_vs_ai_settings_sheet'),
      namesRoute: true,
      label: strings.aiVsAiSettings,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppStyles.bodyPadding,
                  0,
                  AppStyles.bodyPadding,
                  AppStyles.bodyPadding,
                ),
                child: Text(
                  strings.aiVsAiSettings,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              LichessListSection(
                header: Text(strings.aiVsAi),
                hasLeading: false,
                children: <Widget>[
                  _SettingsSliderHeader(
                    title: strings.skillLevel,
                    value: '$_skillLevel/${Constants.highestSkillLevel}',
                    valueStyle: valueStyle,
                  ),
                  Slider(
                    key: const Key('ai_vs_ai_settings_skill_slider'),
                    min: 1,
                    max: Constants.highestSkillLevel.toDouble(),
                    divisions: Constants.highestSkillLevel - 1,
                    value: _skillLevel.toDouble(),
                    label: _skillLevel.toString(),
                    semanticFormatterCallback: (double value) =>
                        '${strings.skillLevel}: ${value.round()}',
                    onChanged: _setSkillLevel,
                  ),
                  _SettingsSliderHeader(
                    title: strings.moveTime,
                    value: strings.aiThinkingTimeValue(_moveTime),
                    valueStyle: valueStyle,
                  ),
                  Slider(
                    key: const Key('ai_vs_ai_settings_move_time_slider'),
                    max: 60,
                    divisions: 60,
                    value: _moveTime.toDouble(),
                    label: strings.aiThinkingTimeValue(_moveTime),
                    semanticFormatterCallback: (double value) =>
                        strings.aiThinkingTimeValue(value.round()),
                    onChanged: _setMoveTime,
                  ),
                  _SettingsSliderHeader(
                    title: strings.animationDuration,
                    value: strings.animationDurationValue(_animationDuration),
                    valueStyle: valueStyle,
                  ),
                  Slider(
                    key: const Key('ai_vs_ai_settings_animation_slider'),
                    max: 5,
                    divisions: 50,
                    value: _animationDuration,
                    label: strings.animationDurationValue(_animationDuration),
                    semanticFormatterCallback: (double value) => strings
                        .animationDurationValue((value * 10).round() / 10),
                    onChanged: _setAnimationDuration,
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('ai_vs_ai_settings_auto_restart'),
                    secondary: const Icon(Icons.autorenew_rounded),
                    title: Text(strings.isAutoRestart),
                    value: _autoRestart,
                    onChanged: _setAutoRestart,
                  ),
                ],
              ),
              LichessListSection(
                hasLeading: false,
                children: <Widget>[
                  ListTile(
                    key: const Key('ai_vs_ai_settings_more'),
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(strings.moreComputerSettings),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSliderHeader extends StatelessWidget {
  const _SettingsSliderHeader({
    required this.title,
    required this.value,
    required this.valueStyle,
  });

  final String title;
  final String value;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Text(value, key: ValueKey<String>(value), style: valueStyle),
        ],
      ),
    );
  }
}
