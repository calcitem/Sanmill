// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// voice_assistant_settings.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'voice_assistant_settings.g.dart';

/// Supported Whisper model types
@HiveType(typeId: 14)
enum WhisperModelType {
  @HiveField(0)
  tiny,
  @HiveField(1)
  base,
  @HiveField(2)
  small,
  @HiveField(3)
  medium,
}

extension WhisperModelTypeName on WhisperModelType {
  String get name {
    switch (this) {
      case WhisperModelType.tiny:
        return 'Tiny (~75 MB)';
      case WhisperModelType.base:
        return 'Base (~142 MB)';
      case WhisperModelType.small:
        return 'Small (~466 MB)';
      case WhisperModelType.medium:
        return 'Medium (~1.5 GB)';
    }
  }

  String get fileName {
    switch (this) {
      case WhisperModelType.tiny:
        return 'ggml-tiny.bin';
      case WhisperModelType.base:
        return 'ggml-base.bin';
      case WhisperModelType.small:
        return 'ggml-small.bin';
      case WhisperModelType.medium:
        return 'ggml-medium.bin';
    }
  }

  // Base download URL for Whisper models
  String getDownloadUrl(String language) {
    final String modelName = fileName;
    if (language == 'en') {
      // English models
      return 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelName';
    } else {
      // Multilingual models
      return 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelName';
    }
  }
}

/// VoiceAssistantSettings data model
///
/// Holds the configuration for the voice assistant feature
@HiveType(typeId: 15)
@JsonSerializable()
@CopyWith()
@immutable
class VoiceAssistantSettings {
  const VoiceAssistantSettings({
    this.enabled = false,
    this.modelType = WhisperModelType.tiny,
    this.language = 'en',
    this.modelDownloaded = false,
    this.modelPath = '',
    this.autoDetectLanguage = false,
    this.showVoiceButton = true,
    this.continuousListening = false,
    this.downloadProgress = -1.0,
  });

  /// Encodes a Json style map into a [VoiceAssistantSettings] object
  factory VoiceAssistantSettings.fromJson(Map<String, dynamic> json) =>
      _$VoiceAssistantSettingsFromJson(json);

  /// Whether voice assistant is enabled
  @HiveField(0, defaultValue: false)
  final bool enabled;

  /// Whisper model type to use
  @HiveField(1, defaultValue: WhisperModelType.tiny)
  final WhisperModelType modelType;

  /// Language code for the voice recognition (e.g., 'en', 'zh', 'de')
  @HiveField(2, defaultValue: 'en')
  final String language;

  /// Whether the model file has been downloaded
  @HiveField(3, defaultValue: false)
  final bool modelDownloaded;

  /// Local path to the downloaded model file
  @HiveField(4, defaultValue: '')
  final String modelPath;

  /// Auto-detect language from app locale
  @HiveField(5, defaultValue: false)
  final bool autoDetectLanguage;

  /// Show voice button in game interface
  @HiveField(6, defaultValue: true)
  final bool showVoiceButton;

  /// Enable continuous listening mode
  @HiveField(7, defaultValue: false)
  final bool continuousListening;

  /// Download progress (0.0 to 1.0), -1.0 means no download in progress
  @HiveField(8, defaultValue: -1.0)
  final double downloadProgress;

  /// Decodes a Json from a [VoiceAssistantSettings] object
  Map<String, dynamic> toJson() => _$VoiceAssistantSettingsToJson(this);
}
