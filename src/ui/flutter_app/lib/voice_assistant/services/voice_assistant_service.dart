// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_assistant_service.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/voice_assistant_settings.dart';
import 'model_downloader.dart';
import 'speech_recognition_service.dart';
import 'voice_command_processor.dart';

/// Main voice assistant service that coordinates all voice-related functionality
class VoiceAssistantService {
  factory VoiceAssistantService() => _instance;

  VoiceAssistantService._internal();

  static final VoiceAssistantService _instance =
      VoiceAssistantService._internal();

  final ModelDownloader _modelDownloader = ModelDownloader();
  final SpeechRecognitionService _speechRecognition =
      SpeechRecognitionService();
  final VoiceCommandProcessor _commandProcessor = VoiceCommandProcessor();

  /// Whether the service is ready to use
  bool get isReady =>
      _speechRecognition.isInitialized && settings.modelDownloaded;

  /// Whether actively listening
  bool get isListening => _speechRecognition.isListening;

  /// Current settings
  VoiceAssistantSettings get settings => DB().voiceAssistantSettings;

  /// Model downloader
  ModelDownloader get modelDownloader => _modelDownloader;

  /// Speech recognition service
  SpeechRecognitionService get speechRecognition => _speechRecognition;

  /// Initialize the voice assistant
  ///
  /// Should be called when the app starts if voice assistant is enabled
  Future<bool> initialize() async {
    if (!settings.enabled) {
      logger.i('Voice assistant is disabled');
      return false;
    }

    if (!settings.modelDownloaded || settings.modelPath.isEmpty) {
      logger.w('Voice assistant model not downloaded');
      return false;
    }

    try {
      final bool success = await _speechRecognition.initialize(
        settings.modelPath,
        settings.language,
      );

      if (success) {
        logger.i('Voice assistant initialized successfully');
      } else {
        logger.e('Failed to initialize voice assistant');
      }

      return success;
    } catch (e, stackTrace) {
      logger.e('Failed to initialize voice assistant',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Enable voice assistant
  ///
  /// [context] - BuildContext for showing dialogs
  /// Returns true if successfully enabled
  Future<bool> enable(BuildContext context) async {
    final VoiceAssistantSettings currentSettings = settings;

    // Check if model is downloaded
    if (!currentSettings.modelDownloaded) {
      // Show download dialog
      final bool? shouldDownload = await _showDownloadDialog(context);
      if (shouldDownload != true) {
        return false;
      }

      // Download model
      if (!context.mounted) {
        return false;
      }
      final bool downloadSuccess = await downloadModel(context);
      if (!downloadSuccess) {
        return false;
      }
    } else {
      // Model is already downloaded, ask if user wants to re-download
      if (!context.mounted) {
        return false;
      }
      final bool? shouldRedownload = await _showRedownloadConfirmDialog(context);
      if (shouldRedownload == true) {
        // User wants to re-download, delete old model first
        await deleteModel();

        if (!context.mounted) {
          return false;
        }
        final bool downloadSuccess = await downloadModel(context);
        if (!downloadSuccess) {
          return false;
        }
      }
    }

    // Initialize speech recognition
    final bool initSuccess = await initialize();
    if (!initSuccess) {
      return false;
    }

    // Update settings
    DB().voiceAssistantSettings =
        DB().voiceAssistantSettings.copyWith(enabled: true);

    return true;
  }

  /// Disable voice assistant
  Future<void> disable() async {
    await _speechRecognition.dispose();
    DB().voiceAssistantSettings = settings.copyWith(enabled: false);
    logger.i('Voice assistant disabled');
  }

  /// Download the Whisper model
  ///
  /// [context] - BuildContext for getting current language
  Future<bool> downloadModel(BuildContext context) async {
    final VoiceAssistantSettings currentSettings = settings;

    try {
      // Determine language from settings or app locale
      String language = currentSettings.language;
      if (currentSettings.autoDetectLanguage) {
        language = Localizations.localeOf(context).languageCode;
      }

      // Check if already downloaded
      final bool alreadyDownloaded = await _modelDownloader.isModelDownloaded(
        currentSettings.modelType,
        language,
      );

      if (alreadyDownloaded) {
        final String modelPath = await _modelDownloader.getModelPath(
          currentSettings.modelType,
          language,
        );
        DB().voiceAssistantSettings = currentSettings.copyWith(
          modelDownloaded: true,
          modelPath: modelPath,
          language: language,
        );
        logger.i('Model already downloaded: $modelPath');
        return true;
      }

      // Download model
      final String? downloadedPath = await _modelDownloader.downloadModel(
        modelType: currentSettings.modelType,
        language: language,
      );

      if (downloadedPath != null) {
        DB().voiceAssistantSettings = currentSettings.copyWith(
          modelDownloaded: true,
          modelPath: downloadedPath,
          language: language,
        );
        logger.i('Model downloaded successfully: $downloadedPath');
        return true;
      } else {
        logger.e('Failed to download model');
        return false;
      }
    } catch (e, stackTrace) {
      logger.e('Failed to download model', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Delete the downloaded model
  Future<bool> deleteModel() async {
    try {
      final bool deleted = await _modelDownloader.deleteModel(
        settings.modelType,
        settings.language,
      );

      if (deleted) {
        DB().voiceAssistantSettings = settings.copyWith(
          modelDownloaded: false,
          modelPath: '',
        );
        await _speechRecognition.dispose();
        logger.i('Model deleted successfully');
      }

      return deleted;
    } catch (e, stackTrace) {
      logger.e('Failed to delete model', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Start listening for voice commands
  ///
  /// [context] - BuildContext for processing commands
  Future<VoiceCommandResult?> startListening(BuildContext context) async {
    if (!isReady) {
      logger.e('Voice assistant not ready');
      return null;
    }

    try {
      // Start listening
      final String? recognizedText = await _speechRecognition.startListening();

      if (recognizedText == null || recognizedText.isEmpty) {
        logger.w('No speech recognized');
        return null;
      }

      // Process command
      if (!context.mounted) {
        return null;
      }
      final VoiceCommandResult result =
          await _commandProcessor.processCommand(recognizedText, context);

      logger.i(
          'Command processed: ${result.type}, success: ${result.success}');
      return result;
    } catch (e, stackTrace) {
      logger.e('Failed to process voice command',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _speechRecognition.stopListening();
  }

  /// Show re-download confirmation dialog
  Future<bool?> _showRedownloadConfirmDialog(BuildContext context) async {
    final S loc = S.of(context);

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(loc.voiceAssistantRedownloadModel),
          content: Text(loc.voiceAssistantRedownloadModelMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(loc.no),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(loc.yes),
            ),
          ],
        );
      },
    );
  }

  /// Show download confirmation dialog
  Future<bool?> _showDownloadDialog(BuildContext context) async {
    final VoiceAssistantSettings currentSettings = settings;
    final S loc = S.of(context);
    final String localeLanguage = Localizations.localeOf(context).languageCode;
    final List<Map<String, String>> languages = <Map<String, String>>[
      <String, String>{'code': localeLanguage, 'name': localeLanguage},
      <String, String>{'code': 'en', 'name': 'English'},
      <String, String>{'code': 'zh', 'name': '中文'},
      <String, String>{'code': 'de', 'name': 'Deutsch'},
      <String, String>{'code': 'es', 'name': 'Español'},
      <String, String>{'code': 'fr', 'name': 'Français'},
      <String, String>{'code': 'ja', 'name': '日本語'},
      <String, String>{'code': 'ko', 'name': '한국어'},
      <String, String>{'code': 'ru', 'name': 'Русский'},
    ];

    final Set<String> seenCodes = <String>{};
    final List<Map<String, String>> uniqueLanguages = languages
        .where((Map<String, String> lang) => seenCodes.add(lang['code']!))
        .toList();

    String selectedLanguage = currentSettings.autoDetectLanguage
        ? localeLanguage
        : currentSettings.language;

    if (!uniqueLanguages
        .any((Map<String, String> lang) => lang['code'] == selectedLanguage)) {
      uniqueLanguages.insert(
        0,
        <String, String>{
          'code': selectedLanguage,
          'name': selectedLanguage,
        },
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            final String modelName = currentSettings.modelType.name;
            return AlertDialog(
              title: Text(loc.voiceAssistantDownloadModel),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('${loc.voiceAssistantDownloadModelMessage}\n'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${loc.model}: $modelName'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(loc.voiceAssistantSelectLanguage),
                    subtitle: DropdownButton<String>(
                      value: selectedLanguage,
                      isExpanded: true,
                      onChanged: (String? value) {
                        if (value != null) {
                          setState(() {
                            selectedLanguage = value;
                          });
                        }
                      },
                      items: uniqueLanguages
                          .map(
                            (Map<String, String> lang) => DropdownMenuItem<String>(
                              value: lang['code'],
                              child: Text('${lang['name']} (${lang['code']})'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(loc.cancel),
                ),
                TextButton(
                  onPressed: () {
                    DB().voiceAssistantSettings =
                        DB().voiceAssistantSettings.copyWith(
                      language: selectedLanguage,
                      modelDownloaded: false,
                      modelPath: '',
                    );
                    Navigator.of(context).pop(true);
                  },
                  child: Text(loc.download),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Change model type
  Future<bool> changeModelType(
    WhisperModelType newType,
    BuildContext context,
  ) async {
    final VoiceAssistantSettings currentSettings = settings;

    // Check if new model is already downloaded
    final bool isDownloaded = await _modelDownloader.isModelDownloaded(
      newType,
      currentSettings.language,
    );

    if (isDownloaded) {
      final String modelPath = await _modelDownloader.getModelPath(
        newType,
        currentSettings.language,
      );

      // Update settings
      DB().voiceAssistantSettings = currentSettings.copyWith(
        modelType: newType,
        modelPath: modelPath,
        modelDownloaded: true,
      );

      // Reinitialize if enabled
      if (currentSettings.enabled) {
        await _speechRecognition.dispose();
        await initialize();
      }

      return true;
    } else {
      // Need to download new model
      DB().voiceAssistantSettings = currentSettings.copyWith(
        modelType: newType,
        modelDownloaded: false,
        modelPath: '',
      );

      return false;
    }
  }

  /// Get model size in human-readable format
  Future<String?> getModelSize() async {
    final int? sizeBytes = await _modelDownloader.getModelSize(
      settings.modelType,
      settings.language,
    );

    if (sizeBytes != null) {
      return ModelDownloader.formatBytes(sizeBytes);
    }

    return null;
  }
}
