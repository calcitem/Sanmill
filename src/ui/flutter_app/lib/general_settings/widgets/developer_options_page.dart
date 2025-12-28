// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// developer_options_page.dart

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../models/general_settings.dart';
import 'dialogs/llm_assisted_development_dialog.dart';
import 'logs_page.dart';

/// Developer options page
///
/// Contains advanced settings and developer tools
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  void _setIsAutoRestart(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(isAutoRestart: value);
  }

  SettingsList _buildDeveloperOptionsList(
    BuildContext context,
    Box<GeneralSettings> box,
    _,
  ) {
    final GeneralSettings generalSettings = box.get(
      DB.generalSettingsKey,
      defaultValue: const GeneralSettings(),
    )!;

    return SettingsList(
      key: const Key('developer_options_page_settings_list'),
      children: <Widget>[
        SettingsCard(
          key: const Key('developer_options_page_settings_card_options'),
          title: Text(
            S.of(context).developerOptions,
            key: const Key(
              'developer_options_page_settings_card_options_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'developer_options_page_settings_card_auto_restart',
              ),
              value: generalSettings.isAutoRestart,
              onChanged: (bool val) => _setIsAutoRestart(generalSettings, val),
              titleString: S.of(context).isAutoRestart,
            ),
            SettingsListTile(
              key: const Key(
                'developer_options_page_settings_card_llm_assisted_development',
              ),
              titleString: S.of(context).llmAssistedDevelopment,
              onTap: () => showDialog(
                context: context,
                builder: (_) => const LlmAssistedDevelopmentDialog(),
              ),
            ),
            SettingsListTile(
              key: const Key('developer_options_page_settings_card_logs'),
              titleString: S.of(context).logs,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const LogsPage(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);

        final Widget page = BlockSemantics(
          key: const Key('developer_options_page_block_semantics'),
          child: Scaffold(
            key: const Key('developer_options_page_scaffold'),
            resizeToAvoidBottomInset: false,
            backgroundColor: useDarkSettingsUi
                ? settingsTheme.scaffoldBackgroundColor
                : AppTheme.lightBackgroundColor,
            appBar: AppBar(
              key: const Key('developer_options_page_app_bar'),
              leading: CustomDrawerIcon.of(context)?.drawerIcon,
              title: Text(
                S.of(context).developerOptions,
                key: const Key('developer_options_page_app_bar_title'),
                style: useDarkSettingsUi
                    ? null
                    : AppTheme.appBarTheme.titleTextStyle,
              ),
            ),
            body: ValueListenableBuilder<Box<GeneralSettings>>(
              key: const Key('developer_options_page_value_listenable_builder'),
              valueListenable: DB().listenGeneralSettings,
              builder: _buildDeveloperOptionsList,
            ),
          ),
        );

        return useDarkSettingsUi
            ? Theme(data: settingsTheme, child: page)
            : page;
      },
    );
  }
}
