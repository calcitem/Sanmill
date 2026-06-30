// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// advanced_ai_search_page.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _AdvancedAiSearchPage extends StatelessWidget {
  const _AdvancedAiSearchPage({required this.parent});

  final GeneralSettingsPage parent;

  SettingsCard _buildSearchBehaviorCard(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    return SettingsCard(
      key: const Key('advanced_ai_search_page_search_behavior_card'),
      title: Text(
        S.of(context).searchBehaviorSettings,
        key: const Key('advanced_ai_search_page_search_behavior_title'),
      ),
      children: <Widget>[
        SettingsListTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_algorithm',
          ),
          titleString: S.of(context).algorithm,
          trailingString: generalSettings.searchAlgorithm!.name,
          onTap: () => parent._setAlgorithm(context, generalSettings),
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_draw_on_human_experience',
          ),
          value: generalSettings.drawOnHumanExperience,
          onChanged: (bool val) {
            parent._setDrawOnHumanExperience(generalSettings, val);
          },
          titleString: S.of(context).drawOnHumanExperience,
          subtitleString: S.of(context).drawOnTheHumanExperienceDetail,
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_consider_mobility',
          ),
          value: generalSettings.considerMobility,
          onChanged: (bool val) {
            parent._setConsiderMobility(generalSettings, val);
          },
          titleString: S.of(context).considerMobility,
          subtitleString: S.of(context).considerMobilityOfPiecesDetail,
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_focus_on_blocking_paths',
          ),
          value: generalSettings.focusOnBlockingPaths,
          onChanged: (bool val) {
            parent._setFocusOnBlockingPaths(generalSettings, val);
          },
          titleString: S.of(context).focusOnBlockingPaths,
          subtitleString: S.of(context).focusOnBlockingPaths_Detail,
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_ai_is_lazy',
          ),
          value: generalSettings.aiIsLazy,
          onChanged: (bool val) {
            parent._setAiIsLazy(generalSettings, val);
          },
          titleString: S.of(context).passive,
          subtitleString: S.of(context).passiveDetail,
        ),
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
          ),
          value: generalSettings.shufflingEnabled,
          onChanged: (bool val) {
            parent._setShufflingEnabled(generalSettings, val);
          },
          titleString: S.of(context).shufflingEnabled,
          subtitleString: S.of(context).moveRandomlyDetail,
        ),
      ],
    );
  }

  SettingsCard _buildThreadingCard(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    return SettingsCard(
      key: const Key('advanced_ai_search_page_threading_card'),
      title: Text(
        S.of(context).threadingSettings,
        key: const Key('advanced_ai_search_page_threading_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key(
            'general_settings_page_settings_card_ais_play_style_use_lazy_smp',
          ),
          value: generalSettings.useLazySmp,
          onChanged: (bool val) {
            parent._setUseLazySmp(generalSettings, val);
          },
          titleString: S.of(context).useLazySmp,
          subtitleString: S.of(context).useLazySmp_Detail,
        ),
        if (generalSettings.useLazySmp)
          SettingsListTile(
            key: const Key(
              'general_settings_page_settings_card_ais_play_style_engine_threads',
            ),
            titleString: S.of(context).engineThreads,
            subtitleString: S.of(context).engineThreads_Detail,
            trailingString: generalSettings.engineThreads.toString(),
            onTap: () => parent._setEngineThreads(context),
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
      key: const Key('advanced_ai_search_page_settings_list'),
      children: <Widget>[
        _AnimatedSettingsCard(
          child: _buildSearchBehaviorCard(context, generalSettings),
        ),
        _AnimatedSettingsCard(
          child: _buildThreadingCard(context, generalSettings),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _SettingsSubPageScaffold(
    pageKey: const Key('advanced_ai_search_page'),
    titleBuilder: (S strings) => strings.advancedAiSearch,
    settingsBuilder: _buildSettingsList,
  );
}
