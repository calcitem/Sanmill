// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../appearance_settings/widgets/appearance_settings_page.dart';
import '../game_page/services/mill.dart';
import '../game_platform/game_registry.dart';
import '../general_settings/services/config_import_export_service.dart';
import '../general_settings/widgets/general_settings_page.dart';
import '../generated/intl/l10n.dart';
import '../shared/database/database.dart';
import '../shared/services/logger.dart';
import '../shared/themes/app_theme.dart';
import '../shared/widgets/lichess_list_section.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  static const String _logTag = '[settings_hub_page]';

  Future<void> _exportSettings(BuildContext context) async {
    final S strings = S.of(context);
    final bool? success = await ConfigImportExportService.shareConfig(
      shareSubject: strings.configImportShareSubject,
      saveDialogTitle: strings.exportAllSettings,
    );
    if (!context.mounted || success == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? strings.configExportSuccess : strings.configExportFailed,
        ),
      ),
    );
  }

  Future<void> _importSettings(BuildContext context) async {
    FilePickerResult? pickResult;
    try {
      pickResult = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[
          ConfigImportExportService.fileExtension,
          'json',
        ],
      );
    } catch (e, st) {
      logger.e('$_logTag Import file pick failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).configImportErrorReadFailed)),
        );
      }
      return;
    }

    if (pickResult == null ||
        pickResult.files.isEmpty ||
        pickResult.files.single.path == null) {
      return;
    }
    final String filePath = pickResult.files.single.path!;

    if (!context.mounted) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          S.of(ctx).importAllSettings,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        content: Text(S.of(ctx).configImportConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final ConfigImportResult result =
        await ConfigImportExportService.importConfigFromPath(filePath);

    if (!context.mounted) {
      return;
    }

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).configImportSuccess)),
      );
    } else if (!result.userCancelled) {
      final S s = S.of(context);
      final String message = switch (result.errorKind) {
        ConfigImportErrorKind.fileNotFound => s.configImportErrorFileNotFound,
        ConfigImportErrorKind.invalidFile => s.configImportErrorInvalidFile,
        ConfigImportErrorKind.readFailed => s.configImportErrorReadFailed,
        null => s.configImportErrorReadFailed,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _restoreFactoryDefaultSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _SettingsHubResetSettingsDialog(),
    );
  }

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
              cardKey: const Key('settings_hub_settings_card'),
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
            if (!kIsWeb)
              LichessListSection(
                header: Text(strings.configImportExport),
                headerKey: const Key('settings_hub_config_import_export_title'),
                cardKey: const Key('settings_hub_config_import_export_card'),
                children: <Widget>[
                  _SettingsHubActionTile(
                    key: const Key('settings_hub_export_all_settings'),
                    icon: Icons.ios_share_rounded,
                    title: strings.exportAllSettings,
                    onTap: () => _exportSettings(context),
                  ),
                  _SettingsHubActionTile(
                    key: const Key('settings_hub_import_all_settings'),
                    icon: Icons.file_download_outlined,
                    title: strings.importAllSettings,
                    onTap: () => _importSettings(context),
                  ),
                ],
              ),
            LichessListSection(
              header: Text(strings.restore),
              headerKey: const Key('settings_hub_restore_title'),
              cardKey: const Key('settings_hub_restore_card'),
              children: <Widget>[
                _SettingsHubActionTile(
                  key: const Key('settings_hub_restore_default_settings'),
                  icon: Icons.restore_rounded,
                  title: strings.restoreDefaultSettings,
                  onTap: () => _restoreFactoryDefaultSettings(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHubActionTile extends StatelessWidget {
  const _SettingsHubActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(title), onTap: onTap);
  }
}

class _SettingsHubResetSettingsDialog extends StatelessWidget {
  const _SettingsHubResetSettingsDialog();

  void _cancel(BuildContext context) => Navigator.pop(context);

  Future<void> _restore(BuildContext context) async {
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      S.of(context).reopenToTakeEffect,
    );

    Navigator.pop(context);

    // Resetting the DB at runtime does not fully propagate all settings
    // to live widgets; a restart is required for all changes to take effect.
    await DB.reset();

    GameController().reset(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('reset_settings_alert_dialog_alert_dialog'),
      title: Text(
        S.of(context).restore,
        key: const Key('reset_settings_alert_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        key: const Key('reset_settings_alert_dialog_content_scroll_view'),
        child: Text(
          '${S.of(context).restoreDefaultSettings}?',
          key: const Key('reset_settings_alert_dialog_content_text'),
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('reset_settings_alert_dialog_ok_button'),
          onPressed: () => _restore(context),
          child: Text(
            S.of(context).ok,
            key: const Key('reset_settings_alert_dialog_ok_button_text'),
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
        ),
        TextButton(
          key: const Key('reset_settings_alert_dialog_cancel_button'),
          onPressed: () => _cancel(context),
          child: Text(
            S.of(context).cancel,
            key: const Key('reset_settings_alert_dialog_cancel_button_text'),
            style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            ),
          ),
        ),
      ],
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
