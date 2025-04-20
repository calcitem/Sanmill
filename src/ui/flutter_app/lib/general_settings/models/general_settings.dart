// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// general_settings.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/config/prompt_defaults.dart';

part 'general_settings.g.dart';

@HiveType(typeId: 5)
enum SearchAlgorithm {
  @HiveField(0)
  alphaBeta,
  @HiveField(1)
  pvs,
  @HiveField(2)
  mtdf,
  @HiveField(3)
  mcts,
  @HiveField(4)
  random,
}

@HiveType(typeId: 11)
enum SoundTheme {
  @HiveField(0)
  ball,
  @HiveField(1)
  liquid,
  @HiveField(2)
  wood,
}

@HiveType(typeId: 13)
enum LlmProvider {
  @HiveField(0)
  openai,
  @HiveField(1)
  google,
  @HiveField(2)
  ollama,
}

extension SearchAlgorithmName on SearchAlgorithm {
  String get name {
    switch (this) {
      case SearchAlgorithm.alphaBeta:
        return 'Alpha-Beta';
      case SearchAlgorithm.pvs:
        return 'PVS';
      case SearchAlgorithm.mtdf:
        return 'MTD(f)';
      case SearchAlgorithm.mcts:
        return 'MCTS';
      case SearchAlgorithm.random:
        return 'Random';
    }
  }
}

extension SoundThemeName on SoundTheme {
  String get name {
    switch (this) {
      case SoundTheme.ball:
        return 'ball';
      case SoundTheme.liquid:
        return 'liquid';
      case SoundTheme.wood:
        return 'wood';
    }
  }

  String localeName(BuildContext context) {
    switch (this) {
      case SoundTheme.ball:
        return S.of(context).ball;
      case SoundTheme.liquid:
        return S.of(context).liquid;
      case SoundTheme.wood:
        return S.of(context).wood;
    }
  }
}

extension LlmProviderName on LlmProvider {
  String get name {
    switch (this) {
      case LlmProvider.openai:
        return 'OpenAI API';
      case LlmProvider.google:
        return 'Google Gemini API';
      case LlmProvider.ollama:
        return 'Ollama API';
    }
  }
}

/// GeneralSettings data model
///
/// Holds the data needed for the General Settings
@HiveType(typeId: 2)
@JsonSerializable()
@CopyWith()
@immutable
class GeneralSettings {
  const GeneralSettings({
    this.isPrivacyPolicyAccepted = false,
    @Deprecated(
        "As this is not a user facing preference we migrated it into another box")
    this.usesHiveDB = false,
    this.toneEnabled = true,
    this.keepMuteWhenTakingBack = true,
    this.screenReaderSupport = false,
    this.aiMovesFirst = false,
    this.aiIsLazy = false,
    this.skillLevel = 1,
    this.moveTime = 1,
    this.humanMoveTime = 0,
    this.isAutoRestart = false,
    this.isAutoChangeFirstMove = false,
    this.resignIfMostLose = false,
    this.shufflingEnabled = true,
    this.learnEndgame = false,
    @Deprecated('Use [useOpeningBook] instead') this.openingBook = false,
    @Deprecated(
        'This only represents the old algorithm type. Use [searchAlgorithm] instead')
    this.algorithm = 2,
    this.searchAlgorithm = SearchAlgorithm.mtdf,
    this.usePerfectDatabase = false,
    this.drawOnHumanExperience = true,
    this.considerMobility = true,
    this.focusOnBlockingPaths = false,
    @Deprecated(
        "We won't export the developer settings anymore. People should use the EnvironmentConfig.devMode")
    this.developerMode = false,
    @Deprecated("Use [EnvironmentConfig.devMode] instead")
    this.experimentsEnabled = false,
    this.firstRun = true,
    this.gameScreenRecorderSupport = false,
    this.gameScreenRecorderDuration = 2,
    this.gameScreenRecorderPixelRatio = 50,
    this.showTutorial = true,
    this.remindedOpponentMayFly = false,
    this.vibrationEnabled = false,
    this.soundTheme = SoundTheme.ball,
    this.useOpeningBook = false,
    this.llmPromptHeader = '',
    this.llmPromptFooter = '',
    this.llmProvider = LlmProvider.openai,
    this.llmModel = '',
    this.llmApiKey = '',
    this.llmBaseUrl = '',
    this.llmTemperature = 0.7,
  });

