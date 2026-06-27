// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ai_knowledge_sources_page.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _AiKnowledgeSourcesPage extends StatelessWidget {
  const _AiKnowledgeSourcesPage({required this.parent});

  final GeneralSettingsPage parent;

  SettingsCard _buildOpeningBookCard(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    return SettingsCard(
      key: const Key('ai_knowledge_sources_page_opening_book_card'),
      title: Text(
        S.of(context).openingBookSettings,
        key: const Key('ai_knowledge_sources_page_opening_book_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_use_opening_book',
          ),
          value: generalSettings.useOpeningBook,
          onChanged: (bool val) {
            parent._setUseOpeningBook(generalSettings, val);
          },
          titleString: S.of(context).useOpeningBook,
          subtitleString: S.of(context).useOpeningBook_Detail,
        ),
        if (generalSettings.useOpeningBook && generalSettings.shufflingEnabled)
          SettingsListTile(
            key: const Key(
              'general_settings_page_settings_card_ais_play_style_opening_randomness',
            ),
            titleString: S.of(context).openingRandomness,
            trailingString: '${generalSettings.openingRandomness}%',
            onTap: () => parent._setOpeningRandomness(context),
          ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_show_opening_info',
          ),
          value: generalSettings.showOpeningInfo,
          onChanged: (bool val) {
            parent._setShowOpeningInfo(generalSettings, val);
          },
          titleString: S.of(context).showOpeningInfo,
          subtitleString: S.of(context).showOpeningInfo_Detail,
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_prefer_favored_openings',
          ),
          value: generalSettings.preferFavoredOpenings,
          onChanged: (bool val) {
            parent._setPreferFavoredOpenings(generalSettings, val);
          },
          titleString: S.of(context).preferFavoredOpenings,
          subtitleString: S.of(context).preferFavoredOpenings_Detail,
        ),
      ],
    );
  }

  SettingsCard _buildPerfectDatabaseCard(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    final String perfectDatabaseDescriptionFirstLine = _settingsFirstLine(
      S.of(context).perfectDatabaseDescription,
    );

    return SettingsCard(
      key: const Key('ai_knowledge_sources_page_perfect_database_card'),
      title: Text(
        S.of(context).perfectDatabaseSettings,
        key: const Key('ai_knowledge_sources_page_perfect_database_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_use_perfect_database',
          ),
          value: generalSettings.usePerfectDatabase,
          onChanged: (bool val) {
            if (val) {
              parent._showUsePerfectDatabaseDialog(context);
              if (isRuleSupportingPerfectDatabase()) {
                parent._setUsePerfectDatabase(generalSettings, true);
              }
            } else {
              parent._setUsePerfectDatabase(generalSettings, false);
            }
          },
          titleString: S.of(context).usePerfectDatabase,
          subtitleString: perfectDatabaseDescriptionFirstLine,
        ),
        if (generalSettings.usePerfectDatabase &&
            isRuleSupportingPerfectDatabase())
          SettingsListTile.switchTile(
            key: const Key(
              'general_settings_page_settings_card_ais_play_style_trap_awareness',
            ),
            value: generalSettings.trapAwareness,
            onChanged: (bool val) {
              parent._setTrapAwareness(generalSettings, val);
            },
            titleString: S.of(context).trapAwareness,
            subtitleString: S.of(context).trapAwarenessDescription,
          ),
      ],
    );
  }

  SettingsCard _buildHumanDatabaseCard(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    return SettingsCard(
      key: const Key('ai_knowledge_sources_page_human_database_card'),
      title: Text(
        S.of(context).humanGameDatabaseSettings,
        key: const Key('ai_knowledge_sources_page_human_database_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_use_human_database',
          ),
          value: generalSettings.humanDatabaseEnabled,
          onChanged: (bool val) {
            unawaited(
              parent._setHumanDatabaseEnabled(context, generalSettings, val),
            );
          },
          titleString: S.of(context).useHumanGameDatabase,
          subtitleString: S.of(context).useHumanGameDatabase_Detail,
        ),
        SettingsListTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_human_database_file',
          ),
          titleString: S.of(context).humanGameDatabaseFile,
          subtitleString: S.of(context).humanGameDatabaseFile_Detail,
          trailingString: generalSettings.humanDatabaseFilePath.isEmpty
              ? S.of(context).none
              : p.basename(generalSettings.humanDatabaseFilePath),
          onTap: () {
            unawaited(parent._pickHumanDatabaseFile(context, generalSettings));
          },
        ),
        SettingsListTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_download_human_database',
          ),
          titleString: S.of(context).downloadHumanGameDatabase,
          subtitleString: S.of(context).downloadHumanGameDatabase_Detail,
          onTap: () {
            unawaited(parent._downloadHumanDatabase(context));
          },
        ),
        if (generalSettings.humanDatabaseFilePath.isNotEmpty)
          SettingsListTile(
            key: const Key(
              'general_settings_page_settings_card_ais_play_style_clear_human_database_file',
            ),
            titleString: S.of(context).clearHumanGameDatabaseFile,
            onTap: () => parent._clearHumanDatabaseFile(generalSettings),
          ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_show_human_database_stats',
          ),
          value: generalSettings.showHumanDatabaseStats,
          onChanged: (bool val) {
            parent._setShowHumanDatabaseStats(generalSettings, val);
          },
          titleString: S.of(context).showHumanGameDatabaseStats,
          subtitleString: S.of(context).showHumanGameDatabaseStats_Detail,
        ),
      ],
    );
  }

  SettingsList _buildSettingsList(
    BuildContext context,
    Box<GeneralSettings> box,
    Widget? child,
  ) {
    final GeneralSettings generalSettings = box.get(
      DB.generalSettingsKey,
      defaultValue: const GeneralSettings(),
    )!;

    return SettingsList(
      key: const Key('ai_knowledge_sources_page_settings_list'),
      children: <Widget>[
        if (_openingBookSettingsAvailable())
          _AnimatedSettingsCard(
            child: _buildOpeningBookCard(context, generalSettings),
          ),
        if (_humanDatabaseSettingsAvailable())
          _AnimatedSettingsCard(
            child: _buildHumanDatabaseCard(context, generalSettings),
          ),
        if (!kIsWeb)
          _AnimatedSettingsCard(
            child: _buildPerfectDatabaseCard(context, generalSettings),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _SettingsSubPageScaffold(
    pageKey: const Key('ai_knowledge_sources_page'),
    titleBuilder: (S strings) => strings.aiKnowledgeSources,
    settingsBuilder: _buildSettingsList,
  );
}
