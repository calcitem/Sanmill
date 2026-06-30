// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appearance_settings/widgets/appearance_settings_page.dart';
import '../game_platform/game_registry.dart';
import '../general_settings/widgets/general_settings_page.dart';
import '../generated/intl/l10n.dart';
import '../shared/widgets/lichess_list_section.dart';

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final bool hasRuleSettings =
        GameRegistry.instance.current.buildRuleSettingsScreen(context) != null;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListTileTheme.merge(
        iconColor: Theme.of(context).colorScheme.primary,
        child: ListView(
          key: const Key('settings_hub_list'),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: <Widget>[
            LichessListSection(
              header: Text(strings.settings),
              headerKey: const Key('settings_hub_group'),
              children: <Widget>[
                _SettingsHubTile(
                  key: const Key('settings_hub_general_settings'),
                  icon: Icons.tune_rounded,
                  title: strings.generalSettings,
                  pageBuilder: (_) => const GeneralSettingsPage(),
                ),
                if (hasRuleSettings)
                  _SettingsHubTile(
                    key: const Key('settings_hub_rule_settings'),
                    icon: Icons.rule_rounded,
                    title: strings.ruleSettings,
                    pageBuilder: (BuildContext context) {
                      final Widget? page = GameRegistry.instance.current
                          .buildRuleSettingsScreen(context);
                      assert(
                        page != null,
                        'Rule settings page is unavailable.',
                      );
                      return page!;
                    },
                  ),
                _SettingsHubTile(
                  key: const Key('settings_hub_appearance'),
                  icon: Icons.grid_view_rounded,
                  title: strings.board,
                  pageBuilder: (_) => const AppearanceSettingsPage(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHubTile extends StatelessWidget {
  const _SettingsHubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.pageBuilder,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const CupertinoListTileChevron()
          : null,
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: pageBuilder));
      },
    );
  }
}