  /// Encodes a Json style map into a [GeneralSettings] object
  factory GeneralSettings.fromJson(Map<String, dynamic> json) =>
      _$GeneralSettingsFromJson(json);

  @HiveField(0, defaultValue: false)
  final bool isPrivacyPolicyAccepted;

  @HiveField(1, defaultValue: true)
  final bool toneEnabled;

  @HiveField(2, defaultValue: true)
  final bool keepMuteWhenTakingBack;

  @HiveField(3, defaultValue: false)
  final bool screenReaderSupport;

  @HiveField(4, defaultValue: false)
  final bool aiMovesFirst;

  @HiveField(5, defaultValue: false)
  final bool aiIsLazy;

  @HiveField(6, defaultValue: 1)
  final int skillLevel;

  @HiveField(7, defaultValue: 1)
  final int moveTime;

  @HiveField(8, defaultValue: false)
  final bool isAutoRestart;

  @HiveField(9, defaultValue: false)
  final bool isAutoChangeFirstMove;

  @HiveField(10, defaultValue: false)
  final bool resignIfMostLose;

  @HiveField(11, defaultValue: true)
  final bool shufflingEnabled;

  @HiveField(12, defaultValue: false)
  final bool learnEndgame;

  @Deprecated('Use [useOpeningBook] instead')
  @HiveField(13, defaultValue: false)
  final bool openingBook;

  @Deprecated(
      'This only represents the old algorithm type. Use [searchAlgorithm] instead')
  @HiveField(14, defaultValue: 2)
  final int algorithm;

  @HiveField(15, defaultValue: true)
  final bool drawOnHumanExperience;

  @HiveField(16, defaultValue: true)
  final bool considerMobility;

  @Deprecated(
    "We won't export the developer settings anymore. People should use the EnvironmentConfig.devMode",
  )
  @HiveField(17, defaultValue: false)
  final bool developerMode;

  @Deprecated("Use [EnvironmentConfig.devMode] instead")
  @HiveField(18, defaultValue: false)
  final bool experimentsEnabled;

  @Deprecated(
    "As this is not a user facing preference we migrated it into another box",
  )
  @HiveField(19, defaultValue: false)
  final bool usesHiveDB;

  @HiveField(20, defaultValue: SearchAlgorithm.mtdf)
  final SearchAlgorithm? searchAlgorithm;

  @HiveField(21, defaultValue: true)
  final bool firstRun;

  @HiveField(22, defaultValue: false)
  final bool gameScreenRecorderSupport;

  @HiveField(23, defaultValue: 2)
  final int gameScreenRecorderDuration;

  @HiveField(24, defaultValue: 50)
  final int gameScreenRecorderPixelRatio;

  @HiveField(25, defaultValue: true)
  final bool showTutorial;

  @HiveField(26, defaultValue: false)
  final bool remindedOpponentMayFly;

  @HiveField(27, defaultValue: false)
  final bool usePerfectDatabase;

  @HiveField(28, defaultValue: false)
  final bool focusOnBlockingPaths;

  @HiveField(29, defaultValue: false)
  final bool vibrationEnabled;

  @HiveField(30, defaultValue: SoundTheme.ball)
  final SoundTheme? soundTheme;

  @HiveField(31, defaultValue: false)
  final bool useOpeningBook;

  @HiveField(32, defaultValue: 0)
  final int humanMoveTime;

  // The header part of LLM prompt
  @HiveField(33, defaultValue: "")
  final String llmPromptHeader;

  // The footer part of LLM prompt
  @HiveField(34, defaultValue: "")
  final String llmPromptFooter;

  @HiveField(35, defaultValue: LlmProvider.openai)
  final LlmProvider llmProvider;

  @HiveField(36, defaultValue: "")
  final String llmModel;

  @HiveField(37, defaultValue: "")
  final String llmApiKey;

  @HiveField(38, defaultValue: "")
  final String llmBaseUrl;

  @HiveField(39, defaultValue: 0.7)
  final double llmTemperature;

  /// Decodes a Json from a [GeneralSettings] object
  Map<String, dynamic> toJson() => _$GeneralSettingsToJson(this);

  // For backwards compatibility with code that uses static properties
  static String get defaultLlmPromptHeader => PromptDefaults.llmPromptHeader;

  static String get defaultLlmPromptFooter => PromptDefaults.llmPromptFooter;
}
