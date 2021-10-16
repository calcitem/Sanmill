/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'preferences.g.dart';

/// Preferece data model
///
/// holds the data needed for the normal Settings
@HiveType(typeId: 2)
@JsonSerializable()
@immutable
class Preferences {
  const Preferences({
    this.isPrivacyPolicyAccepted = false,
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
    this.algorithm = 2,
    this.drawOnHumanExperience = true,
    this.considerMobility = true,
    this.developerMode = false,
    this.experimentsEnabled = false,
  });

  @HiveField(0)
  final bool isPrivacyPolicyAccepted;
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
  @HiveField(15)
  final int algorithm;
  @HiveField(16)
  final bool drawOnHumanExperience;
  @HiveField(17)
  final bool considerMobility;
  @HiveField(18)
  final bool developerMode;
  @HiveField(19)
  final bool experimentsEnabled;

  /// returns a modified copy of the [Preferences] object
  Preferences copyWith({
    bool? isPrivacyPolicyAccepted,
    bool? usesHiveDB,
    bool? toneEnabled,
    bool? keepMuteWhenTakingBack,
    bool? screenReaderSupport,
    bool? aiMovesFirst,
    bool? aiIsLazy,
    int? skillLevel,
    int? moveTime,
    bool? isAutoRestart,
    bool? isAutoChangeFirstMove,
    bool? resignIfMostLose,
    bool? shufflingEnabled,
    bool? learnEndgame,
    bool? openingBook,
    int? algorithm,
    bool? drawOnHumanExperience,
    bool? considerMobility,
    bool? developerMode,
    bool? experimentsEnabled,
  }) =>
      Preferences(
        isPrivacyPolicyAccepted:
            isPrivacyPolicyAccepted ?? this.isPrivacyPolicyAccepted,
        usesHiveDB: usesHiveDB ?? this.usesHiveDB,
        toneEnabled: toneEnabled ?? this.toneEnabled,
        keepMuteWhenTakingBack:
            keepMuteWhenTakingBack ?? this.keepMuteWhenTakingBack,
        screenReaderSupport: screenReaderSupport ?? this.screenReaderSupport,
        aiMovesFirst: aiMovesFirst ?? this.aiMovesFirst,
        aiIsLazy: aiIsLazy ?? this.aiIsLazy,
        skillLevel: skillLevel ?? this.skillLevel,
        moveTime: moveTime ?? this.moveTime,
        isAutoRestart: isAutoRestart ?? this.isAutoRestart,
        isAutoChangeFirstMove:
            isAutoChangeFirstMove ?? this.isAutoChangeFirstMove,
        resignIfMostLose: resignIfMostLose ?? this.resignIfMostLose,
        shufflingEnabled: shufflingEnabled ?? this.shufflingEnabled,
        learnEndgame: learnEndgame ?? this.learnEndgame,
        openingBook: openingBook ?? this.openingBook,
        algorithm: algorithm ?? this.algorithm,
        drawOnHumanExperience:
            drawOnHumanExperience ?? this.drawOnHumanExperience,
        considerMobility: considerMobility ?? this.considerMobility,
        developerMode: developerMode ?? this.developerMode,
        experimentsEnabled: experimentsEnabled ?? this.experimentsEnabled,
      );

  /// encodes a Json style map into a [Preferences] obbject
  factory Preferences.fromJson(Map<String, dynamic> json) =>
      _$PreferencesFromJson(json);

  /// decodes a Json from a [Preferences] obbject
  Map<String, dynamic> toJson() => _$PreferencesToJson(this);
}
