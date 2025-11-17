// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_assistant_settings_page.dart

import 'package:flutter/material.dart';

import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/snackbar_service.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../models/voice_assistant_settings.dart';
import '../services/model_downloader.dart';
import '../services/voice_assistant_service.dart';

part 'dialogs/download_model_dialog.dart';
part 'dialogs/model_info_dialog.dart';

/// Voice Assistant Settings page
class VoiceAssistantSettingsPage extends StatefulWidget {
  const VoiceAssistantSettingsPage({super.key});

  @override
  State<VoiceAssistantSettingsPage> createState() =>
      _VoiceAssistantSettingsPageState();
}

class _VoiceAssistantSettingsPageState
    extends State<VoiceAssistantSettingsPage> {
  final VoiceAssistantService _service = VoiceAssistantService();

  @override
  Widget build(BuildContext context) {
    final S loc = S.of(context);

    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        leading: CustomDrawerIcon.of(context)?.drawerIcon,
        title: Text(loc.voiceAssistant),
      ),
      body: ValueListenableBuilder<Object>(
        valueListenable: DB().listenVoiceAssistantSettings,
        builder: (BuildContext context, Object _, Widget? __) {
          final VoiceAssistantSettings settings = DB().voiceAssistantSettings;

          return ListView(
            children: <Widget>[
              // Enable/Disable Voice Assistant
              SettingsCard(
                title: Text(loc.voiceAssistantGeneral),
                children: <Widget>[
                  SettingsListTile.switchTile(
                    titleString: loc.voiceAssistantEnabled,
                    value: settings.enabled,
                    onChanged: (bool value) => _toggleVoiceAssistant(value),
                  ),
                  if (settings.enabled) ...<Widget>[
                    SettingsListTile.switchTile(
                      titleString: loc.voiceAssistantShowButton,
                      value: settings.showVoiceButton,
                      onChanged: (bool value) {
                        DB().voiceAssistantSettings =
                            settings.copyWith(showVoiceButton: value);
                      },
                    ),
                    SettingsListTile.switchTile(
                      titleString: loc.voiceAssistantContinuousListening,
                      value: settings.continuousListening,
                      onChanged: (bool value) {
                        DB().voiceAssistantSettings =
                            settings.copyWith(continuousListening: value);
                      },
                    ),
                  ],
                ],
              ),

              // Model Settings
              if (settings.enabled)
                SettingsCard(
                  title: Text(loc.voiceAssistantModel),
                  children: <Widget>[
                    SettingsListTile(
                      titleString: loc.voiceAssistantModelType,
                      subtitleString: settings.modelType.name,
                      onTap: () => _showModelTypeDialog(),
                    ),
                    SettingsListTile(
                      titleString: loc.voiceAssistantLanguage,
                      subtitleString: settings.language,
                      onTap: () => _showLanguageDialog(),
                    ),
                    SettingsListTile.switchTile(
                      titleString: loc.voiceAssistantAutoDetectLanguage,
                      value: settings.autoDetectLanguage,
                      onChanged: (bool value) {
                        DB().voiceAssistantSettings =
                            settings.copyWith(autoDetectLanguage: value);
                      },
                    ),
                  ],
                ),

              // Model Management
              if (settings.enabled)
                SettingsCard(
                  title: Text(loc.voiceAssistantModelManagement),
                  children: <Widget>[
                    SettingsListTile(
                      titleString: loc.voiceAssistantDownloadModel,
                      subtitleString: settings.modelDownloaded
                          ? loc.voiceAssistantModelDownloaded
                          : loc.voiceAssistantModelNotDownloaded,
                      onTap: () => _downloadModel(),
                    ),
                    if (settings.modelDownloaded)
                      SettingsListTile(
                        titleString: loc.voiceAssistantDeleteModel,
                        onTap: () => _deleteModel(),
                      ),
                    SettingsListTile(
                      titleString: loc.voiceAssistantModelInfo,
                      onTap: () => _showModelInfo(),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  /// Toggle voice assistant on/off
  Future<void> _toggleVoiceAssistant(bool enabled) async {
    if (enabled) {
      // Enable voice assistant
      final bool success = await _service.enable(context);
      if (!success && mounted) {
        SnackBarService.showRootSnackBar(
          S.of(context).voiceAssistantEnableFailed,
        );
      }
    } else {
      // Disable voice assistant
      await _service.disable();
    }
  }

  /// Show model type selection dialog
  Future<void> _showModelTypeDialog() async {
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;
    final S loc = S.of(context);

    final WhisperModelType? selectedType = await showDialog<WhisperModelType>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(loc.voiceAssistantSelectModelType),
          children: WhisperModelType.values.map((WhisperModelType type) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, type),
              child: ListTile(
                title: Text(type.name),
                trailing: settings.modelType == type
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );

    if (selectedType != null && selectedType != settings.modelType) {
      final bool hasModel = await _service.changeModelType(
        selectedType,
        context,
      );

      if (!hasModel && mounted) {
        SnackBarService.showRootSnackBar(
          loc.voiceAssistantModelNotDownloaded,
        );
      }
    }
  }

  /// Show language selection dialog
  Future<void> _showLanguageDialog() async {
    final VoiceAssistantSettings settings = DB().voiceAssistantSettings;
    final S loc = S.of(context);

    // Common languages
    final List<Map<String, String>> languages = <Map<String, String>>[
      <String, String>{'code': 'en', 'name': 'English'},
      <String, String>{'code': 'zh', 'name': '中文'},
      <String, String>{'code': 'de', 'name': 'Deutsch'},
      <String, String>{'code': 'es', 'name': 'Español'},
      <String, String>{'code': 'fr', 'name': 'Français'},
      <String, String>{'code': 'ja', 'name': '日本語'},
      <String, String>{'code': 'ko', 'name': '한국어'},
      <String, String>{'code': 'ru', 'name': 'Русский'},
    ];

    final String? selectedLanguage = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(loc.voiceAssistantSelectLanguage),
          children: languages.map((Map<String, String> lang) {
            final String code = lang['code']!;
            final String name = lang['name']!;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, code),
              child: ListTile(
                title: Text(name),
                trailing: settings.language == code
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );

    if (selectedLanguage != null && selectedLanguage != settings.language) {
      DB().voiceAssistantSettings = settings.copyWith(
        language: selectedLanguage,
        modelDownloaded: false,
        modelPath: '',
      );

      if (mounted) {
        SnackBarService.showRootSnackBar(
          loc.voiceAssistantLanguageChanged,
        );
      }
    }
  }

  /// Download model
  Future<void> _downloadModel() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const _DownloadModelDialog(),
    );

    if (confirmed == true && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => _DownloadProgressDialog(
          service: _service,
        ),
      );
    }
  }

  /// Delete model
  Future<void> _deleteModel() async {
    final S loc = S.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(loc.voiceAssistantDeleteModel),
          content: Text(loc.voiceAssistantDeleteModelConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(loc.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(loc.delete),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final bool success = await _service.deleteModel();
      if (mounted) {
        SnackBarService.showRootSnackBar(
          success
              ? loc.voiceAssistantModelDeleted
              : loc.voiceAssistantDeleteFailed,
        );
      }
    }
  }

  /// Show model info dialog
  Future<void> _showModelInfo() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => const _ModelInfoDialog(),
    );
  }
}
