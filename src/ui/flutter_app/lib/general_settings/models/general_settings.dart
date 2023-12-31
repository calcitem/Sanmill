// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

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
    this.isAutoRestart = false,
    this.isAutoChangeFirstMove = false,
    this.resignIfMostLose = false,
    this.shufflingEnabled = true,
    this.learnEndgame = false,
    this.openingBook = false,
    @Deprecated(
        'This only represents the old algorithm type. Use [searchAlgorithm] instead')
    this.algorithm = 2,
    this.searchAlgorithm = SearchAlgorithm.mtdf,
    this.usePerfectDatabase = false,
    this.drawOnHumanExperience = true,
    this.considerMobility = true,
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
  });

  /// Encodes a Json style map into a [GeneralSettings] object
  factory GeneralSettings.fromJson(Map<String, dynamic> json) =>
      _$GeneralSettingsFromJson(json);

  @HiveField(0)
  final bool isPrivacyPolicyAccepted;

  @HiveField(1)
  final bool toneEnabled;

  @HiveField(2)
  final bool keepMuteWhenTakingBack;

  @HiveField(3)
  final bool screenReaderSupport;

  @HiveField(4)
  final bool aiMovesFirst;

  @HiveField(5)
  final bool aiIsLazy;

  @HiveField(6)
  final int skillLevel;

  @HiveField(7)
  final int moveTime;

  @HiveField(8)
  final bool isAutoRestart;

  @HiveField(9)
  final bool isAutoChangeFirstMove;

  @HiveField(10)
  final bool resignIfMostLose;

  @HiveField(11)
  final bool shufflingEnabled;

  @HiveField(12)
  final bool learnEndgame;

  @HiveField(13)
  final bool openingBook;

  @Deprecated(
      'This only represents the old algorithm type. Use [searchAlgorithm] instead')
  @HiveField(14)
  final int algorithm;

  @HiveField(15)
  final bool drawOnHumanExperience;

  @HiveField(16)
  final bool considerMobility;

  @Deprecated(
    "We won't export the developer settings anymore. People should use the EnvironmentConfig.devMode",
  )
  @HiveField(17)
  final bool developerMode;

  @Deprecated("Use [EnvironmentConfig.devMode] instead")
  @HiveField(18)
  final bool experimentsEnabled;

  @Deprecated(
    "As this is not a user facing preference we migrated it into another box",
  )
  @HiveField(19)
  final bool usesHiveDB;

  @HiveField(20)
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

  /// Decodes a Json from a [GeneralSettings] object
  Map<String, dynamic> toJson() => _$GeneralSettingsToJson(this);
}
