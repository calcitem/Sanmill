// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// developer_options_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../experience_recording/pages/diagnostic_reproduction_page.dart';
import '../../experience_recording/pages/session_list_page.dart';
import '../../experience_recording/services/diagnostic_action_trail_service.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../games/mill/opening_book/opening_book_studio_page.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/pages/diagnostic_drafts_page.dart';
import '../../shared/services/diagnostic_report_service.dart';
import '../../shared/services/snackbar_service.dart';
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

  void _setExperienceRecordingEnabled(
    BuildContext context,
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings = generalSettings.copyWith(
      experienceRecordingEnabled: value,
    );

    // Stop any active recording when feature is disabled.
    if (!value) {
      RecordingService().stopRecording();
    }
  }

  void _openRecordingSessions(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SessionListPage(),
      ),
    );
  }

  void _setDiagnosticActionTrailEnabled(
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings = generalSettings.copyWith(
      diagnosticActionTrailEnabled: value,
    );
    unawaited(DiagnosticActionTrailService().setEnabled(value));
  }

  Future<void> _clearDiagnosticActionTrail(BuildContext context) async {
    await DiagnosticActionTrailService().clear();
    if (context.mounted) {
      SnackBarService.showRootSnackBar(
        S.of(context).diagnosticActionTrailCleared,
      );
    }
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
            SettingsListTile(
              key: const Key('developer_options_page_opening_book_studio'),
              titleString: S.of(context).openingBookStudio,
              subtitleString: S.of(context).openingBookStudioDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const OpeningBookStudioPage(),
                ),
              ),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('developer_options_page_diagnostic_action_trail'),
          title: Text(S.of(context).diagnosticActionTrail),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key('diagnostic_action_trail_enabled'),
              value: generalSettings.diagnosticActionTrailEnabled,
              onChanged: (bool value) =>
                  _setDiagnosticActionTrailEnabled(generalSettings, value),
              titleString: S.of(context).diagnosticActionTrail,
              subtitleString: S.of(context).diagnosticActionTrailDescription,
            ),
            SettingsListTile(
              key: const Key('diagnostic_action_trail_clear'),
              titleString: S.of(context).diagnosticClearActionTrail,
              trailingString:
                  '${DiagnosticActionTrailService().eventCount} / '
                  '${DiagnosticActionTrailService.maxEvents}',
              onTap: () => _clearDiagnosticActionTrail(context),
            ),
            SettingsListTile(
              key: const Key('diagnostic_paste_and_reproduce'),
              titleString: S.of(context).diagnosticPasteAndReproduce,
              subtitleString: S
                  .of(context)
                  .diagnosticPasteAndReproduceDescription,
              onTap: () =>
                  DiagnosticReproductionPage.importFromClipboard(context),
            ),
            SettingsListTile(
              key: const Key('diagnostic_saved_drafts'),
              titleString: S.of(context).diagnosticSavedDrafts,
              subtitleString: S.of(context).diagnosticSavedDraftsDescription,
              trailingString: DiagnosticReportService().drafts.value.length
                  .toString(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/diagnosticDrafts'),
                  builder: (BuildContext context) =>
                      const DiagnosticDraftsPage(),
                ),
              ),
            ),
          ],
        ),
        SettingsCard(
          key: const Key(
            'developer_options_page_settings_card_experience_recording',
          ),
          title: Text(
            S.of(context).experienceRecording,
            key: const Key(
              'developer_options_page_settings_card_experience_recording_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'developer_options_page_experience_recording_enabled',
              ),
              value: generalSettings.experienceRecordingEnabled,
              onChanged: (bool val) {
                _setExperienceRecordingEnabled(context, generalSettings, val);
                if (val == true) {
                  SnackBarService.showRootSnackBar(S.of(context).experimental);
                }
              },
              titleString: S.of(context).experienceRecording,
              subtitleString: S.of(context).experienceRecordingDescription,
            ),
            SettingsListTile(
              key: const Key('developer_options_page_recording_sessions'),
              titleString: S.of(context).recordingSessions,
              onTap: () => _openRecordingSessions(context),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      key: const Key('developer_options_page_block_semantics'),
      child: Scaffold(
        key: const Key('developer_options_page_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          key: const Key('developer_options_page_app_bar'),
          title: Text(
            S.of(context).developerOptions,
            key: const Key('developer_options_page_app_bar_title'),
          ),
        ),
        body: ValueListenableBuilder<Box<GeneralSettings>>(
          key: const Key('developer_options_page_value_listenable_builder'),
          valueListenable: DB().listenGeneralSettings,
          builder: _buildDeveloperOptionsList,
        ),
      ),
    );
  }
}
