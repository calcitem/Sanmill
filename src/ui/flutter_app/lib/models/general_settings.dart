// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'package:sanmill/services/database/adapters/adapters.dart';

part 'general_settings.g.dart';

@HiveType(typeId: 5)
enum Algorithms {
  @HiveField(0)
  alphaBeta,
  @HiveField(1)
  pvs,
  @HiveField(2)
  mtdf,
}

extension AlgorithmNames on Algorithms {
  String get name {
    switch (this) {
      case Algorithms.alphaBeta:
        return 'Alpha-Beta';
      case Algorithms.pvs:
        return 'PVS';
      case Algorithms.mtdf:
        return 'MTD(f)';
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
    @Deprecated("As this is not a user facing preference we migrated it into another box")
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
    this.algorithm = Algorithms.mtdf,
    @Deprecated('This only represents the old algorithm type. Use [algorithm] instead')
        this.oldAlgorithm = 0,
    this.drawOnHumanExperience = true,
    this.considerMobility = true,
    @Deprecated("We won't export the developer settings anymore. People should use the EnvironmentConfig.devMode")
        this.developerMode = false,
    @Deprecated("Use [EnvironmentConfig.devMode] instead")
        this.experimentsEnabled = false,
  });

  @HiveField(0)
  final bool isPrivacyPolicyAccepted;
  @Deprecated(
    "As this is not a user facing preference we migrated it into another box",
  )
  @HiveField(1)
  final bool usesHiveDB;

  @HiveField(2)
  final bool toneEnabled;
  @HiveField(3)
  final bool keepMuteWhenTakingBack;
  @HiveField(4)
  final bool screenReaderSupport;
  @HiveField(5)
  final bool aiMovesFirst;
  @HiveField(6)
  final bool aiIsLazy;
  @HiveField(7)
  final int skillLevel;
  @HiveField(8)
  final int moveTime;
  @HiveField(9)
  final bool isAutoRestart;
  @HiveField(10)
  final bool isAutoChangeFirstMove;
  @HiveField(11)
  final bool resignIfMostLose;
  @HiveField(12)
  final bool shufflingEnabled;
  @HiveField(13)
  final bool learnEndgame;
  @HiveField(14)
  final bool openingBook;
  @JsonKey(
    fromJson: AlgorithmAdapter.algorithmFromJson,
    toJson: AlgorithmAdapter.algorithmToJson,
  )
  @HiveField(20)
  final Algorithms? algorithm;
  @Deprecated('This only represents the old algorithm type')
  @HiveField(15)
  final int oldAlgorithm;
  @HiveField(16)
  final bool drawOnHumanExperience;
  @HiveField(17)
  final bool considerMobility;
  @HiveField(18)
  @Deprecated(
    "We won't export the developer settings anymore. People should use the EnvironmentConfig.devMode",
  )
  final bool developerMode;
  @HiveField(19)
  @Deprecated("Use [EnvironmentConfig.devMode] instead")
  final bool experimentsEnabled;

  /// Encodes a Json style map into a [GeneralSettings] object
  factory GeneralSettings.fromJson(Map<String, dynamic> json) =>
      _$GeneralSettingsFromJson(json);

  /// Decodes a Json from a [GeneralSettings] object
  Map<String, dynamic> toJson() => _$GeneralSettingsToJson(this);
}
